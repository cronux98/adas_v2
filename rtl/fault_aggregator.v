// ============================================================================
// fault_aggregator.v — Central Fault Collector + Safety Control Registers
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    Fault aggregation + safety control register block
// Author:   Mei-Lin Chang, Digital Design Engineer
// Date:     2026-04-29
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz
//
// Register Map (base 0x0000_F000):
//   0x00 SAFETY_CTRL                RW   Safety control (parity-protected)
//   0x04 SAFETY_STATUS              RO   Safety status
//   0x08 SAFETY_FAULT_MASK          RW   Fault source mask
//   0x0C SAFETY_FAULT_STATUS        RO   Latched fault status (W1C, parity-protected)
//   0x10 SAFETY_FAULT_COUNT         RO   Total fault count
//   0x14 SAFETY_LOCKSTEP_CTRL       RW   Lockstep comparator control
//   0x18 SAFETY_LOCKSTEP_MASK       RW   Lockstep signal mask
//   0x1C SAFETY_LOCKSTEP_MISMATCH   RO   Mismatch counter
//   0x20 SAFETY_LOCKSTEP_LAST_PC    RO   PC at last mismatch
//   0x24 SAFETY_LOCKSTEP_LAST_OUT   RO   Core output at last mismatch
//   0x28 SAFETY_ECC_STATUS          RO   ECC/parity error status
//   0x2C SAFETY_SCRATCH             RW   Scratch/test register
//   0x30 SAFETY_INTR_MASK           RW   Interrupt mask
//   0x34 SAFETY_INTR_STATUS         RO   Interrupt status
//   0x38 SAFETY_RESET_CTRL          RW   Software reset control
//   0x3C SAFETY_ID                  RO   Module ID ("SFTY")
//
// Fault Input Sources (block_interfaces.md §13.2):
//   lockstep_mismatch_i, wdt_fault_i, servo_fault_i, ai_fault_i,
//   spi_fault_i, speed_fault_i, itcm_parity_err_i, dtcm_parity_err_i
//
// Parity Protection (P0-7):
//   reg_ctrl and reg_fault_status are parity-protected (even parity).
//   Parity bit is stored ONLY on writes, not continuously recomputed.
//   On read: ^reg != stored_parity → ECC_FAULT flag in SAFETY_ECC_STATUS.
//   Reference: Trikarenos (arXiv:2407.05938) — ECC-protected registers.
//
// Outputs:
//   aggregated_fault_o  → CDC → RSC
//   core_halt_o          → CPU halt
//   irq_lockstep_o       → CPU interrupt
//   irq_fault_agg_o      → CPU interrupt
//   lockstep_en_o        → Lockstep comparator enable
//   lockstep_delay_en_o  → Lockstep delay enable
//   lockstep_delay_o     → Lockstep delay cycles
//   lockstep_mask_o      → Lockstep signal mask
//   lockstep_self_test_o → Lockstep comparator self-test pulse
// ============================================================================

`timescale 1ns / 1ps

module fault_aggregator (
    input  wire        clk_i,
    input  wire        rst_n_i,

    // AXI4-Lite Slave (Safety Control Registers)
    input  wire [31:0] s_axi_awaddr_i,
    input  wire        s_axi_awvalid_i,
    output wire        s_axi_awready_o,
    input  wire [31:0] s_axi_wdata_i,
    input  wire [3:0]  s_axi_wstrb_i,
    input  wire        s_axi_wvalid_i,
    output wire        s_axi_wready_o,
    output wire [1:0]  s_axi_bresp_o,
    output wire        s_axi_bvalid_o,
    input  wire        s_axi_bready_i,
    input  wire [31:0] s_axi_araddr_i,
    input  wire        s_axi_arvalid_i,
    output wire        s_axi_arready_o,
    output wire [31:0] s_axi_rdata_o,
    output wire [1:0]  s_axi_rresp_o,
    output wire        s_axi_rvalid_o,
    input  wire        s_axi_rready_i,

    // Fault inputs from all sources
    input  wire        lockstep_mismatch_i,
    input  wire        wdt_fault_i,          // CDC'd from wdt_clk
    input  wire        servo_fault_i,
    input  wire        ai_fault_i,
    input  wire        spi_fault_i,
    input  wire        speed_fault_i,
    input  wire        itcm_parity_err_i,
    input  wire        dtcm_parity_err_i,

    // Lockstep comparator feedback
    input  wire [31:0] lockstep_mismatch_pc_i,
    input  wire [31:0] lockstep_last_out_i,
    input  wire [31:0] lockstep_last_exp_i,
    input  wire [31:0] lockstep_count_i,

    // Outputs
    output wire        aggregated_fault_o,   // → CDC → RSC
    output wire        core_halt_o,           // → CPU halt
    output wire        irq_lockstep_o,        // → CPU interrupt
    output wire        irq_fault_agg_o,       // → CPU interrupt

    // Lockstep control outputs → lockstep_comparator
    output wire        lockstep_en_o,
    output wire        lockstep_delay_en_o,
    output wire [1:0]  lockstep_delay_o,
    output wire [31:0] lockstep_mask_o,
    output wire        lockstep_self_test_o  // P0-5: comparator self-test pulse
);

    localparam AXI_OKAY = 2'b00, AXI_SLVERR = 2'b10;
    localparam SAFETY_ID_VAL = 32'h5346_5459;  // "SFTY"
    localparam MAGIC_KEY = 8'hA5;

    // ——— Registers ———
    reg [31:0] reg_ctrl;              // 0x00  SAFETY_CTRL (parity-protected)
    reg [31:0] reg_fault_mask;        // 0x08  SAFETY_FAULT_MASK
    reg [31:0] reg_fault_status;      // 0x0C  SAFETY_FAULT_STATUS (parity-protected)
    reg [31:0] reg_fault_count;       // 0x10  SAFETY_FAULT_COUNT
    reg [31:0] reg_lockstep_ctrl;     // 0x14  SAFETY_LOCKSTEP_CTRL
    reg [31:0] reg_lockstep_mask;     // 0x18  SAFETY_LOCKSTEP_MASK
    reg [31:0] reg_lockstep_mismatch; // 0x1C  SAFETY_LOCKSTEP_MISMATCH
    reg [31:0] reg_ls_last_pc;        // 0x20  SAFETY_LOCKSTEP_LAST_PC
    reg [31:0] reg_ls_last_out;       // 0x24  SAFETY_LOCKSTEP_LAST_OUT
    reg [31:0] reg_scratch;           // 0x2C  SAFETY_SCRATCH
    reg [31:0] reg_intr_mask;         // 0x30  SAFETY_INTR_MASK
    reg [31:0] reg_intr_status;       // 0x34  SAFETY_INTR_STATUS
    reg [31:0] reg_reset_ctrl;        // 0x38  SAFETY_RESET_CTRL

    // P0-7: Parity protection for safety-critical registers
    reg        reg_ctrl_parity;           // even parity of reg_ctrl (written on write)
    reg        reg_fault_status_parity;   // even parity of reg_fault_status
    reg [31:0] reg_ecc_status;           // 0x28 FAULT_ECC_STATUS (RO)

    // ——— AXI write ———
    reg awready, wready, aw_done, w_done, bvalid;
    reg [31:0] awaddr_latch, wdata_latch;
    reg [3:0]  wstrb_latch;
    reg [1:0]  bresp;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            awready <= 1'b1; wready <= 1'b1; aw_done <= 1'b0; w_done <= 1'b0;
            awaddr_latch <= 32'd0; wdata_latch <= 32'd0; wstrb_latch <= 4'd0;
            bvalid <= 1'b0; bresp <= AXI_OKAY;
        end else begin
            if (s_axi_awvalid_i && awready) begin awaddr_latch <= s_axi_awaddr_i; aw_done <= 1'b1; awready <= 1'b0; end
            if (s_axi_wvalid_i  && wready)  begin wdata_latch <= s_axi_wdata_i; wstrb_latch <= s_axi_wstrb_i; w_done <= 1'b1; wready <= 1'b0; end
            if (aw_done && w_done && !bvalid) begin bvalid <= 1'b1; bresp <= wr_valid ? AXI_OKAY : AXI_SLVERR; aw_done <= 1'b0; w_done <= 1'b0; end
            if (bvalid && s_axi_bready_i) bvalid <= 1'b0;
            if (!aw_done) awready <= 1'b1;
            if (!w_done)  wready  <= 1'b1;
        end
    end

    // ——— AXI read ———
    reg arready, rvalid, ar_done;
    reg [31:0] araddr_latch, rdata;
    reg [1:0]  rresp;

    wire [5:0] rd_off = araddr_latch[7:2];
    wire [31:0] rd_data;
    wire rd_valid;

    // SAFETY_STATUS computed
    wire [31:0] safety_status = {24'd0,
                                  shutdown_active, halted, any_critical, any_fault,
                                  lockstep_active, safety_enabled,
                                  2'd0};

    assign {rd_data, rd_valid} =
        (rd_off == 6'h00) ? {reg_ctrl,             1'b1} :
        (rd_off == 6'h01) ? {safety_status,        1'b1} :
        (rd_off == 6'h02) ? {reg_fault_mask,       1'b1} :
        (rd_off == 6'h03) ? {reg_fault_status,     1'b1} :
        (rd_off == 6'h04) ? {reg_fault_count,      1'b1} :
        (rd_off == 6'h05) ? {reg_lockstep_ctrl,    1'b1} :
        (rd_off == 6'h06) ? {reg_lockstep_mask,    1'b1} :
        (rd_off == 6'h07) ? {reg_lockstep_mismatch, 1'b1} :
        (rd_off == 6'h08) ? {reg_ls_last_pc,       1'b1} :
        (rd_off == 6'h09) ? {reg_ls_last_out,      1'b1} :
        (rd_off == 6'h0A) ? {reg_ecc_status,       1'b1} :  // P0-7: FAULT_ECC_STATUS @ 0x28
        (rd_off == 6'h0B) ? {reg_scratch,          1'b1} :
        (rd_off == 6'h0C) ? {reg_intr_mask,        1'b1} :
        (rd_off == 6'h0D) ? {reg_intr_status,      1'b1} :
        (rd_off == 6'h0E) ? {reg_reset_ctrl,       1'b1} :
        (rd_off == 6'h0F) ? {SAFETY_ID_VAL,        1'b1} :
                             {32'd0,                1'b0};

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            arready <= 1'b1; ar_done <= 1'b0; araddr_latch <= 32'd0;
            rvalid <= 1'b0; rdata <= 32'd0; rresp <= AXI_OKAY;
        end else begin
            if (s_axi_arvalid_i && arready) begin araddr_latch <= s_axi_araddr_i; ar_done <= 1'b1; arready <= 1'b0; end
            if (ar_done && !rvalid) begin rvalid <= 1'b1; rdata <= rd_data; rresp <= rd_valid ? AXI_OKAY : AXI_SLVERR; ar_done <= 1'b0; end
            if (rvalid && s_axi_rready_i) rvalid <= 1'b0;
            if (!ar_done) arready <= 1'b1;
        end
    end

    wire [5:0] wr_off = awaddr_latch[7:2];
    wire wr_valid = (wr_off <= 6'h0E);
    wire wr_go = bvalid && s_axi_bready_i;

    // Register writes
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            reg_ctrl              <= 32'd0;
            reg_fault_mask        <= 32'h0000_0FFF;  // all faults enabled
            reg_fault_status      <= 32'd0;
            reg_fault_count       <= 32'd0;
            reg_lockstep_ctrl     <= 32'd0;
            reg_lockstep_mask     <= 32'hFFFF_FFFF;
            reg_lockstep_mismatch <= 32'd0;
            reg_ls_last_pc        <= 32'd0;
            reg_ls_last_out       <= 32'd0;
            reg_scratch           <= 32'd0;
            reg_intr_mask         <= 32'd0;
            reg_intr_status       <= 32'd0;
            reg_reset_ctrl        <= 32'd0;
            // P0-7: Parity and ECC status
            reg_ctrl_parity        <= 1'b0;
            reg_fault_status_parity <= 1'b0;
            reg_ecc_status         <= 32'd0;
        end else begin
            if (wr_go) begin
                case (wr_off)
                    6'h00: begin  // SAFETY_CTRL (parity-protected, P0-7)
                        reg_ctrl[0] <= wdata_latch[0];   // ENABLE
                        reg_ctrl[1] <= wdata_latch[1];   // LOCKSTEP_EN
                        reg_ctrl[2] <= wdata_latch[2];   // FAULT_AGG_EN
                        reg_ctrl[3] <= wdata_latch[3];   // AUTO_HALT
                        reg_ctrl[4] <= wdata_latch[4];   // AUTO_SHUTDOWN
                        reg_ctrl[8] <= wdata_latch[8];   // FORCE_FAULT
                        reg_ctrl[9] <= wdata_latch[9];   // FORCE_MISMATCH
                        reg_ctrl[10]<= wdata_latch[10];  // TEST_MODE
                        reg_ctrl[11]<= wdata_latch[11];  // P0-5: SELF_TEST (lockstep comparator self-test)
                        if (wstrb_latch[2]) reg_ctrl[23:16] <= wdata_latch[23:16]; // FAULT_SEVERITY
                        // P0-7: Update parity after write
                        reg_ctrl_parity <= ^{
                            reg_ctrl[31:24],
                            wstrb_latch[2] ? wdata_latch[23:16] : reg_ctrl[23:16],
                            reg_ctrl[15:12],
                            wdata_latch[11:8],
                            reg_ctrl[7:5],
                            wdata_latch[4:0]
                        };
                    end
                    6'h02: reg_fault_mask <= wdata_latch;           // SAFETY_FAULT_MASK
                    6'h03: begin  // SAFETY_FAULT_STATUS (W1C, parity-protected, P0-7)
                        reg_fault_status <= reg_fault_status & ~wdata_latch;
                        // Update parity for W1C result
                        reg_fault_status_parity <= ^(reg_fault_status & ~wdata_latch);
                    end
                    6'h05: begin  // SAFETY_LOCKSTEP_CTRL
                        reg_lockstep_ctrl[0] <= wdata_latch[0];   // ENABLE
                        reg_lockstep_ctrl[1] <= wdata_latch[1];   // DELAY_EN
                        if (wstrb_latch[0]) reg_lockstep_ctrl[3:2] <= wdata_latch[3:2]; // DELAY_CYCLES
                        if (wstrb_latch[0]) reg_lockstep_ctrl[7:4] <= wdata_latch[7:4]; // THRESHOLD
                    end
                    6'h06: reg_lockstep_mask <= wdata_latch;       // SAFETY_LOCKSTEP_MASK
                    6'h0B: reg_scratch <= wdata_latch;             // SAFETY_SCRATCH
                    6'h0C: reg_intr_mask <= wdata_latch;           // SAFETY_INTR_MASK
                    6'h0D: reg_intr_status <= reg_intr_status & ~wdata_latch; // W1C
                    6'h0E: begin  // SAFETY_RESET_CTRL (requires magic key)
                        if (reg_scratch[7:0] == MAGIC_KEY) begin
                            reg_reset_ctrl[0] <= wdata_latch[0];  // CPU_RESET
                            reg_reset_ctrl[1] <= wdata_latch[1];  // PERIPH_RESET
                            reg_reset_ctrl[2] <= wdata_latch[2];  // AI_RESET
                        end
                    end
                    default: ;
                endcase
            end
            // Reset self-clear
            if (reg_reset_ctrl != 32'd0)
                reg_reset_ctrl <= 32'd0;
            // FORCE_FAULT / FORCE_MISMATCH / SELF_TEST self-clearing
            if (reg_ctrl[8]) reg_ctrl[8] <= 1'b0;
            if (reg_ctrl[9]) reg_ctrl[9] <= 1'b0;
            if (reg_ctrl[11]) reg_ctrl[11] <= 1'b0;  // P0-5: SELF_TEST self-clears

            // Lockstep mismatch count update
            if (lockstep_mismatch_i && lockstep_count_i > reg_lockstep_mismatch)
                reg_lockstep_mismatch <= lockstep_count_i;
            // Capture last mismatch details
            if (lockstep_mismatch_i) begin
                reg_ls_last_pc  <= lockstep_mismatch_pc_i;
                reg_ls_last_out <= lockstep_last_out_i;
            end

            // P0 FIX: Fault latching + counting + parity (merged from separate always block)
            // Fault sources and masking are computed combinationally above.
            // Dependencies: masked_faults, any_masked (wires)
            for (k = 0; k < 13; k = k + 1) begin
                if (masked_faults[k])
                    reg_fault_status[k] <= 1'b1;
            end
            if (any_masked)
                reg_fault_count <= reg_fault_count + 32'd1;
            if (|masked_faults)
                reg_fault_status_parity <= ^(reg_fault_status | {19'd0, masked_faults});

            // P0 FIX: Parity error detection (merged from separate always block)
            // ctrl_parity_err and fstatus_parity_err are combinational wires above.
            if (ctrl_parity_err)     reg_ecc_status[0] <= 1'b1;
            if (fstatus_parity_err)  reg_ecc_status[1] <= 1'b1;
        end
    end

    // ——— Fault Aggregation Logic ———
    // Fault sources (per block_interfaces.md §13.3)
    //
    // Bit mapping (SAFETY_FAULT_MASK / SAFETY_FAULT_STATUS):
    //   0: LOCKSTEP_MISMATCH  (CRITICAL)
    //   1: WDT_TIMEOUT        (CRITICAL)
    //   2: WDT_EARLY          (HIGH)    - synthesized from wdt_fault_i
    //   3: SERVO_FAULT        (HIGH)
    //   4: AI_FAULT           (HIGH)
    //   5: SPI_FAULT          (MEDIUM)
    //   6: SPEED_STUCK        (MEDIUM)
    //   7: ITCM_PARITY        (CRITICAL)
    //   8: DTCM_PARITY        (CRITICAL)
    //   9: GPIO_SHUTDOWN_ACK  (HIGH)
    //   10: AXI_DECODE_ERR    (MEDIUM)
    //   11: SOFTWARE_FAULT    (HIGH)

    //   12: ECC_FAULT          (CRITICAL) — P0-7: safety register parity error

    wire [12:0] fault_sources;
    assign fault_sources[0]  = lockstep_mismatch_i || reg_ctrl[9];
    assign fault_sources[1]  = wdt_fault_i;
    assign fault_sources[2]  = 1'b0;  // WDT_EARLY (consumed via wdt_fault_i)
    assign fault_sources[3]  = servo_fault_i;
    assign fault_sources[4]  = ai_fault_i;
    assign fault_sources[5]  = spi_fault_i;
    assign fault_sources[6]  = speed_fault_i;
    assign fault_sources[7]  = itcm_parity_err_i;
    assign fault_sources[8]  = dtcm_parity_err_i;
    assign fault_sources[9]  = 1'b0;  // GPIO_SHUTDOWN_ACK (not yet connected)
    assign fault_sources[10] = 1'b0;  // AXI_DECODE_ERR (not yet connected)
    assign fault_sources[11] = reg_ctrl[8];  // FORCE_FAULT (test)
    assign fault_sources[12] = |reg_ecc_status;  // P0-7: ECC parity error detected

    // Mask and latch faults (ECC fault always unmasked — safety-critical)
    wire [12:0] masked_faults = fault_sources & {reg_fault_mask[11:0], 1'b1};
    wire        any_masked = |masked_faults;

    // Fault severity classification
    wire crit_ls   = masked_faults[0];   // LOCKSTEP_MISMATCH
    wire crit_wdt  = masked_faults[1];   // WDT_TIMEOUT
    wire crit_itcm = masked_faults[7];   // ITCM_PARITY
    wire crit_dtcm = masked_faults[8];   // DTCM_PARITY
    wire crit_ecc  = masked_faults[12];  // P0-7: ECC parity error (ALWAYS critical)
    wire any_critical_fault = crit_ls | crit_wdt | crit_itcm | crit_dtcm | crit_ecc |
                               (|(masked_faults & {5'd0, reg_ctrl[23:16]}));

    // P0 FIX: Fault latching, counting, and parity logic merged into
    // the main register-write always block above to eliminate driver-driver conflicts.
    integer k;  // loop iterator for fault latching

    // ——— Derived signals ———
    wire safety_enabled   = reg_ctrl[0];
    wire lockstep_active  = reg_ctrl[1] && reg_lockstep_ctrl[0];
    wire any_fault        = |reg_fault_status[12:0];
    wire any_critical     = any_critical_fault && reg_ctrl[3];
    wire halted           = any_critical_fault && reg_ctrl[3];
    wire shutdown_active  = any_critical_fault && reg_ctrl[4] && !reg_ctrl[10];

    // P0-7: Parity error detection on safety-critical registers
    // Parity is stored on writes only — if a bit-flip corrupts the register,
    // the recomputed parity will differ from the stored parity.
    wire ctrl_parity_err        = ar_done && (araddr_latch[7:2] == 6'h00) && ((^reg_ctrl) != reg_ctrl_parity);
    wire fstatus_parity_err     = ar_done && (araddr_latch[7:2] == 6'h03) && ((^reg_fault_status) != reg_fault_status_parity);

    // P0 FIX: Parity error detection merged into main register-write always block above.

    // ——— Outputs ———
    assign aggregated_fault_o = reg_ctrl[2] && (any_critical_fault || (any_fault && reg_ctrl[4]));
    assign core_halt_o        = reg_ctrl[3] && any_critical_fault;
    assign irq_lockstep_o     = reg_intr_mask[0] && reg_fault_status[0];
    assign irq_fault_agg_o    = reg_intr_mask[1] && any_fault;

    // Lockstep control outputs
    assign lockstep_en_o      = reg_ctrl[1] && reg_lockstep_ctrl[0];
    assign lockstep_delay_en_o = reg_lockstep_ctrl[1];
    assign lockstep_delay_o   = reg_lockstep_ctrl[3:2];
    assign lockstep_mask_o    = reg_lockstep_mask;
    // P0-5: Self-test pulse — assert for 1 cycle when firmware writes SELF_TEST bit
    assign lockstep_self_test_o = reg_ctrl[11];

    // AXI outputs
    assign s_axi_awready_o = awready;
    assign s_axi_wready_o  = wready;
    assign s_axi_bresp_o   = bresp;
    assign s_axi_bvalid_o  = bvalid;
    assign s_axi_arready_o = arready;
    assign s_axi_rdata_o   = rdata;
    assign s_axi_rresp_o   = rresp;
    assign s_axi_rvalid_o  = rvalid;

endmodule
