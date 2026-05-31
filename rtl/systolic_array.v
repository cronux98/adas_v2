// ============================================================================
// systolic_array.v -- 4×4 Weight-Stationary Systolic Array
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    AI Accelerator — 4×4 INT8 Systolic Array
// Author:   AI Accelerator Design Team
// Date:     2026-04-29
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz (10 ns period)
//
// Description:
//   4×4 grid of mac_pe instances configured for weight-stationary dataflow.
//
//   Dataflow (weight-stationary, column-activation with psum chaining):
//
//        a[0]        a[1]        a[2]        a[3]
//         │           │           │           │
//    ┌────┴────┐ ┌────┴────┐ ┌────┴────┐ ┌────┴────┐
//    │ PE[0][0]│→│ PE[0][1]│→│ PE[0][2]│→│ PE[0][3]│→ sum[0]
//    │  w00    │ │  w01    │ │  w02    │ │  w03    │
//    └─────────┘ └─────────┘ └─────────┘ └─────────┘
//    ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
//    │ PE[1][0]│→│ PE[1][1]│→│ PE[1][2]│→│ PE[1][3]│→ sum[1]
//    │  w10    │ │  w11    │ │  w12    │ │  w13    │
//    └─────────┘ └─────────┘ └─────────┘ └─────────┘
//    ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
//    │ PE[2][0]│→│ PE[2][1]│→│ PE[2][2]│→│ PE[2][3]│→ sum[2]
//    │  w20    │ │  w21    │ │  w22    │ │  w23    │
//    └─────────┘ └─────────┘ └─────────┘ └─────────┘
//    ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
//    │ PE[3][0]│→│ PE[3][1]│→│ PE[3][2]│→│ PE[3][3]│→ sum[3]
//    │  w30    │ │  w31    │ │  w32    │ │  w33    │
//    └─────────┘ └─────────┘ └─────────┘ └─────────┘
//
//   Operation sequence:
//     LOAD:  Weights loaded into all 16 PEs (w[i][j] into PE[i][j])
//     COMPUTE cycle 0: a[0] broadcast to column 0; PE[*][0] enabled
//     COMPUTE cycle 1: a[1] broadcast to column 1; PE[*][1] enabled
//     COMPUTE cycle 2: a[2] broadcast to column 2; PE[*][2] enabled
//     COMPUTE cycle 3: a[3] broadcast to column 3; PE[*][3] enabled
//     DONE:   sum[*] valid (captured on cycle 4 edge)
//
//   Latency: 4 compute cycles + 1 pipeline fill = 5 cycles after COMPUTE start
//            (results available on cycle 4 rising edge)
//
// Interfaces: (from block_interfaces.md §6)
//   - Weight loading: 16×INT8 via row/column addressing
//   - Activation input: 4×INT8 broadcast per compute cycle
//   - Psum output: 4×INT32 outputs after computation
// ============================================================================

`timescale 1ns / 1ps

module systolic_array (
    input  wire        clk,
    input  wire        rst_n,

    // Weight loading (driven during LOAD state)
    input  wire        weight_wr,          // weight write strobe
    input  wire [1:0]  weight_row,         // PE row select [0..3]
    input  wire [1:0]  weight_col,         // PE column select [0..3]
    input  wire signed [7:0]  weight_data,        // INT8 weight value

    // Activation broadcast (driven during COMPUTE state)
    input  wire signed [7:0]  activation_0,       // activation for column 0
    input  wire signed [7:0]  activation_1,       // activation for column 1
    input  wire signed [7:0]  activation_2,       // activation for column 2
    input  wire signed [7:0]  activation_3,       // activation for column 3

    // Column compute enables (one-hot per compute cycle)
    input  wire [3:0]  col_enable,         // which column(s) compute this cycle

    // Outputs
    output wire signed [31:0] result_0,           // output for row 0 (INT32)
    output wire signed [31:0] result_1,           // output for row 1 (INT32)
    output wire signed [31:0] result_2,           // output for row 2 (INT32)
    output wire signed [31:0] result_3            // output for row 3 (INT32)
);

    // -------------------------------------------------------------------------
    // Wire declarations for the 4×4 PE interconnect grid
    // -------------------------------------------------------------------------
    // Horizontal: psum[i][j+1] = PE[i][j].psum_out     (0 ≤ i < 4, 0 ≤ j < 3)
    //              psum[i][0]   = 0                     (row boundary)
    // Activation:  col_act[j] selects which activation drives column j
    //              Each PE in column j receives col_act[j]
    // Weight load: decoded from weight_row, weight_col

    wire signed [31:0] psum_node [0:3][0:4];  // psum[i][0]=0, psum[i][4]=result[i]
    wire signed [7:0]  wt_load_node [0:3][0:3];  // weight load data per PE
    wire        wt_load_en [0:3][0:3];     // weight load enable per PE

    // -------------------------------------------------------------------------
    // Row boundary: psum_in for column 0 is always 0
    // -------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_row_boundary
            assign psum_node[i][0] = 32'd0;
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Activation selection per column
    //   When col_enable[j]=1, column j PEs see the activation for that column.
    //   Otherwise, the PE does not compute (enable=0 → transparent).
    //   However: each column needs its activation value present when enabled.
    //   We route activation_0..3 to columns 0..3 respectively.
    // -------------------------------------------------------------------------
    wire signed [7:0] col_act [0:3];
    assign col_act[0] = activation_0;
    assign col_act[1] = activation_1;
    assign col_act[2] = activation_2;
    assign col_act[3] = activation_3;

    // -------------------------------------------------------------------------
    // Weight load decoding: one-hot per PE based on row/col
    // -------------------------------------------------------------------------
    genvar j;
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_row
            for (j = 0; j < 4; j = j + 1) begin : gen_col
                // Weight load enable: asserted when this PE is addressed
                assign wt_load_en[i][j]  = weight_wr &&
                                          (weight_row == i[1:0]) &&
                                          (weight_col == j[1:0]);
                assign wt_load_node[i][j] = weight_data;
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Instantiate 4×4 MAC PE grid
    // -------------------------------------------------------------------------
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_pe_row
            for (j = 0; j < 4; j = j + 1) begin : gen_pe_col
                mac_pe u_mac_pe (
                    .clk            (clk),
                    .rst_n          (rst_n),
                    .weight_load    (wt_load_en[i][j]),
                    .weight_data    (wt_load_node[i][j]),
                    .activation_in  (col_act[j]),
                    .psum_in        (psum_node[i][j]),
                    .enable         (col_enable[j]),
                    .activation_out (),  // not connected (no activation flow needed)
                    .psum_out       (psum_node[i][j+1])
                );
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Result outputs: psum at the right boundary of each row
    //   result[i] = psum_node[i][4] after 4 compute cycles + 1 pipeline fill
    // -------------------------------------------------------------------------
    assign result_0 = psum_node[0][4];
    assign result_1 = psum_node[1][4];
    assign result_2 = psum_node[2][4];
    assign result_3 = psum_node[3][4];

endmodule
