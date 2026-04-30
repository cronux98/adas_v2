// ============================================================================
// gpio.v — GPIO Controller (32-bit bidirectional, interrupt-on-change)
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    32-bit GPIO with configurable interrupts on pins [7:0]
// Author:   Mei-Lin Chang, Digital Design Engineer
// Date:     2026-04-29
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz
//
// Register Map (base 0x0000_7000):
//   0x00 GPIO_DATA            RW   Data value
//   0x04 GPIO_DIR             RW   Direction: 0=input, 1=output
//   0x08 GPIO_OUT             RW   Output data set
//   0x0C GPIO_IN              RO   Input data read
//   0x10 GPIO_SET             WO   Bit-set register
//   0x14 GPIO_CLR             WO   Bit-clear register
//   0x18 GPIO_TOG             WO   Bit-toggle register
//   0x1C GPIO_INT_EN          RW   Interrupt enable per pin [7:0]
//   0x20 GPIO_INT_TYPE        RW   Interrupt type: 0=level, 1=edge
//   0x24 GPIO_INT_POLARITY    RW   Polarity: 0=falling/low, 1=rising/high
//   0x28 GPIO_INT_STATUS      RO   Interrupt status (W1C)
//   0x2C GPIO_INT_ACK         WO   Interrupt acknowledge (write 1 to clear)
//   0x30 GPIO_PULL_EN         RW   Pull-up/down enable
//   0x34 GPIO_PULL_SEL        RW   Pull select: 0=down, 1=up
//   0x38 GPIO_DRIVE           RW   Drive strength
//   0x3C GPIO_SAFETY          RW   Safety pin lock
//   0x40 GPIO_CTRL            RW   Control register
// ============================================================================

`timescale 1ns / 1ps

module gpio (
    input  wire        clk_i,
    input  wire        rst_n_i,

    // AXI4-Lite Slave
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

    // GPIO bidirectional bus
    inout  wire [31:0] gpio_io,

    // Interrupt outputs (pins [7:0] only)
    output wire [7:0]  irq_o,

    // Safety interface
    input  wire        force_shutdown_i,
    output wire        alert_o
);

    localparam AXI_OKAY = 2'b00, AXI_SLVERR = 2'b10;

    // ——— GPIO registers ———
    reg [31:0] gpio_out_reg;       // Output value register
    reg [31:0] gpio_dir;           // Direction: 0=input, 1=output
    reg [31:0] gpio_data;          // Data register (RW)
    reg [31:0] gpio_int_en;        // Interrupt enable
    reg [31:0] gpio_int_type;      // 0=level, 1=edge
    reg [31:0] gpio_int_pol;       // 0=falling/low, 1=rising/high
    reg [31:0] gpio_int_status;    // Interrupt status (W1C)
    reg [31:0] gpio_pull_en;       // Pull enable
    reg [31:0] gpio_pull_sel;      // Pull select
    reg [31:0] gpio_drive;         // Drive strength
    reg [31:0] gpio_safety;        // Safety lock
    reg [31:0] gpio_ctrl;          // Control

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
    wire [31:0] gpio_in_val;
    assign gpio_in_val = gpio_io;

    wire [31:0] rd_data;
    wire rd_valid;

    assign {rd_data, rd_valid} =
        (rd_off == 6'h00) ? {gpio_data,        1'b1} :
        (rd_off == 6'h01) ? {gpio_dir,         1'b1} :
        (rd_off == 6'h02) ? {gpio_out_reg,     1'b1} :
        (rd_off == 6'h03) ? {gpio_in_val,      1'b1} :
        (rd_off == 6'h07) ? {gpio_int_en,      1'b1} :
        (rd_off == 6'h08) ? {gpio_int_type,    1'b1} :
        (rd_off == 6'h09) ? {gpio_int_pol,     1'b1} :
        (rd_off == 6'h0A) ? {gpio_int_status,  1'b1} :
        (rd_off == 6'h0C) ? {gpio_pull_en,     1'b1} :
        (rd_off == 6'h0D) ? {gpio_pull_sel,    1'b1} :
        (rd_off == 6'h0E) ? {gpio_drive,       1'b1} :
        (rd_off == 6'h0F) ? {gpio_safety,      1'b1} :
        (rd_off == 6'h10) ? {gpio_ctrl,        1'b1} :
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

    wire [5:0] wr_off = awaddr_latch[7:2];
    wire wr_valid = (wr_off <= 6'h10);
    wire wr_go = bvalid && s_axi_bready_i;

    // Safety lock logic
    wire [31:0] safety_mask = {29'd0, gpio_safety[2:0]};  // pins 2:0 locked
    wire [31:0] safety_locked_mask = gpio_safety[3] ? {29'd0, 3'b111} : 32'd0;

    // Register writes with safety pin locking
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            gpio_out_reg     <= 32'd0;
            gpio_dir         <= 32'h0000FFFF;  // default: all inputs
            gpio_data        <= 32'd0;
            gpio_int_en      <= 32'd0;
            gpio_int_type    <= 32'd0;
            gpio_int_pol     <= 32'd0;
            gpio_int_status  <= 32'd0;
            gpio_pull_en     <= 32'd0;
            gpio_pull_sel    <= 32'd0;
            gpio_drive       <= 32'd0;
            gpio_safety      <= 32'd7;    // default: all safety pins locked
            gpio_ctrl        <= 32'd0;
        end else begin
            if (wr_go) begin
                case (wr_off)
                    6'h00: gpio_data <= wdata_latch;
                    6'h01: gpio_dir  <= (gpio_dir & safety_locked_mask) | (wdata_latch & ~safety_locked_mask);
                    6'h02: gpio_out_reg <= (gpio_out_reg & safety_locked_mask) | (wdata_latch & ~safety_locked_mask);
                    // GPIO_SET: write 1 to set bit
                    6'h04: gpio_out_reg <= gpio_out_reg | wdata_latch;
                    // GPIO_CLR: write 1 to clear bit
                    6'h05: gpio_out_reg <= gpio_out_reg & ~wdata_latch;
                    // GPIO_TOG: write 1 to toggle bit
                    6'h06: gpio_out_reg <= gpio_out_reg ^ wdata_latch;
                    6'h07: gpio_int_en <= wdata_latch;
                    6'h08: gpio_int_type <= wdata_latch;
                    6'h09: gpio_int_pol <= wdata_latch;
                    // GPIO_INT_STATUS: W1C
                    6'h0A: gpio_int_status <= gpio_int_status & ~wdata_latch;
                    // GPIO_INT_ACK: write 1 to clear (same as W1C on STATUS)
                    6'h0B: gpio_int_status <= gpio_int_status & ~wdata_latch;
                    6'h0C: gpio_pull_en  <= wdata_latch;
                    6'h0D: gpio_pull_sel <= wdata_latch;
                    6'h0E: gpio_drive    <= wdata_latch;
                    // GPIO_SAFETY: lock bits are one-time-write
                    6'h0F: begin
                        if (!gpio_safety[0]) gpio_safety[0] <= wdata_latch[0];
                        if (!gpio_safety[1]) gpio_safety[1] <= wdata_latch[1];
                        if (!gpio_safety[2]) gpio_safety[2] <= wdata_latch[2];
                        gpio_safety[3] <= gpio_safety[0] && gpio_safety[1] && gpio_safety[2];
                    end
                    6'h10: begin
                        gpio_ctrl[0]  <= wdata_latch[0];   // CLK_EN
                        gpio_ctrl[1]  <= wdata_latch[1];   // SOFT_RST
                    end
                    default: ;
                endcase
            end
            // Clear SOFT_RST auto
            if (gpio_ctrl[1]) gpio_ctrl[1] <= 1'b0;
        end
    end

    // ——— GPIO data path ———
    // Output enable per bit
    wire [31:0] gpio_oe = gpio_dir;  // 1=output driven, 0=input (tri-state)
    // Data to drive on outputs
    wire [31:0] gpio_out_d = gpio_out_reg;

    // Tri-state control: when dir[i]=1, drive output; otherwise high-Z (input)
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gpio_pin
            assign gpio_io[i] = gpio_oe[i] ? gpio_out_d[i] : 1'bz;
        end
    endgenerate

    // ——— Interrupt detection (pins [7:0]) ———
    reg [7:0] gpio_in_d1;
    wire [7:0] gpio_in_sync = gpio_io[7:0];

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            gpio_in_d1 <= 8'd0;
        else
            gpio_in_d1 <= gpio_in_sync;
    end

    // Edge detection
    wire [7:0] rising_edge  =  gpio_in_sync & ~gpio_in_d1;
    wire [7:0] falling_edge = ~gpio_in_sync &  gpio_in_d1;

    // Set interrupt status
    integer j;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            // handled in register write block
        end else begin
            for (j = 0; j < 8; j = j + 1) begin
                if (gpio_int_en[j]) begin
                    if (gpio_int_type[j]) begin
                        // Edge-triggered
                        if (gpio_int_pol[j])
                            gpio_int_status[j] <= gpio_int_status[j] | rising_edge[j];
                        else
                            gpio_int_status[j] <= gpio_int_status[j] | falling_edge[j];
                    end else begin
                        // Level-triggered
                        gpio_int_status[j] <= (gpio_in_sync[j] == gpio_int_pol[j]);
                    end
                end
            end
        end
    end

    // IRQ outputs
    assign irq_o = gpio_int_en[7:0] & gpio_int_status[7:0];

    // ——— Alert output (from GPIO[0]) ———
    assign alert_o = gpio_out_reg[0];

    // ——— AXI outputs ———
    assign s_axi_awready_o = awready;
    assign s_axi_wready_o  = wready;
    assign s_axi_bresp_o   = bresp;
    assign s_axi_bvalid_o  = bvalid;
    assign s_axi_arready_o = arready;
    assign s_axi_rdata_o   = rdata;
    assign s_axi_rresp_o   = rresp;
    assign s_axi_rvalid_o  = rvalid;

endmodule
