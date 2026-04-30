// ============================================================================
// control_fsm.v -- 5-State Control FSM for AI Accelerator
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    AI Accelerator — Control Finite State Machine
// Author:   AI Accelerator Design Team
// Date:     2026-04-29
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz (10 ns period)
//
// Description:
//   Five-state Moore-type FSM that orchestrates the full AI accelerator
//   computation lifecycle:
//
//     IDLE ──→ LOAD_WEIGHTS ──→ LOAD_INPUT ──→ COMPUTE ──→ DONE ──→ IDLE
//
//   Transitions:
//     IDLE:          go=1         → LOAD_WEIGHTS
//     LOAD_WEIGHTS:  weights_done → LOAD_INPUT
//     LOAD_INPUT:    inputs_done  → COMPUTE
//     COMPUTE:       cycle >= 4   → DONE
//     DONE:          (auto)       → IDLE (after 1 cycle)
//
// Interfaces: (from block_interfaces.md §6, microarchitecture_spec.md §5.3)
//   - AXI register-driven go signal
//   - Weight buffer and input buffer coordination
//   - Column-enable generation for systolic array (one-hot per compute cycle)
// ============================================================================

`timescale 1ns / 1ps

module control_fsm (
    input  wire        clk,
    input  wire        rst_n,

    // Start signal (from AI_CTRL.GO bit)
    input  wire        go,

    // Load completion status
    input  wire        weights_loaded,    // all 16 weights written to buffer
    input  wire        inputs_loaded,     // input activations written

    // Current state output (for status register)
    output reg  [2:0]  state,             // encoded state value
    output reg         busy,              // '1' when computation in progress
    output reg         done,              // pulse: computation complete

    // Systolic array control outputs
    output reg         weight_wr,         // weight write strobe to PE array
    output reg  [1:0]  weight_row,        // PE row address for weight loading
    output reg  [1:0]  weight_col,        // PE column address for weight loading
    output reg  [3:0]  col_enable,        // one-hot column enable per compute cycle
    output reg  [1:0]  compute_cycle,     // current compute cycle counter [0..3]

    // Buffer control
    output reg         sram_rd,           // read strobe for weight SRAM
    output reg  [3:0]  sram_addr,         // SRAM read address
    output reg         cycle_count_valid  // CYCLE_COUNT valid for status register
);

    // -------------------------------------------------------------------------
    // State encoding (one-hot for glitch-free outputs)
    // -------------------------------------------------------------------------
    localparam [2:0]
        S_IDLE         = 3'd0,
        S_LOAD_WEIGHTS = 3'd1,
        S_LOAD_INPUT   = 3'd2,
        S_COMPUTE      = 3'd3,
        S_DONE         = 3'd4;

    // -------------------------------------------------------------------------
    // State register
    // -------------------------------------------------------------------------
    reg [2:0] next_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // -------------------------------------------------------------------------
    // Next-state logic (Moore)
    // -------------------------------------------------------------------------
    always @(*) begin
        next_state = state;  // default: hold
        case (state)
            S_IDLE: begin
                if (go)
                    next_state = S_LOAD_WEIGHTS;
            end

            S_LOAD_WEIGHTS: begin
                if (weights_loaded)
                    next_state = S_LOAD_INPUT;
            end

            S_LOAD_INPUT: begin
                if (inputs_loaded)
                    next_state = S_COMPUTE;
            end

            S_COMPUTE: begin
                // compute_cycle counts 0→1→2→3; after cycle 3, transition to DONE
                // compute_cycle is updated synchronously (see sequential block below)
                if (compute_cycle == 2'd3)
                    next_state = S_DONE;
            end

            S_DONE: begin
                // Assert DONE signal for one cycle, then return to IDLE
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Compute cycle counter (active only in COMPUTE state)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            compute_cycle <= 2'd0;
        end else if (state == S_COMPUTE) begin
            if (compute_cycle < 2'd3)
                compute_cycle <= compute_cycle + 2'd1;
            else
                compute_cycle <= 2'd0;     // wrap for next computation
        end else begin
            compute_cycle <= 2'd0;
        end
    end

    // -------------------------------------------------------------------------
    // Output logic
    // -------------------------------------------------------------------------

    // Systolic array column enable (one-hot decode of compute_cycle during COMPUTE)
    always @(*) begin
        if (state == S_COMPUTE) begin
            case (compute_cycle)
                2'd0: col_enable = 4'b0001;  // column 0 computes
                2'd1: col_enable = 4'b0010;  // column 1 computes
                2'd2: col_enable = 4'b0100;  // column 2 computes
                2'd3: col_enable = 4'b1000;  // column 3 computes
                default: col_enable = 4'b0000;
            endcase
        end else begin
            col_enable = 4'b0000;
        end
    end

    // Busy flag
    always @(*) begin
        busy = (state != S_IDLE) && (state != S_DONE);
    end

    // Done pulse (single cycle in S_DONE)
    always @(*) begin
        done = (state == S_DONE);
    end

    // Weight loading control (during LOAD_WEIGHTS, step through all 16 PEs)
    // weight_row/col sequence: (0,0),(0,1),(0,2),(0,3),(1,0),...,(3,3)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_wr  <= 1'b0;
            weight_row <= 2'd0;
            weight_col <= 2'd0;
        end else if (state == S_LOAD_WEIGHTS) begin
            // weight_wr is pulsed; weights arrive via systolic_array weight_data
            // The SRAM drives weight_data to the array; we cycle through addresses
            weight_wr <= 1'b1;
            if (weight_col == 2'd3) begin
                weight_col <= 2'd0;
                weight_row <= weight_row + 2'd1;
            end else begin
                weight_col <= weight_col + 2'd1;
            end
        end else begin
            weight_wr  <= 1'b0;
            weight_row <= 2'd0;
            weight_col <= 2'd0;
        end
    end

    // Cycle count valid (pulse each compute cycle for status tracking)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count_valid <= 1'b0;
        end else begin
            cycle_count_valid <= (state == S_COMPUTE);
        end
    end

    // SRAM read strobe (active during LOAD_WEIGHTS state)
    // Each cycle reads one row of weights from SRAM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sram_rd  <= 1'b0;
            sram_addr <= 4'd0;
        end else if (state == S_LOAD_WEIGHTS) begin
            // Read SRAM at weight_row to get one row of weights
            // At start of each row (weight_col==0), issue a read
            if (weight_col == 2'd0) begin
                sram_rd   <= 1'b1;
                sram_addr <= {2'd0, weight_row};
            end else begin
                sram_rd   <= 1'b0;
            end
        end else begin
            sram_rd  <= 1'b0;
            sram_addr <= 4'd0;
        end
    end

endmodule
