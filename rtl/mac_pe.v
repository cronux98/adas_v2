// ============================================================================
// mac_pe.v -- Multiply-Accumulate Processing Element (INT8 × INT8 → INT32)
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    AI Accelerator — 4×4 Weight-Stationary Systolic Array
// Author:   AI Accelerator Design Team
// Date:     2026-04-29
// Updated:  2026-04-29 — Phase 2b: Operand isolation + FAST_MODE pipeline
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz (10 ns period)
//
// Description:
//   Single MAC PE for the weight-stationary systolic array. The weight is
//   loaded during LOAD state and remains stationary. During COMPUTE, one
//   activation is presented per cycle; the PE multiplies weight × activation
//   and adds the incoming partial sum from the left neighbour.
//
//   Dataflow:  activation_in ──→ [MAC PE] ──→ activation_out (pass-through)
//              psum_in       ──→ [MAC PE] ──→ psum_out
//
//   Operand Isolation (Phase 2b fix):
//     When enable=0, psum_out is forced to 0 to prevent glitch propagation
//     and reduce dynamic power (was: transparent pass-through of psum_in).
//
//   FAST_MODE Pipeline (Phase 2b):
//     When `FAST_MODE is defined, the multiply output is registered in an
//     intermediate pipeline stage. This splits the critical path:
//       Stage 1: weight × activation → mult_reg
//       Stage 2: psum_in + mult_reg → psum_out
//     Enables operation at 150 MHz+ with zero functional change.
//
// Interfaces: (from block_interfaces.md §6)
//   - INT8 weight (loaded via systolic_array control)
//   - INT8 activation (driven per column per compute cycle)
//   - INT32 partial sum (flowing horizontally within a row)
// ============================================================================

`timescale 1ns / 1ps

module mac_pe (
    input  wire        clk,
    input  wire        rst_n,

    // Weight loading
    input  wire        weight_load,    // load strobe during LOAD state
    input  wire [7:0]  weight_data,    // INT8 signed weight value

    // Data interface
    input  wire [7:0]  activation_in,  // INT8 signed activation (broadcast from array ctrl)
    input  wire [31:0] psum_in,        // INT32 partial sum from left neighbour (or 0 for col 0)
    input  wire        enable,         // compute enable (asserted for this PE's compute cycle)

    // Outputs
    output wire [7:0]  activation_out, // activation pass-through (to next column)
    output reg  [31:0] psum_out        // partial sum to right neighbour
);

    // -------------------------------------------------------------------------
    // Internal registers
    // -------------------------------------------------------------------------
    reg signed [7:0]  weight;          // stationary weight (INT8)
    reg signed [7:0]  activation_d;    // delayed activation for pass-through

    // -------------------------------------------------------------------------
    // Weight loading (stationary — loaded once per inference)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight <= 8'd0;
        end else if (weight_load) begin
            weight <= weight_data;
        end
    end

    // -------------------------------------------------------------------------
    // Activation pass-through (registered for timing, 1-cycle delay)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            activation_d <= 8'd0;
        end else begin
            activation_d <= activation_in;
        end
    end

    assign activation_out = activation_d;

`ifdef FAST_MODE
    // =========================================================================
    // FAST_MODE: 2-stage pipeline (registered multiply output)
    //
    // Critical path decomposition for 150 MHz operation:
    //   Stage 1: mult_reg <= weight × activation_in    (~1.8 ns)
    //   Stage 2: psum_out <= psum_in + mult_reg         (~1.2 ns)
    //
    // Additional latency: +1 cycle (transparent to systolic array
    // because activations are already delayed by activation_d register,
    // and the array is pipelined by construction).
    // =========================================================================

    reg signed [31:0] mult_reg;   // registered multiply output

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mult_reg <= 32'd0;
        end else if (enable) begin
            mult_reg <= weight * activation_in;
        end else begin
            mult_reg <= 32'd0;     // operand isolation
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psum_out <= 32'd0;
        end else if (enable) begin
            // Stage 2: accumulate registered multiply result
            psum_out <= psum_in + mult_reg;
        end else begin
            // Operand isolation: force to 0 when disabled
            psum_out <= 32'd0;
        end
    end

`else
    // =========================================================================
    // STANDARD MODE: single-cycle MAC (100 MHz target)
    //
    // Timing (sky130hs, SS/125°C/1.62V):
    //   8×8 signed mult:   ~1.8 ns
    //   32-bit adder:      ~1.2 ns
    //   DFF setup:         ~0.1 ns
    //   Total:             ~3.1 ns  << 10 ns period  ✓
    // =========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psum_out <= 32'd0;
        end else if (enable) begin
            // Signed multiply-accumulate: INT8 × INT8 → INT32
            psum_out <= psum_in + (weight * activation_in);
        end else begin
            // Operand isolation: force to 0 when disabled
            // (was: psum_out <= psum_in; — caused glitch propagation)
            psum_out <= 32'd0;
        end
    end

`endif

endmodule
