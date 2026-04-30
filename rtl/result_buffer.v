// ============================================================================
// result_buffer.v -- Result Output Buffer
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    AI Accelerator — Result Buffer (4 × 32-bit INT32 outputs)
// Author:   AI Accelerator Design Team
// Date:     2026-04-29
// Updated:  2026-04-29 — BUG-02: Added bias readback ports for AI_BIAS_0_1/2_3
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz (10 ns period)
//
// Description:
//   Captures the 4 accumulated INT32 outputs from the systolic array at the
//   end of the COMPUTE state and holds them for AXI read access.
//
//   Capture occurs on the DONE state edge (after the final psum has propagated
//   through all PE pipeline stages).
//
//   Outputs are read via the AXI register interface as:
//     AI_OUTPUT_0 (0x24): output[0] (INT32)
//     AI_OUTPUT_1 (0x28): output[1] (INT32)
//     AI_OUTPUT_2 (0x2C): output[2] (INT32)
//     AI_OUTPUT_3 (0x30): output[3] (INT32)
//
//   Bias readback (BUG-02 fix):
//     AI_BIAS_0_1 (0x1C): bias_rd_data_0_1 output port
//     AI_BIAS_2_3 (0x20): bias_rd_data_2_3 output port
//     These expose the stored bias register values to axi4_lite_decode
//     for ASIL-D write-read-compare diagnostics.
//
// Interfaces: (from block_interfaces.md §6.3, REGISTER_MAP.md §2)
//   - Input:  4 × 32-bit from systolic_array result_0..3
//   - Capture: strobe from control_fsm on DONE transition
//   - Output:  AXI read mux drives result_data based on address offset
//   - Bias readback: combinational outputs of stored bias registers
// ============================================================================

`timescale 1ns / 1ps

module result_buffer (
    input  wire        clk,
    input  wire        rst_n,

    // Input from systolic array
    input  wire [31:0] result_0,           // row 0 accumulated output (INT32)
    input  wire [31:0] result_1,           // row 1 accumulated output (INT32)
    input  wire [31:0] result_2,           // row 2 accumulated output (INT32)
    input  wire [31:0] result_3,           // row 3 accumulated output (INT32)

    // Capture control
    input  wire        capture,            // strobe from control_fsm DONE state

    // Read interface (to AXI register decode)
    input  wire [1:0]  rd_addr,            // output select: 0→result_0, 1→result_1, ...
    output reg  [31:0] rd_data,            // requested output value

    // Bias registers (loaded from AXI)
    input  wire        bias_wr,            // bias write strobe
    input  wire        bias_sel,           // 0=bias_0_1, 1=bias_2_3
    input  wire [31:0] bias_data,          // bias write data (2×INT16 packed)

    // Bias readback ports (BUG-02 fix)
    // Expose stored bias values for register readback via AXI
    output wire [31:0] bias_rd_data_0_1,   // AI_BIAS_0_1 readback
    output wire [31:0] bias_rd_data_2_3,   // AI_BIAS_2_3 readback

    // Status
    output wire        data_valid          // '1' when capture has occurred at least once
);

    // -------------------------------------------------------------------------
    // Result storage registers
    // -------------------------------------------------------------------------
    reg [31:0] result_0_reg;
    reg [31:0] result_1_reg;
    reg [31:0] result_2_reg;
    reg [31:0] result_3_reg;

    // Capture on DONE state strobe
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_0_reg <= 32'd0;
            result_1_reg <= 32'd0;
            result_2_reg <= 32'd0;
            result_3_reg <= 32'd0;
        end else if (capture) begin
            result_0_reg <= result_0;
            result_1_reg <= result_1;
            result_2_reg <= result_2;
            result_3_reg <= result_3;
        end
    end

    // -------------------------------------------------------------------------
    // Bias storage registers
    //   bias_0_1:  bias0[15:0],  bias1[31:16]  (INT16 signed)
    //   bias_2_3:  bias2[15:0],  bias3[31:16]  (INT16 signed)
    //   Biases are added to the accumulated outputs before storage.
    // -------------------------------------------------------------------------
    reg [31:0] bias_0_1_reg;
    reg [31:0] bias_2_3_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bias_0_1_reg <= 32'd0;
            bias_2_3_reg <= 32'd0;
        end else if (bias_wr) begin
            if (bias_sel)
                bias_2_3_reg <= bias_data;
            else
                bias_0_1_reg <= bias_data;
        end
    end

    // BUG-02: Bias readback — combinational outputs for AXI register interface
    assign bias_rd_data_0_1 = bias_0_1_reg;
    assign bias_rd_data_2_3 = bias_2_3_reg;

    // -------------------------------------------------------------------------
    // Bias application
    //   Add accumulated INT16 bias to each INT32 result before storage.
    //   Bias values are sign-extended from INT16 to INT32.
    // -------------------------------------------------------------------------
    wire signed [31:0] bias_sxt [0:3];
    assign bias_sxt[0] = $signed({{16{bias_0_1_reg[15]}}, bias_0_1_reg[15:0]});
    assign bias_sxt[1] = $signed({{16{bias_0_1_reg[31]}}, bias_0_1_reg[31:16]});
    assign bias_sxt[2] = $signed({{16{bias_2_3_reg[15]}}, bias_2_3_reg[15:0]});
    assign bias_sxt[3] = $signed({{16{bias_2_3_reg[31]}}, bias_2_3_reg[31:16]});

    wire signed [31:0] result_with_bias [0:3];
    assign result_with_bias[0] = $signed(result_0_reg) + bias_sxt[0];
    assign result_with_bias[1] = $signed(result_1_reg) + bias_sxt[1];
    assign result_with_bias[2] = $signed(result_2_reg) + bias_sxt[2];
    assign result_with_bias[3] = $signed(result_3_reg) + bias_sxt[3];

    // -------------------------------------------------------------------------
    // Read mux (combinational)
    // -------------------------------------------------------------------------
    always @(*) begin
        case (rd_addr)
            2'd0: rd_data = result_with_bias[0];
            2'd1: rd_data = result_with_bias[1];
            2'd2: rd_data = result_with_bias[2];
            2'd3: rd_data = result_with_bias[3];
            default: rd_data = 32'd0;
        endcase
    end

    // -------------------------------------------------------------------------
    // Data valid flag (sticky after first capture, cleared on reset)
    // -------------------------------------------------------------------------
    reg data_valid_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_valid_reg <= 1'b0;
        end else if (capture) begin
            data_valid_reg <= 1'b1;
        end
    end

    assign data_valid = data_valid_reg;

endmodule
