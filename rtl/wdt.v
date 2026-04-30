// ============================================================================
// wdt.v — Window Watchdog Timer (Independent wdt_clk Domain)
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    Window Watchdog Timer with CDC'd AXI4-Lite interface
// Author:   Mei-Lin Chang, Digital Design Engineer
// Date:     2026-04-29
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    wdt_clk @ 32.768 kHz (independent)
//
// WARNING: This block runs on the independent watchdog clock domain.
// All AXI inputs from sys_clk domain are synchronized using 2FF
// synchronizers internally. See cdc_plan.md CDC-01 for details.
//
// Register Map (base 0x0000_F100):
//   0x00 WDT_CTRL           RW       Control register (key-protected)
//   0x04 WDT_TIMEOUT        RW       Timeout in wdt_clk ticks
//   0x08 WDT_WINDOW         RW       Open window start threshold
//   0x0C WDT_COUNT          RO       Current counter value
//   0x10 WDT_KICK           WO       Refresh (write 0xAC53_CAFE)
//   0x14 WDT_STATUS         RO       Status register
//   0x18 WDT_PREWARN        RW       Pre-warning threshold
//   0x1C WDT_INTR_MASK      RW       Interrupt mask
//   0x20 WDT_INTR_STATUS    RO       Interrupt status
//   0x24 WDT_LOCK           RW       Configuration lock
//   0x28 WDT_ID             RO       Module ID ("WDT\0")
// ============================================================================

`timescale 1ns / 1ps

module wdt (
    input  wire        clk_i,        // wdt_clk (32.768 kHz)
    input  wire        rst_n_i,      // wdt_rst_n

    // AXI4-Lite Slave (all inputs CDC'd from sys_clk)
    // Note: These signals have already passed through 2FF synchronizers
    // in the CDC wrapper. They arrive clean to this module.
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

    // Fault / pre-warning outputs
    output wire        fault_o,        // WDT timeout → fault aggregator
    output wire        prewarn_o       // 75% pre-warning → IRQ controller
);

    localparam AXI_OKAY = 2'b00, AXI_SLVERR = 2'b10;
    localparam KICK_MAGIC = 32'hAC53_CAFE;
    localparam WDT_ID_VAL  = 32'h5744_5400;  // "WDT\0"

    // ——— Registers ———
    reg [31:0] reg_ctrl;        // 0x00
    reg [31:0] reg_timeout;     // 0x04
    reg [31:0] reg_window;      // 0x08
    reg [31:0] reg_prewarn;     // 0x18
    reg [31:0] reg_intr_mask;   // 0x1C
    reg [31:0] reg_intr_status; // 0x20
    reg [31:0] reg_lock;        // 0x24
    reg [31:0] reg_status;      // 0x14 (computed)

    // ——— Counter ———
    reg [31:0] wdt_count;

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

    assign {rd_data, rd_valid} =
        (rd_off == 6'h00) ? {reg_ctrl,         1'b1} :
        (rd_off == 6'h01) ? {reg_timeout,      1'b1} :
        (rd_off == 6'h02) ? {reg_window,       1'b1} :
        (rd_off == 6'h03) ? {wdt_count,        1'b1} :
        // 0x10 WDT_KICK is WO, read returns 0
        (rd_off == 6'h04) ? {32'd0,            1'b0} :
        (rd_off == 6'h05) ? {reg_status,       1'b1} :
        (rd_off == 6'h06) ? {reg_prewarn,      1'b1} :
        (rd_off == 6'h07) ? {reg_intr_mask,    1'b1} :
        (rd_off == 6'h08) ? {reg_intr_status,  1'b1} :
        (rd_off == 6'h09) ? {reg_lock,         1'b1} :
        (rd_off == 6'h0A) ? {WDT_ID_VAL,       1'b1} :
                             {32'd0,            1'b0};

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

    // Write decode
    wire [5:0] wr_off = awaddr_latch[7:2];
    wire wr_is_ctrl    = (wr_off == 6'h00);
    wire wr_is_timeout = (wr_off == 6'h01);
    wire wr_is_window  = (wr_off == 6'h02);
    wire wr_is_kick    = (wr_off == 6'h04);
    wire wr_is_prewarn = (wr_off == 6'h06);
    wire wr_is_im      = (wr_off == 6'h07);
    wire wr_is_ist     = (wr_off == 6'h08);
    wire wr_is_lock    = (wr_off == 6'h09);
    wire wr_valid = wr_is_ctrl | wr_is_timeout | wr_is_window | wr_is_kick |
                    wr_is_prewarn | wr_is_im | wr_is_ist | wr_is_lock;
    wire wr_go = bvalid && s_axi_bready_i;

    // Key-check for CTRL write
    wire ctrl_key_valid = (wdata_latch[15:8] == 8'h5A);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            reg_ctrl        <= 32'd0;
            reg_timeout     <= 32'd3277;   // ~100ms @ 32.768kHz
            reg_window      <= 32'd2458;   // 75% of 3277
            reg_prewarn     <= 32'd2560;   // ~78% of timeout
            reg_intr_mask   <= 32'd0;
            reg_intr_status <= 32'd0;
            reg_lock        <= 32'd0;
        end else begin
            // Lock-check function
            if (wr_go) begin
                // WDT_CTRL: key-protected; lock-protected if LOCK_CTRL set
                if (wr_is_ctrl && ctrl_key_valid && !reg_lock[0]) begin
                    reg_ctrl[0] <= wdata_latch[0];   // ENABLE (once set, cannot clear)
                    reg_ctrl[1] <= wdata_latch[1];   // WINDOW_EN
                    reg_ctrl[2] <= wdata_latch[2];   // PREWARN_EN
                    reg_ctrl[3] <= wdata_latch[3];   // RESET_EN
                end
                // WDT_TIMEOUT: lock-protected if LOCK_TIMEOUT set
                if (wr_is_timeout && !reg_lock[1])
                    reg_timeout <= wdata_latch;
                // WDT_WINDOW: lock-protected if LOCK_WINDOW set
                if (wr_is_window && !reg_lock[2])
                    reg_window <= wdata_latch;
                // WDT_KICK
                if (wr_is_kick && wdata_latch == KICK_MAGIC) begin
                    // Check if we're in the open window
                    if (!reg_ctrl[1] || (wdt_count >= reg_window)) begin
                        // Valid refresh
                        wdt_count <= 32'd0;
                        reg_status[3] <= 1'b0;  // clear TIMED_OUT
                        reg_status[4] <= 1'b0;  // clear EARLY_KICK
                    end else begin
                        // Early kick (closed window) → fault
                        reg_status[4] <= 1'b1;  // EARLY_KICK
                    end
                end
                if (wr_is_prewarn && !reg_lock[2])
                    reg_prewarn <= wdata_latch;
                if (wr_is_im)
                    reg_intr_mask <= wdata_latch;
                if (wr_is_ist)
                    reg_intr_status <= reg_intr_status & ~wdata_latch;
                // WDT_LOCK: one-time write
                if (wr_is_lock) begin
                    if (!reg_lock[0] && wdata_latch[0]) reg_lock[0] <= 1'b1;
                    if (!reg_lock[1] && wdata_latch[1]) reg_lock[1] <= 1'b1;
                    if (!reg_lock[2] && wdata_latch[2]) reg_lock[2] <= 1'b1;
                    reg_lock[3] <= reg_lock[0] && reg_lock[1] && reg_lock[2];
                end
            end

            // WDT can never be disabled once enabled (sticky)
            reg_ctrl[0] <= reg_ctrl[0] || (wr_go && wr_is_ctrl && ctrl_key_valid && wdata_latch[0]);
        end
    end

    // ——— Watchdog counter ———
    reg        timed_out;
    reg        prewarned;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            wdt_count  <= 32'd0;
            timed_out  <= 1'b0;
            prewarned  <= 1'b0;
        end else if (reg_ctrl[0]) begin
            // Counter increments
            if (wdt_count >= reg_timeout) begin
                timed_out <= 1'b1;
                // Counter stops at timeout
            end else begin
                wdt_count <= wdt_count + 32'd1;
                timed_out <= 1'b0;
            end

            // Pre-warning check
            prewarned <= (wdt_count >= reg_prewarn) && reg_ctrl[2];

            // Update status
            reg_status[0] <= 1'b1;  // RUNNING
            reg_status[1] <= (reg_ctrl[1]) ? (wdt_count >= reg_window) : 1'b1;  // IN_WINDOW
            reg_status[2] <= prewarned;
        end else begin
            reg_status[0] <= 1'b0;
        end
    end

    // Latch timeout in status
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            reg_status[3] <= 1'b0;
        else if (timed_out)
            reg_status[3] <= 1'b1;
    end

    // ——— Outputs ———
    assign fault_o   = reg_status[3] || reg_status[4];  // TIMED_OUT or EARLY_KICK
    assign prewarn_o = prewarned && reg_ctrl[2];

    assign s_axi_awready_o = awready;
    assign s_axi_wready_o  = wready;
    assign s_axi_bresp_o   = bresp;
    assign s_axi_bvalid_o  = bvalid;
    assign s_axi_arready_o = arready;
    assign s_axi_rdata_o   = rdata;
    assign s_axi_rresp_o   = rresp;
    assign s_axi_rvalid_o  = rvalid;

endmodule
