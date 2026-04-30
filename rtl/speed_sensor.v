// ============================================================================
// speed_sensor.v — Wheel Speed Sensor (Pulse Counter + Timestamp)
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    Wheel tachometer pulse counter with 64-bit timestamp
// Author:   Mei-Lin Chang, Digital Design Engineer
// Date:     2026-04-29
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz
//
// Register Map (base 0x0000_4000):
//   0x00 SPEED_CTRL             RW   Control register
//   0x04 SPEED_STATUS           RO   Status register
//   0x08 SPEED_COUNT            RO   Pulse count (32-bit)
//   0x0C SPEED_TIMESTAMP_L      RO   Last pulse timestamp [31:0]
//   0x10 SPEED_TIMESTAMP_H      RO   Last pulse timestamp [63:32]
//   0x14 SPEED_PERIOD_L         RO   Period between pulses [31:0]
//   0x18 SPEED_PERIOD_H         RO   Period between pulses [63:32]
//   0x1C SPEED_STUCK_TIMEOUT    RW   Stuck sensor timeout
//   0x20 SPEED_CAPTURE_COUNT    RO   Captured count snapshot
//   0x24 SPEED_INTR_MASK        RW   Interrupt mask
//   0x28 SPEED_INTR_STATUS      RO   Interrupt status (W1C)
//   0x2C SPEED_COUNT_MAX        RW   Counter overflow threshold
// ============================================================================

`timescale 1ns / 1ps

module speed_sensor (
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

    // External async pulse input
    input  wire        pulse_i,

    // Interrupts / fault
    output wire        irq_pulse_o,
    output wire        irq_ovf_o,
    output wire        fault_o
);

    localparam AXI_OKAY   = 2'b00;
    localparam AXI_SLVERR = 2'b10;

    // ——— Registers ———
    reg [31:0] reg_ctrl;          // 0x00
    reg [31:0] reg_stuck_timeout; // 0x1C
    reg [31:0] reg_intr_mask;     // 0x24
    reg [31:0] reg_intr_status;   // 0x28
    reg [31:0] reg_count_max;     // 0x2C

    // ——— AXI write channel ———
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
            if (s_axi_awvalid_i && awready) begin awaddr_latch <= s_axi_awaddr_i; aw_done <= 1'b1; awready <= 1'b0; end
            if (s_axi_wvalid_i  && wready)  begin wdata_latch <= s_axi_wdata_i; wstrb_latch <= s_axi_wstrb_i; w_done <= 1'b1; wready <= 1'b0; end
            if (aw_done && w_done && !bvalid) begin bvalid <= 1'b1; bresp <= wr_valid ? AXI_OKAY : AXI_SLVERR; aw_done <= 1'b0; w_done <= 1'b0; end
            if (bvalid && s_axi_bready_i) bvalid <= 1'b0;
            if (!aw_done) awready <= 1'b1;
            if (!w_done)  wready  <= 1'b1;
        end
    end

    // ——— AXI read channel ———
    reg arready, rvalid;
    reg [31:0] araddr_latch, rdata;
    reg [1:0]  rresp;
    reg        ar_done;

    wire [5:0] rd_off = araddr_latch[7:2];
    wire [31:0] status_word = {16'd0, estimated_rate, 12'd0, count_ovf, sensor_stuck, pulse_detected};
    wire [31:0] rd_data;
    wire rd_valid;

    assign {rd_data, rd_valid} =
        (rd_off == 6'h00) ? {reg_ctrl,           1'b1} :
        (rd_off == 6'h01) ? {status_word,        1'b1} :
        (rd_off == 6'h02) ? {pulse_count,        1'b1} :
        (rd_off == 6'h03) ? {timestamp_last_l,   1'b1} :
        (rd_off == 6'h04) ? {timestamp_last_h,   1'b1} :
        (rd_off == 6'h05) ? {period_l,           1'b1} :
        (rd_off == 6'h06) ? {period_h,           1'b1} :
        (rd_off == 6'h07) ? {reg_stuck_timeout,  1'b1} :
        (rd_off == 6'h08) ? {capture_count,      1'b1} :
        (rd_off == 6'h09) ? {reg_intr_mask,      1'b1} :
        (rd_off == 6'h0A) ? {reg_intr_status,    1'b1} :
        (rd_off == 6'h0B) ? {reg_count_max,      1'b1} :
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
    wire wr_is_stuck   = (wr_off == 6'h07);
    wire wr_is_im      = (wr_off == 6'h09);
    wire wr_is_ist     = (wr_off == 6'h0A);
    wire wr_is_cmax    = (wr_off == 6'h0B);
    wire wr_valid = wr_is_ctrl | wr_is_stuck | wr_is_im | wr_is_ist | wr_is_cmax;
    wire wr_go = bvalid && s_axi_bready_i;

    // Register writes
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            reg_ctrl          <= 32'd0;
            reg_stuck_timeout <= 32'h0000FFFF;
            reg_intr_mask     <= 32'd0;
            reg_intr_status   <= 32'd0;
            reg_count_max     <= 32'hFFFFFFFF;
        end else begin
            if (wr_go && wr_is_ctrl) begin
                reg_ctrl[0]  <= wdata_latch[0];   // ENABLE
                reg_ctrl[3]  <= wdata_latch[3];   // STUCK_DET_EN
                reg_ctrl[4]  <= wdata_latch[4];   // STUCK_ACTION
                reg_ctrl[10] <= wdata_latch[10];  // CLK_EN
            end
            if (wr_go && wr_is_stuck) reg_stuck_timeout <= wdata_latch;
            if (wr_go && wr_is_im)    reg_intr_mask <= wdata_latch;
            if (wr_go && wr_is_ist)   reg_intr_status <= reg_intr_status & ~wdata_latch;  // W1C
            if (wr_go && wr_is_cmax)  reg_count_max <= wdata_latch;
            // Auto-clear PULSE_DETECTED on STATUS read
            if (rvalid && rd_off == 6'h01)
                reg_intr_status[0] <= 1'b0;
            // CLR_COUNT (bit 1) and CLR_TIMESTAMP (bit 2) self-clearing
            reg_ctrl[1] <= 1'b0;
            reg_ctrl[2] <= 1'b0;
            if (wr_go && wr_is_ctrl && wdata_latch[1]) reg_ctrl[1] <= 1'b1;
            if (wr_go && wr_is_ctrl && wdata_latch[2]) reg_ctrl[2] <= 1'b1;
        end
    end

    // ——— 2FF Synchronizer for external pulse ———
    (* ASYNC_REG = "TRUE" *) reg pulse_sync0, pulse_sync1;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pulse_sync0 <= 1'b0;
            pulse_sync1 <= 1'b0;
        end else begin
            pulse_sync0 <= pulse_i;
            pulse_sync1 <= pulse_sync0;
        end
    end

    // ——— Edge detector ———
    reg pulse_sync_d;
    wire pulse_rising;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            pulse_sync_d <= 1'b0;
        else
            pulse_sync_d <= pulse_sync1;
    end
    assign pulse_rising = pulse_sync1 && !pulse_sync_d;

    // ——— Pulse counter + timestamps ———
    reg [31:0] pulse_count;
    reg [63:0] free_running_ts;
    reg [63:0] timestamp_last;
    reg [63:0] timestamp_prev;
    reg [31:0] capture_count;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pulse_count   <= 32'd0;
            free_running_ts <= 64'd0;
            timestamp_last  <= 64'd0;
            timestamp_prev  <= 64'd0;
            capture_count   <= 32'd0;
        end else begin
            // Free-running timestamp counter
            free_running_ts <= free_running_ts + 64'd1;

            // Clear pulse count
            if (reg_ctrl[1]) pulse_count <= 32'd0;
            if (reg_ctrl[2]) begin timestamp_last <= 64'd0; timestamp_prev <= 64'd0; end

            if (reg_ctrl[0] && pulse_rising) begin
                timestamp_prev <= timestamp_last;
                timestamp_last <= free_running_ts;
                pulse_count    <= pulse_count + 32'd1;
                capture_count  <= pulse_count;  // snapshot for atomic read
                reg_intr_status[0] <= 1'b1;     // PULSE_DETECTED
            end
        end
    end

    wire [31:0] timestamp_last_l = timestamp_last[31:0];
    wire [31:0] timestamp_last_h = timestamp_last[63:32];
    wire [63:0] period_calc = timestamp_last - timestamp_prev;
    wire [31:0] period_l = period_calc[31:0];
    wire [31:0] period_h = period_calc[63:32];

    // ——— Stuck-at detection ———
    reg [31:0] stuck_counter;
    reg        sensor_stuck;
    reg        count_ovf;
    reg [15:0] estimated_rate;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            stuck_counter   <= 32'd0;
            sensor_stuck    <= 1'b0;
            count_ovf       <= 1'b0;
            estimated_rate  <= 16'd0;
        end else begin
            if (reg_ctrl[0] && reg_ctrl[3]) begin
                if (pulse_rising)
                    stuck_counter <= 32'd0;
                else if (stuck_counter < reg_stuck_timeout)
                    stuck_counter <= stuck_counter + 32'd1;
                sensor_stuck <= (stuck_counter >= reg_stuck_timeout);
            end else begin
                stuck_counter <= 32'd0;
                sensor_stuck  <= 1'b0;
            end

            // Count overflow
            if (pulse_count >= reg_count_max && reg_ctrl[0])
                count_ovf <= 1'b1;

            // Estimated pulse rate (simplified)
            if (pulse_rising && period_32 > 32'd0)
                estimated_rate <= 16'd0; // not computed in hardware; firmware calculates
        end
    end

    wire [31:0] period_32 = period_l;
    wire pulse_detected = reg_intr_status[0];

    assign irq_pulse_o = reg_intr_mask[0] && pulse_detected;
    assign irq_ovf_o   = reg_intr_mask[1] && count_ovf;
    assign fault_o     = reg_ctrl[4] && sensor_stuck;

    assign s_axi_awready_o = awready;
    assign s_axi_wready_o  = wready;
    assign s_axi_bresp_o   = bresp;
    assign s_axi_bvalid_o  = bvalid;
    assign s_axi_arready_o = arready;
    assign s_axi_rdata_o   = rdata;
    assign s_axi_rresp_o   = rresp;
    assign s_axi_rvalid_o  = rvalid;

endmodule
