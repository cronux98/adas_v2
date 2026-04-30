// ============================================================================
// redundant_shutdown.v — Redundant Shutdown Controller (wdt_clk Domain)
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    Redundant shutdown controller with dual-output shutdown
// Author:   Mei-Lin Chang, Digital Design Engineer
// Date:     2026-04-29
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    wdt_clk @ 32.768 kHz (independent)
//
// Behavior (block_interfaces.md §15):
//   On aggregated fault or software shutdown request:
//     1. Assert alert_n_o within ~4 wdt_clk cycles
//     2. Assert shutdown_n_o[1:0] within 10 wdt_clk cycles (~0.3ms)
//     3. Outputs latched until external POR
//     4. Also drives force_shutdown_o → GPIO redundant path
//
// Inputs:
//   aggregated_fault_i   - from fault_aggregator (CDC'd from sys_clk)
//   force_shutdown_sw_i  - software shutdown from GPIO (CDC'd)
//
// Outputs:
//   shutdown_n_o[1:0]    - Redundant shutdown (active low, dual output)
//   alert_n_o             - Alert output (active low)
//   force_shutdown_o      - Shutdown override → GPIO (CDC'd back)
// ============================================================================

`timescale 1ns / 1ps

module redundant_shutdown (
    input  wire        clk_i,        // wdt_clk (32.768 kHz)
    input  wire        rst_n_i,      // wdt_rst_n

    // Fault inputs (CDC'd from sys_clk domain)
    input  wire        aggregated_fault_i,
    input  wire        force_shutdown_sw_i,

    // Shutdown outputs
    output reg  [1:0]  shutdown_n_o,
    output reg         alert_n_o,
    output reg         force_shutdown_o
);

    // ——— Shutdown state machine ———
    // States:
    //   IDLE     → no fault
    //   ALERT    → alert asserted, waiting before shutdown
    //   SHUTDOWN → shutdown asserted, latched forever
    localparam ST_IDLE     = 2'd0;
    localparam ST_ALERT    = 2'd1;
    localparam ST_SHUTDOWN = 2'd2;

    reg [1:0] state, next_state;

    // Alert delay counter (4 wdt_clk cycles between alert and shutdown)
    reg [2:0] alert_delay_cnt;
    // Shutdown delay counter (10 wdt_clk cycles max)
    reg [3:0] shutdown_delay_cnt;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            state <= ST_IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            ST_IDLE: begin
                if (aggregated_fault_i || force_shutdown_sw_i)
                    next_state = ST_ALERT;
            end
            ST_ALERT: begin
                if (alert_delay_cnt >= 3'd4)
                    next_state = ST_SHUTDOWN;
            end
            ST_SHUTDOWN: begin
                // Latch forever (until POR)
                next_state = ST_SHUTDOWN;
            end
            default: next_state = ST_IDLE;
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            alert_delay_cnt    <= 3'd0;
            shutdown_delay_cnt <= 4'd0;
            alert_n_o          <= 1'b1;   // inactive (high)
            shutdown_n_o       <= 2'b11;  // inactive (high)
            force_shutdown_o   <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    alert_delay_cnt    <= 3'd0;
                    shutdown_delay_cnt <= 4'd0;
                    alert_n_o          <= 1'b1;
                    shutdown_n_o       <= 2'b11;
                    force_shutdown_o   <= 1'b0;
                end
                ST_ALERT: begin
                    // Assert alert immediately
                    alert_n_o <= 1'b0;
                    // Wait 4 cycles then go to SHUTDOWN
                    if (alert_delay_cnt < 3'd4)
                        alert_delay_cnt <= alert_delay_cnt + 3'd1;
                end
                ST_SHUTDOWN: begin
                    // Assert shutdown within 10 wdt_clk cycles
                    if (shutdown_delay_cnt < 4'd10) begin
                        shutdown_delay_cnt <= shutdown_delay_cnt + 4'd1;
                    end else begin
                        shutdown_n_o <= 2'b00;  // active low
                    end
                    force_shutdown_o <= 1'b1;
                    // alert stays asserted
                    alert_n_o <= 1'b0;
                end
            endcase
        end
    end

endmodule
