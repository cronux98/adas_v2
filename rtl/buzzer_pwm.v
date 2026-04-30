// ============================================================================
// buzzer_pwm.v — Buzzer PWM for Audible Alert
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    Buzzer PWM with burst mode
// Author:   Mei-Lin Chang, Digital Design Engineer
// Date:     2026-04-29
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz
//
// Register Map (base 0x0000_5000):
//   0x00 BUZZER_CTRL           RW   Control register
//   0x04 BUZZER_PERIOD         RW   PWM period (cycles)
//   0x08 BUZZER_DUTY           RW   Duty cycle (cycles)
//   0x0C BUZZER_BURST_ON       RW   Burst ON cycles
//   0x10 BUZZER_BURST_OFF      RW   Burst OFF cycles
//   0x14 BUZZER_BURST_COUNT    RW   Burst repeat count (0=infinite)
//   0x18 BUZZER_STATUS         RO   Status register
//   0x1C BUZZER_INTR_MASK      RW   Interrupt mask
//   0x20 BUZZER_INTR_STATUS    RO   Interrupt status (W1C)
// ============================================================================

`timescale 1ns / 1ps

module buzzer_pwm (
    input  wire        clk_i,
    input  wire        rst_n_i,

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

    output wire        pwm_o,
    output wire        irq_done_o
);

    localparam AXI_OKAY = 2'b00, AXI_SLVERR = 2'b10;

    reg [31:0] reg_ctrl;        // 0x00
    reg [31:0] reg_period;      // 0x04
    reg [31:0] reg_duty;        // 0x08
    reg [31:0] reg_burst_on;    // 0x0C
    reg [31:0] reg_burst_off;   // 0x10
    reg [31:0] reg_burst_count; // 0x14
    reg [31:0] reg_intr_mask;   // 0x1C
    reg [31:0] reg_intr_status; // 0x20

    // AXI write
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

    // AXI read
    reg arready, rvalid, ar_done;
    reg [31:0] araddr_latch, rdata;
    reg [1:0]  rresp;

    wire [5:0] rd_off = araddr_latch[7:2];
    wire [31:0] status_word = {24'd0, 1'b0, 2'd0, burst_count_exhausted, burst_active, running, 1'b0, pwm_out};
    wire [31:0] rd_data;
    wire rd_valid;

    assign {rd_data, rd_valid} =
        (rd_off == 6'h00) ? {reg_ctrl,           1'b1} :
        (rd_off == 6'h01) ? {reg_period,         1'b1} :
        (rd_off == 6'h02) ? {reg_duty,           1'b1} :
        (rd_off == 6'h03) ? {reg_burst_on,       1'b1} :
        (rd_off == 6'h04) ? {reg_burst_off,      1'b1} :
        (rd_off == 6'h05) ? {reg_burst_count,    1'b1} :
        (rd_off == 6'h06) ? {status_word,        1'b1} :
        (rd_off == 6'h07) ? {reg_intr_mask,      1'b1} :
        (rd_off == 6'h08) ? {reg_intr_status,    1'b1} :
                             {32'd0,              1'b0};

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
    wire wr_is_ctrl    = (wr_off == 6'h00);
    wire wr_is_period  = (wr_off == 6'h01);
    wire wr_is_duty    = (wr_off == 6'h02);
    wire wr_is_bon     = (wr_off == 6'h03);
    wire wr_is_boff    = (wr_off == 6'h04);
    wire wr_is_bcnt    = (wr_off == 6'h05);
    wire wr_is_im      = (wr_off == 6'h07);
    wire wr_is_ist     = (wr_off == 6'h08);
    wire wr_valid = wr_is_ctrl | wr_is_period | wr_is_duty | wr_is_bon | wr_is_boff | wr_is_bcnt | wr_is_im | wr_is_ist;
    wire wr_go = bvalid && s_axi_bready_i;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            reg_ctrl        <= 32'd0;
            reg_period      <= 32'd100000;   // 1kHz default (100K cycles @ 100MHz)
            reg_duty        <= 32'd50000;    // 50% default
            reg_burst_on    <= 32'd0;
            reg_burst_off   <= 32'd0;
            reg_burst_count <= 32'd0;
            reg_intr_mask   <= 32'd0;
            reg_intr_status <= 32'd0;
        end else begin
            if (wr_go && wr_is_ctrl) begin
                reg_ctrl[0] <= wdata_latch[0];   // ENABLE
                reg_ctrl[1] <= wdata_latch[1];   // BURST_EN
                reg_ctrl[2] <= wdata_latch[2];   // INVERT
                reg_ctrl[10]<= wdata_latch[10];  // CLK_EN
            end
            if (wr_go && wr_is_period)  reg_period      <= wdata_latch;
            if (wr_go && wr_is_duty)    reg_duty        <= wdata_latch;
            if (wr_go && wr_is_bon)     reg_burst_on    <= wdata_latch;
            if (wr_go && wr_is_boff)    reg_burst_off   <= wdata_latch;
            if (wr_go && wr_is_bcnt)    reg_burst_count <= wdata_latch;
            if (wr_go && wr_is_im)      reg_intr_mask   <= wdata_latch;
            if (wr_go && wr_is_ist)     reg_intr_status <= reg_intr_status & ~wdata_latch;
        end
    end

    // ——— PWM core ———
    reg [31:0] counter;
    reg        pwm_out;
    reg        running;
    reg        period_done;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            counter     <= 32'd0;
            pwm_out     <= 1'b0;
            running     <= 1'b0;
            period_done <= 1'b0;
        end else if (reg_ctrl[0]) begin
            running <= 1'b1;
            period_done <= 1'b0;
            if (counter >= reg_period - 1) begin
                counter <= 32'd0;
                pwm_out <= 1'b1;
                period_done <= 1'b1;
            end else begin
                counter <= counter + 32'd1;
                if (counter >= reg_duty)
                    pwm_out <= 1'b0;
            end
        end else begin
            counter <= 32'd0;
            pwm_out <= 1'b0;
            running <= 1'b0;
            period_done <= 1'b0;
        end
    end

    // ——— Burst mode ———
    reg [31:0] burst_cycle_cnt;
    reg        burst_active;
    reg        burst_on_phase;   // 1=ON phase, 0=OFF phase
    reg [31:0] burst_repeat_cnt;
    reg        burst_count_exhausted;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            burst_cycle_cnt <= 32'd0;
            burst_active    <= 1'b0;
            burst_on_phase  <= 1'b1;
            burst_repeat_cnt <= 32'd0;
            burst_count_exhausted <= 1'b0;
        end else if (!reg_ctrl[0]) begin
            burst_cycle_cnt <= 32'd0;
            burst_active    <= 1'b0;
            burst_on_phase  <= 1'b1;
            burst_repeat_cnt <= 32'd0;
            burst_count_exhausted <= 1'b0;
        end else if (reg_ctrl[1]) begin  // BURST_EN
            if (period_done) begin
                burst_cycle_cnt <= burst_cycle_cnt + 32'd1;
                if (burst_on_phase && (burst_cycle_cnt >= reg_burst_on - 1)) begin
                    burst_on_phase <= 1'b0;
                    burst_cycle_cnt <= 32'd0;
                end else if (!burst_on_phase && (burst_cycle_cnt >= reg_burst_off - 1)) begin
                    burst_on_phase <= 1'b1;
                    burst_cycle_cnt <= 32'd0;
                    if (reg_burst_count > 0) begin
                        if (burst_repeat_cnt >= reg_burst_count - 1) begin
                            burst_count_exhausted <= 1'b1;
                            reg_intr_status[0] <= 1'b1;  // burst done
                        end else begin
                            burst_repeat_cnt <= burst_repeat_cnt + 32'd1;
                        end
                    end
                end
            end
            burst_active <= burst_on_phase;
        end else begin
            burst_active <= 1'b1;  // continuous mode
        end
    end

    wire gate_pwm = reg_ctrl[1] ? burst_active : 1'b1;
    assign pwm_o = reg_ctrl[2] ? ~(pwm_out && gate_pwm) : (pwm_out && gate_pwm);
    assign irq_done_o = reg_intr_mask[0] && reg_intr_status[0];

    assign s_axi_awready_o = awready;
    assign s_axi_wready_o  = wready;
    assign s_axi_bresp_o   = bresp;
    assign s_axi_bvalid_o  = bvalid;
    assign s_axi_arready_o = arready;
    assign s_axi_rdata_o   = rdata;
    assign s_axi_rresp_o   = rresp;
    assign s_axi_rvalid_o  = rvalid;

endmodule
