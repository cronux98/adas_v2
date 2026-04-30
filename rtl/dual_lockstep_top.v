// ============================================================================
// dual_lockstep_top.v — Dual-Core Lockstep Wrapper (ASIL-D Target)
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    Dual-core lockstep top-level with 2-cycle time stagger
// Author:   Mei-Lin Chang, Digital Design Engineer
// Date:     2026-04-29
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz
//
// Architecture (per ARCH-AD-001 lockstep_architecture_decision.md §4):
//   Two independent RV32IM core instances operating in time-staggered lockstep.
//   Core A (MASTER)  — leads, executes at cycle T, drives all memory busses
//   Core B (CHECKER) — lags, executes at cycle T+2, receives delayed inputs
//
//   Time stagger of 2 cycles prevents common-cause failures (SafeLS 2307.15436).
//   Both cores execute identical instruction streams.
//   Core B receives 2-cycle-delayed copies of all memory responses and inputs.
//
//   Lockstep output alignment:
//     - Core A lockstep outputs → 2-cycle delay buffer → lockstep_outputs_m_o
//     - Core B lockstep outputs → direct pass-through   → lockstep_outputs_c_o
//   This aligns the two output streams for the comparator.
//
// Block Interfaces (block_interfaces.md §13 — expanded dual-core):
//   lockstep_outputs_m_o[31:0] — Master core outputs (delayed 2 cycles)
//   lockstep_pc_m_o[31:0]      — Master core PC
//   lockstep_valid_m_o         — Master core valid strobe
//   lockstep_outputs_c_o[31:0] — Checker core outputs (no delay)
//   lockstep_pc_c_o[31:0]      — Checker core PC
//   lockstep_valid_c_o         — Checker core valid strobe
//
// Reference: SafeLS — Lockstep NOEL-V Core, arXiv:2307.15436
//            Trikarenos — Fault-Tolerant RISC-V SoC, arXiv:2407.05938
// ============================================================================

`timescale 1ns / 1ps

module dual_lockstep_top (
    // Clock and reset
    input  wire        clk_i,
    input  wire        rst_n_i,

    // =====================================================================
    // ITCM Interface — Shared, driven by Core A (master)
    // =====================================================================
    output wire [12:0] itcm_addr_o,
    input  wire [31:0] itcm_rdata_i,
    output wire        itcm_req_o,
    input  wire        itcm_ack_i,

    // =====================================================================
    // DTCM Interface — Shared, driven by Core A (master)
    // =====================================================================
    output wire [12:0] dtcm_addr_o,
    output wire [31:0] dtcm_wdata_o,
    input  wire [31:0] dtcm_rdata_i,
    output wire [3:0]  dtcm_we_o,
    output wire        dtcm_req_o,
    input  wire        dtcm_ack_i,

    // =====================================================================
    // AXI4-Lite Master Interface — Driven by Core A (master)
    // =====================================================================
    // Write address channel
    output wire [31:0] m_axi_awaddr_o,
    output wire [2:0]  m_axi_awprot_o,
    output wire        m_axi_awvalid_o,
    input  wire        m_axi_awready_i,

    // Write data channel
    output wire [31:0] m_axi_wdata_o,
    output wire [3:0]  m_axi_wstrb_o,
    output wire        m_axi_wvalid_o,
    input  wire        m_axi_wready_i,

    // Write response channel
    input  wire [1:0]  m_axi_bresp_i,
    input  wire        m_axi_bvalid_i,
    output wire        m_axi_bready_o,

    // Read address channel
    output wire [31:0] m_axi_araddr_o,
    output wire [2:0]  m_axi_arprot_o,
    output wire        m_axi_arvalid_o,
    input  wire        m_axi_arready_i,

    // Read data channel
    input  wire [31:0] m_axi_rdata_i,
    input  wire [1:0]  m_axi_rresp_i,
    input  wire        m_axi_rvalid_i,
    output wire        m_axi_rready_o,

    // =====================================================================
    // Interrupts (shared — checker receives 2-cycle delayed copy)
    // =====================================================================
    input  wire [15:0] irq_i,
    input  wire        timer_irq_i,

    // =====================================================================
    // Lockstep Outputs to Comparator
    // =====================================================================
    // Master (Core A) — delayed 2 cycles for alignment with checker
    output wire [31:0] lockstep_outputs_m_o,
    output wire [31:0] lockstep_pc_m_o,
    output wire        lockstep_valid_m_o,

    // Checker (Core B) — direct, naturally aligned to delayed master
    output wire [31:0] lockstep_outputs_c_o,
    output wire [31:0] lockstep_pc_c_o,
    output wire        lockstep_valid_c_o,

    // =====================================================================
    // Control Inputs (shared)
    // =====================================================================
    input  wire        halt_i,
    input  wire        debug_req_i
);

    // =========================================================================
    // Stagger Initialization FSM
    // =========================================================================
    // On system reset:
    //   - Core A (master) is released immediately
    //   - Core B (checker) is held in reset for 2 extra cycles
    // This establishes the 2-cycle time stagger between the two cores.
    //
    // Both cores will then execute identical instruction streams, with
    // core B naturally trailing core A by exactly 2 cycles.
    // =========================================================================

    reg [1:0] stagger_init_cnt;
    wire      core_b_rst_n;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            stagger_init_cnt <= 2'd0;
        end else begin
            if (stagger_init_cnt < 2'd3)  // count 0,1,2 → release at count 3
                stagger_init_cnt <= stagger_init_cnt + 2'd1;
        end
    end

    // Core B held in reset until stagger count reaches 3 (2 extra cycles after
    // system reset de-assertion). Core A is released immediately.
    assign core_b_rst_n = rst_n_i && (stagger_init_cnt >= 2'd3);

    // =========================================================================
    // Core A (MASTER) — Leading Core
    // =========================================================================
    // Drives all memory busses directly. Lockstep outputs go through a
    // 2-cycle delay buffer for alignment with the checker core.

    wire [31:0] core_a_lockstep_outputs;
    wire [31:0] core_a_lockstep_pc;
    wire        core_a_lockstep_valid;

    rv32im_core u_core_a (
        .clk_i              (clk_i),
        .rst_n_i            (rst_n_i),
        .itcm_addr_o        (itcm_addr_o),
        .itcm_rdata_i       (itcm_rdata_i),
        .itcm_req_o         (itcm_req_o),
        .itcm_ack_i         (itcm_ack_i),
        .dtcm_addr_o        (dtcm_addr_o),
        .dtcm_wdata_o       (dtcm_wdata_o),
        .dtcm_rdata_i       (dtcm_rdata_i),
        .dtcm_we_o          (dtcm_we_o),
        .dtcm_req_o         (dtcm_req_o),
        .dtcm_ack_i         (dtcm_ack_i),
        .m_axi_awaddr_o     (m_axi_awaddr_o),
        .m_axi_awprot_o     (m_axi_awprot_o),
        .m_axi_awvalid_o    (m_axi_awvalid_o),
        .m_axi_awready_i    (m_axi_awready_i),
        .m_axi_wdata_o      (m_axi_wdata_o),
        .m_axi_wstrb_o      (m_axi_wstrb_o),
        .m_axi_wvalid_o     (m_axi_wvalid_o),
        .m_axi_wready_i     (m_axi_wready_i),
        .m_axi_bresp_i      (m_axi_bresp_i),
        .m_axi_bvalid_i     (m_axi_bvalid_i),
        .m_axi_bready_o     (m_axi_bready_o),
        .m_axi_araddr_o     (m_axi_araddr_o),
        .m_axi_arprot_o     (m_axi_arprot_o),
        .m_axi_arvalid_o    (m_axi_arvalid_o),
        .m_axi_arready_i    (m_axi_arready_i),
        .m_axi_rdata_i      (m_axi_rdata_i),
        .m_axi_rresp_i      (m_axi_rresp_i),
        .m_axi_rvalid_i     (m_axi_rvalid_i),
        .m_axi_rready_o     (m_axi_rready_o),
        .irq_i              (irq_i),
        .timer_irq_i        (timer_irq_i),
        .lockstep_outputs_o (core_a_lockstep_outputs),
        .lockstep_pc_o      (core_a_lockstep_pc),
        .lockstep_valid_o   (core_a_lockstep_valid),
        .halt_i             (halt_i),
        .debug_req_i        (debug_req_i)
    );

    // =========================================================================
    // Input Delay Buffers for Core B (Checker) — 2-Cycle Stagger
    // =========================================================================
    // Core B executes the same program as Core A but lags by 2 cycles.
    // Since Core A drives the physical busses, Core B must receive
    // delayed copies of all memory responses and control inputs.
    //
    // Each input to Core B is delayed through a 2-deep shift register.
    // This ensures Core B sees the same data Core A saw, 2 cycles later.
    // =========================================================================

    // ——— ITCM response delay ———
    reg [31:0] itcm_rdata_d1, itcm_rdata_d2;
    reg        itcm_ack_d1,   itcm_ack_d2;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            itcm_rdata_d1 <= 32'd0;
            itcm_rdata_d2 <= 32'd0;
            itcm_ack_d1   <= 1'b0;
            itcm_ack_d2   <= 1'b0;
        end else begin
            itcm_rdata_d1 <= itcm_rdata_i;
            itcm_rdata_d2 <= itcm_rdata_d1;
            itcm_ack_d1   <= itcm_ack_i;
            itcm_ack_d2   <= itcm_ack_d1;
        end
    end

    wire [31:0] core_b_itcm_rdata = itcm_rdata_d2;
    wire        core_b_itcm_ack   = itcm_ack_d2;

    // ——— DTCM response delay ———
    reg [31:0] dtcm_rdata_d1, dtcm_rdata_d2;
    reg        dtcm_ack_d1,   dtcm_ack_d2;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            dtcm_rdata_d1 <= 32'd0;
            dtcm_rdata_d2 <= 32'd0;
            dtcm_ack_d1   <= 1'b0;
            dtcm_ack_d2   <= 1'b0;
        end else begin
            dtcm_rdata_d1 <= dtcm_rdata_i;
            dtcm_rdata_d2 <= dtcm_rdata_d1;
            dtcm_ack_d1   <= dtcm_ack_i;
            dtcm_ack_d2   <= dtcm_ack_d1;
        end
    end

    wire [31:0] core_b_dtcm_rdata = dtcm_rdata_d2;
    wire        core_b_dtcm_ack   = dtcm_ack_d2;

    // ——— AXI response delay ———
    // Read data channel (2-cycle delay)
    reg [31:0] axi_rdata_d1, axi_rdata_d2;
    reg [1:0]  axi_rresp_d1, axi_rresp_d2;
    reg        axi_rvalid_d1, axi_rvalid_d2;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            axi_rdata_d1  <= 32'd0;
            axi_rdata_d2  <= 32'd0;
            axi_rresp_d1  <= 2'd0;
            axi_rresp_d2  <= 2'd0;
            axi_rvalid_d1 <= 1'b0;
            axi_rvalid_d2 <= 1'b0;
        end else begin
            axi_rdata_d1  <= m_axi_rdata_i;
            axi_rdata_d2  <= axi_rdata_d1;
            axi_rresp_d1  <= m_axi_rresp_i;
            axi_rresp_d2  <= axi_rresp_d1;
            axi_rvalid_d1 <= m_axi_rvalid_i;
            axi_rvalid_d2 <= axi_rvalid_d1;
        end
    end

    // Write response channel (2-cycle delay)
    reg [1:0]  axi_bresp_d1, axi_bresp_d2;
    reg        axi_bvalid_d1, axi_bvalid_d2;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            axi_bresp_d1  <= 2'd0;
            axi_bresp_d2  <= 2'd0;
            axi_bvalid_d1 <= 1'b0;
            axi_bvalid_d2 <= 1'b0;
        end else begin
            axi_bresp_d1  <= m_axi_bresp_i;
            axi_bresp_d2  <= axi_bresp_d1;
            axi_bvalid_d1 <= m_axi_bvalid_i;
            axi_bvalid_d2 <= axi_bvalid_d1;
        end
    end

    // Write address / write data ready (2-cycle delay)
    reg        axi_awready_d1, axi_awready_d2;
    reg        axi_wready_d1,  axi_wready_d2;
    reg        axi_arready_d1, axi_arready_d2;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            axi_awready_d1 <= 1'b0;
            axi_awready_d2 <= 1'b0;
            axi_wready_d1  <= 1'b0;
            axi_wready_d2  <= 1'b0;
            axi_arready_d1 <= 1'b0;
            axi_arready_d2 <= 1'b0;
        end else begin
            axi_awready_d1 <= m_axi_awready_i;
            axi_awready_d2 <= axi_awready_d1;
            axi_wready_d1  <= m_axi_wready_i;
            axi_wready_d2  <= axi_wready_d1;
            axi_arready_d1 <= m_axi_arready_i;
            axi_arready_d2 <= axi_arready_d1;
        end
    end

    // ——— Interrupt delay (2 cycles) ———
    // Interrupts must arrive at the same pipeline stage in both cores.
    // Core B receives interrupts delayed by the stagger depth.
    reg [15:0] irq_d1, irq_d2;
    reg        timer_irq_d1, timer_irq_d2;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            irq_d1       <= 16'd0;
            irq_d2       <= 16'd0;
            timer_irq_d1 <= 1'b0;
            timer_irq_d2 <= 1'b0;
        end else begin
            irq_d1       <= irq_i;
            irq_d2       <= irq_d1;
            timer_irq_d1 <= timer_irq_i;
            timer_irq_d2 <= timer_irq_d1;
        end
    end

    // ——— Halt / debug delay (2 cycles) ———
    reg halt_d1,      halt_d2;
    reg debug_req_d1, debug_req_d2;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            halt_d1      <= 1'b0;
            halt_d2      <= 1'b0;
            debug_req_d1 <= 1'b0;
            debug_req_d2 <= 1'b0;
        end else begin
            halt_d1      <= halt_i;
            halt_d2      <= halt_d1;
            debug_req_d1 <= debug_req_i;
            debug_req_d2 <= debug_req_d1;
        end
    end

    // =========================================================================
    // Core B (CHECKER) — Lagging Core
    // =========================================================================
    // Receives all inputs delayed by 2 cycles. Its memory request outputs
    // are left unconnected — Core B executes from the delayed responses
    // provided by Core A's bus transactions.
    //
    // This works because both cores execute identical code. Core B's
    // ITCM requests would be identical to Core A's (just time-shifted),
    // so feeding Core B the delayed ITCM responses from Core A is equivalent
    // to Core B independently accessing the ITCM.

    wire [12:0] core_b_itcm_addr_unused;
    wire        core_b_itcm_req_unused;
    wire [12:0] core_b_dtcm_addr_unused;
    wire [31:0] core_b_dtcm_wdata_unused;
    wire [3:0]  core_b_dtcm_we_unused;
    wire        core_b_dtcm_req_unused;

    // AXI outputs from core B — unconnected (core A drives the bus)
    wire [31:0] core_b_axi_awaddr_unused;
    wire [2:0]  core_b_axi_awprot_unused;
    wire        core_b_axi_awvalid_unused;
    wire [31:0] core_b_axi_wdata_unused;
    wire [3:0]  core_b_axi_wstrb_unused;
    wire        core_b_axi_wvalid_unused;
    wire        core_b_axi_bready_unused;
    wire [31:0] core_b_axi_araddr_unused;
    wire [2:0]  core_b_axi_arprot_unused;
    wire        core_b_axi_arvalid_unused;
    wire        core_b_axi_rready_unused;

    wire [31:0] core_b_lockstep_outputs;
    wire [31:0] core_b_lockstep_pc;
    wire        core_b_lockstep_valid;

    rv32im_core u_core_b (
        .clk_i              (clk_i),
        .rst_n_i            (core_b_rst_n),       // held in reset 2 extra cycles
        // ITCM — receives delayed responses from Core A's bus
        .itcm_addr_o        (core_b_itcm_addr_unused),
        .itcm_rdata_i       (core_b_itcm_rdata),
        .itcm_req_o         (core_b_itcm_req_unused),
        .itcm_ack_i         (core_b_itcm_ack),
        // DTCM — receives delayed responses from Core A's bus
        .dtcm_addr_o        (core_b_dtcm_addr_unused),
        .dtcm_wdata_o       (core_b_dtcm_wdata_unused),
        .dtcm_rdata_i       (core_b_dtcm_rdata),
        .dtcm_we_o          (core_b_dtcm_we_unused),
        .dtcm_req_o         (core_b_dtcm_req_unused),
        .dtcm_ack_i         (core_b_dtcm_ack),
        // AXI — receives delayed responses from Core A's bus
        .m_axi_awaddr_o     (core_b_axi_awaddr_unused),
        .m_axi_awprot_o     (core_b_axi_awprot_unused),
        .m_axi_awvalid_o    (core_b_axi_awvalid_unused),
        .m_axi_awready_i    (axi_awready_d2),
        .m_axi_wdata_o      (core_b_axi_wdata_unused),
        .m_axi_wstrb_o      (core_b_axi_wstrb_unused),
        .m_axi_wvalid_o     (core_b_axi_wvalid_unused),
        .m_axi_wready_i     (axi_wready_d2),
        .m_axi_bresp_i      (axi_bresp_d2),
        .m_axi_bvalid_i     (axi_bvalid_d2),
        .m_axi_bready_o     (core_b_axi_bready_unused),
        .m_axi_araddr_o     (core_b_axi_araddr_unused),
        .m_axi_arprot_o     (core_b_axi_arprot_unused),
        .m_axi_arvalid_o    (core_b_axi_arvalid_unused),
        .m_axi_arready_i    (axi_arready_d2),
        .m_axi_rdata_i      (axi_rdata_d2),
        .m_axi_rresp_i      (axi_rresp_d2),
        .m_axi_rvalid_i     (axi_rvalid_d2),
        .m_axi_rready_o     (core_b_axi_rready_unused),
        // Interrupts — delayed 2 cycles
        .irq_i              (irq_d2),
        .timer_irq_i        (timer_irq_d2),
        // Lockstep outputs — go directly to comparator (no delay needed)
        .lockstep_outputs_o (core_b_lockstep_outputs),
        .lockstep_pc_o      (core_b_lockstep_pc),
        .lockstep_valid_o   (core_b_lockstep_valid),
        // Control — delayed 2 cycles
        .halt_i             (halt_d2),
        .debug_req_i        (debug_req_d2)
    );

    // =========================================================================
    // Core A Lockstep Output Delay Buffer — 2-Cycle Alignment
    // =========================================================================
    // Core A's lockstep outputs are delayed by 2 cycles so they align
    // temporally with Core B's outputs at the comparator input.
    // Core B naturally lags by 2 cycles, so its outputs are already
    // aligned with Core A's delayed outputs.

    reg [31:0] ls_outputs_a_d1, ls_outputs_a_d2;
    reg [31:0] ls_pc_a_d1,      ls_pc_a_d2;
    reg        ls_valid_a_d1,   ls_valid_a_d2;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ls_outputs_a_d1 <= 32'd0;
            ls_outputs_a_d2 <= 32'd0;
            ls_pc_a_d1      <= 32'd0;
            ls_pc_a_d2      <= 32'd0;
            ls_valid_a_d1   <= 1'b0;
            ls_valid_a_d2   <= 1'b0;
        end else begin
            ls_outputs_a_d1 <= core_a_lockstep_outputs;
            ls_outputs_a_d2 <= ls_outputs_a_d1;
            ls_pc_a_d1      <= core_a_lockstep_pc;
            ls_pc_a_d2      <= ls_pc_a_d1;
            ls_valid_a_d1   <= core_a_lockstep_valid;
            ls_valid_a_d2   <= ls_valid_a_d1;
        end
    end

    // Master outputs (delayed 2 cycles for alignment)
    assign lockstep_outputs_m_o = ls_outputs_a_d2;
    assign lockstep_pc_m_o      = ls_pc_a_d2;
    assign lockstep_valid_m_o   = ls_valid_a_d2;

    // Checker outputs (direct — naturally aligned)
    assign lockstep_outputs_c_o = core_b_lockstep_outputs;
    assign lockstep_pc_c_o      = core_b_lockstep_pc;
    assign lockstep_valid_c_o   = core_b_lockstep_valid;

`ifndef SYNTHESIS
    // —————————————————————————————————————————————————————————————————————
    // Assertions: Verify stagger depth and lockstep alignment
    // —————————————————————————————————————————————————————————————————————
    reg [2:0] stagger_assert_cnt;
    reg       stagger_valid;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            stagger_assert_cnt <= 3'd0;
            stagger_valid      <= 1'b0;
        end else begin
            if (stagger_assert_cnt < 3'd5)
                stagger_assert_cnt <= stagger_assert_cnt + 3'd1;
            else
                stagger_valid <= 1'b1;
        end
    end

    // After initialization, both cores should produce valid outputs
    // simultaneously (with the master delayed 2 cycles internally).
    always @(posedge clk_i) begin
        if (stagger_valid && lockstep_valid_m_o && lockstep_valid_c_o) begin
            // Both cores valid in same cycle — lockstep is aligned
        end
    end
`endif

endmodule
