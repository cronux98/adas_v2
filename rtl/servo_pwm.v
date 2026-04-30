// ============================================================================
// servo_pwm.v — Servo PWM Controller (Braking Actuator)
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    Servo PWM for braking actuator control
// Author:   Mei-Lin Chang, Digital Design Engineer
// Date:     2026-04-29
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz
//
// Register Map (base 0x0000_3000):
//   0x00 SERVO_CTRL          RW   Control register
//   0x04 SERVO_PERIOD        RW   PWM period (cycles)       default: 2,000,000 (20ms)
//   0x08 SERVO_DUTY          RW   Duty cycle (cycles)       default: 150,000 (1500µs)
//   0x0C SERVO_SAFE_DUTY     RW   Safe/neutral duty         default: 150,000
//   0x10 SERVO_STATUS        RO   Status register
//   0x14 SERVO_FAULT_LIMIT   RW   Fault debounce
//   0x18 SERVO_INTR_MASK     RW   Interrupt mask
//   0x1C SERVO_INTR_STATUS   RO   Interrupt status (W1C)
//   0x20 SERVO_DUTY_US       RW   Duty in µs
// ============================================================================

`timescale 1ns / 1ps

module servo_pwm (
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

    // PWM output + interrupts
    output wire        pwm_o,
    output wire        irq_fault_o,
    output wire        fault_o
);

    localparam AXI_OKAY   = 2'b00;
    localparam AXI_SLVERR = 2'b10;

    // ——— Registers ———
    reg [31:0] reg_ctrl;          // 0x00
    reg [31:0] reg_period;        // 0x04
    reg [31:0] reg_duty;          // 0x08
    reg [31:0] reg_safe_duty;     // 0x0C
    reg [31:0] reg_fault_limit;   // 0x14
    reg [31:0] reg_intr_mask;     // 0x18
    reg [31:0] reg_intr_status;   // 0x1C
    reg [31:0] reg_duty_us;       // 0x20

    // ——— AXI write state ———
    reg awready, wready;
    reg [31:0] awaddr_latch, wdata_latch;
    reg [3:0]  wstrb_latch;
    reg        aw_done, w_done;
    reg [1:0]  bresp;
    reg        bvalid;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            awready <= 1'b1; wready <= 1'b1;
            awaddr_latch <= 32'd0; wdata_latch <= 32'd0; wstrb_latch <= 4'd0;
            aw_done <= 1'b0; w_done <= 1'b0;
            bvalid <= 1'b0; bresp <= AXI_OKAY;
        end else begin
            // Latch addr
            if (s_axi_awvalid_i && awready) begin
                awaddr_latch <= s_axi_awaddr_i; aw_done <= 1'b1; awready <= 1'b0;
            end
            // Latch data
            if (s_axi_wvalid_i && wready) begin
                wdata_latch <= s_axi_wdata_i; wstrb_latch <= s_axi_wstrb_i; w_done <= 1'b1; wready <= 1'b0;
            end
            // Commit
            if (aw_done && w_done && !bvalid) begin
                bvalid <= 1'b1;
                bresp <= wr_valid ? AXI_OKAY : AXI_SLVERR;
                aw_done <= 1'b0; w_done <= 1'b0;
            end
            if (bvalid && s_axi_bready_i) bvalid <= 1'b0;
            if (!aw_done) awready <= 1'b1;
            if (!w_done)  wready <= 1'b1;
        end
    end

    // Read channel
    reg arready, rvalid;
    reg [31:0] araddr_latch, rdata;
    reg [1:0] rresp;
    reg ar_done;

    wire [5:0] rd_off = araddr_latch[7:2];
    wire rd_valid;
    wire [31:0] rd_data;
    wire [31:0] status_word = {26'd0, fault_latched, fault_det, at_safe, pwm_on};

    assign {rd_data, rd_valid} =
        (rd_off == 6'h00) ? {reg_ctrl,         1'b1} :
        (rd_off == 6'h01) ? {reg_period,       1'b1} :
        (rd_off == 6'h02) ? {reg_duty,         1'b1} :
        (rd_off == 6'h03) ? {reg_safe_duty,    1'b1} :
        (rd_off == 6'h04) ? {status_word,      1'b1} :
        (rd_off == 6'h05) ? {reg_fault_limit,  1'b1} :
        (rd_off == 6'h06) ? {reg_intr_mask,    1'b1} :
        (rd_off == 6'h07) ? {reg_intr_status,  1'b1} :
        (rd_off == 6'h08) ? {reg_duty_us,      1'b1} :
                             {32'd0,            1'b0};

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            arready <= 1'b1; ar_done <= 1'b0; araddr_latch <= 32'd0;
            rvalid <= 1'b0; rdata <= 32'd0; rresp <= AXI_OKAY;
        end else begin
            if (s_axi_arvalid_i && arready) begin
                araddr_latch <= s_axi_araddr_i; ar_done <= 1'b1; arready <= 1'b0;
            end
            if (ar_done && !rvalid) begin
                rvalid <= 1'b1; rdata <= rd_data; rresp <= rd_valid ? AXI_OKAY : AXI_SLVERR;
                ar_done <= 1'b0;
            end
            if (rvalid && s_axi_rready_i) rvalid <= 1'b0;
            if (!ar_done) arready <= 1'b1;
        end
    end

    // Write decode
    wire [5:0] wr_off = awaddr_latch[7:2];
    wire wr_is_ctrl        = (wr_off == 6'h00);
    wire wr_is_period      = (wr_off == 6'h01);
    wire wr_is_duty        = (wr_off == 6'h02);
    wire wr_is_safe        = (wr_off == 6'h03);
    wire wr_is_flim        = (wr_off == 6'h05);
    wire wr_is_im          = (wr_off == 6'h06);
    wire wr_is_ist         = (wr_off == 6'h07);
    wire wr_is_duty_us     = (wr_off == 6'h08);
    wire wr_valid = wr_is_ctrl | wr_is_period | wr_is_duty | wr_is_safe | wr_is_flim |
                    wr_is_im | wr_is_ist | wr_is_duty_us;
    wire wr_go = bvalid && s_axi_bready_i;

    // Register writes
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            reg_ctrl        <= 32'd0;
            reg_period      <= 32'd2000000;  // 20ms @ 100MHz
            reg_duty        <= 32'd150000;   // 1500µs (90° neutral)
            reg_safe_duty   <= 32'd150000;
            reg_fault_limit <= 32'd1000;
            reg_intr_mask   <= 32'd0;
            reg_intr_status <= 32'd0;
            reg_duty_us     <= 32'd1500;
        end else begin
            // W1C on fault
            if (wr_go && wr_is_ctrl) begin
                reg_ctrl[0]  <= wdata_latch[0];   // ENABLE
                reg_ctrl[1]  <= wdata_latch[1];   // SAFE_MODE
                reg_ctrl[2]  <= wdata_latch[2];   // US_MODE
                reg_ctrl[3]  <= wdata_latch[3];   // FAULT_EN
                reg_ctrl[4]  <= wdata_latch[4];   // FAULT_ACTION
                reg_ctrl[10] <= wdata_latch[10];  // CLK_EN
            end
            if (wr_go && wr_is_period)   reg_period <= wdata_latch;
            if (wr_go && wr_is_duty)     reg_duty   <= wdata_latch;
            if (wr_go && wr_is_safe)     reg_safe_duty <= wdata_latch;
            if (wr_go && wr_is_flim)     reg_fault_limit <= wdata_latch;
            if (wr_go && wr_is_im)       reg_intr_mask <= wdata_latch;
            if (wr_go && wr_is_ist)      reg_intr_status <= reg_intr_status & ~wdata_latch;
            if (wr_go && wr_is_duty_us)  reg_duty_us <= wdata_latch;
            // Auto-clear fault latched on status read
            if (rvalid && rd_off == 6'h04) begin
                reg_intr_status[2] <= 1'b0;
            end
        end
    end

    // ——— PWM core ———
    reg [31:0] counter;
    reg        pwm_on;
    wire [31:0] effective_duty = reg_ctrl[2] ? (reg_duty_us * 32'd100) : reg_duty;
    wire [31:0] safe_duty      = reg_ctrl[2] ? (reg_safe_duty & 32'd0) + 32'd150000 : reg_safe_duty;
    wire [31:0] active_duty    = reg_ctrl[1] ? safe_duty : effective_duty;
    wire [31:0] active_period  = (reg_period > 32'd0) ? reg_period : 32'd2000000;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            counter <= 32'd0;
            pwm_on  <= 1'b0;
        end else if (reg_ctrl[0]) begin
            if (counter >= active_period - 1) begin
                counter <= 32'd0;
                pwm_on  <= 1'b1;
            end else begin
                counter <= counter + 32'd1;
                if (counter >= active_duty)
                    pwm_on <= 1'b0;
            end
        end else begin
            counter <= 32'd0;
            pwm_on  <= 1'b0;
        end
    end

    assign pwm_o = pwm_on;

    // ——— Fault detection (readback compare, staged) ———
    reg        fault_det;
    reg        fault_latched;
    reg [31:0] fault_debounce;
    reg        pwm_on_d1;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            fault_det      <= 1'b0;
            fault_latched  <= 1'b0;
            fault_debounce <= 32'd0;
            pwm_on_d1      <= 1'b0;
        end else begin
            pwm_on_d1 <= pwm_on;
            if (reg_ctrl[3] && reg_ctrl[0]) begin
                // Readback compare: if pwm doesn't match expected
                if (pwm_on != pwm_on) begin  // placeholder for readback
                    if (fault_debounce >= reg_fault_limit) begin
                        fault_det <= 1'b1;
                    end else begin
                        fault_debounce <= fault_debounce + 32'd1;
                    end
                end else begin
                    fault_debounce <= 32'd0;
                end
            end else begin
                fault_det <= 1'b0;
                fault_debounce <= 32'd0;
            end
            // Latch fault
            if (fault_det) begin
                fault_latched <= 1'b1;
                reg_intr_status[0] <= 1'b1;
            end
        end
    end

    wire at_safe = reg_ctrl[1];

    assign irq_fault_o = reg_intr_mask[0] && fault_det;
    assign fault_o     = fault_latched;

    assign s_axi_awready_o = awready;
    assign s_axi_wready_o  = wready;
    assign s_axi_bresp_o   = bresp;
    assign s_axi_bvalid_o  = bvalid;
    assign s_axi_arready_o = arready;
    assign s_axi_rdata_o   = rdata;
    assign s_axi_rresp_o   = rresp;
    assign s_axi_rvalid_o  = rvalid;

endmodule
