// ============================================================================
// ai_accel_4x4.v -- AI Accelerator 4×4 Top-Level Integration
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    AI Accelerator — 4×4 INT8 Weight-Stationary Systolic Array
// Author:   AI Accelerator Design Team
// Date:     2026-04-29
// Updated:  2026-04-29 — BUG-06: Renamed from ai_accelerator_top to ai_accel_4x4
//                       — BUG-01: Added weight readback wiring
//                       — BUG-02: Added bias readback wiring
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz (10 ns period)
//
// Description:
//   Top-level integration of all AI accelerator sub-blocks:
//     - axi4_lite_decode:  AXI4-Lite slave + register file
//     - control_fsm:       5-state FSM (IDLE→LOAD_WEIGHTS→LOAD_INPUT→COMPUTE→DONE)
//     - sram_buffer:       16-entry × 39-bit weight SRAM with SECDED ECC
//     - systolic_array:    4×4 MAC PE grid (weight-stationary)
//     - result_buffer:     4×32-bit result capture + bias addition
//
//   Dataflow:
//     1. CPU writes AI_WEIGHT_0..3 → axi4_lite_decode → sram_buffer
//     2. CPU writes AI_INPUT       → axi4_lite_decode (reg_ai_input)
//     3. CPU writes AI_CTRL.GO=1   → axi4_lite_decode → control_fsm.go
//     4. FSM: LOAD_WEIGHTS         → sram_buffer ← serially reads → systolic_array weights
//     5. FSM: COMPUTE              → systolic_array computes 4 cycles
//     6. FSM: DONE                 → result_buffer captures outputs
//     7. CPU reads AI_OUTPUT_0..3  → result_buffer → axi4_lite_decode → AXI read data
//     8. IRQ: irq_done_o asserted  → CPU interrupt (if enabled)
//
//   Register Map: see REGISTER_MAP.md §2 (base 0x0000_1000)
//   Block Interfaces: see block_interfaces.md §6
//
//   Module name: ai_accel_4x4 (matches block_interfaces.md §6.1)
// ============================================================================

`timescale 1ns / 1ps

module ai_accel_4x4 (
    // Clock and reset
    input  wire        clk_i,
    input  wire        rst_n_i,

    // =====================================================================
    // AXI4-Lite Slave Interface (ARM IHI 0022E)
    //   Connected to AXI4-Lite Crossbar slave port 0 (addr 0x0000_1000)
    // =====================================================================
    // Write address channel
    input  wire [31:0] s_axi_awaddr_i,
    input  wire        s_axi_awvalid_i,
    output wire        s_axi_awready_o,

    // Write data channel
    input  wire [31:0] s_axi_wdata_i,
    input  wire [3:0]  s_axi_wstrb_i,
    input  wire        s_axi_wvalid_i,
    output wire        s_axi_wready_o,

    // Write response channel
    output wire [1:0]  s_axi_bresp_o,
    output wire        s_axi_bvalid_o,
    input  wire        s_axi_bready_i,

    // Read address channel
    input  wire [31:0] s_axi_araddr_i,
    input  wire        s_axi_arvalid_i,
    output wire        s_axi_arready_o,

    // Read data channel
    output wire [31:0] s_axi_rdata_o,
    output wire [1:0]  s_axi_rresp_o,
    output wire        s_axi_rvalid_o,
    input  wire        s_axi_rready_i,

    // =====================================================================
    // Interrupt and fault outputs (to interrupt controller + safety monitor)
    // =====================================================================
    output wire        irq_done_o,         // computation complete interrupt
    output wire        irq_error_o,        // error interrupt
    output wire        fault_o             // hard fault (to safety monitor)
);

    // -------------------------------------------------------------------------
    // Internal interconnect signals
    // -------------------------------------------------------------------------

    // axi4_lite_decode → control_fsm
    wire        go;
    wire        clr_done;
    wire        clr_error;

    // control_fsm → ai_accel_4x4 (compute_cycle for cycle count tracking)
    wire [3:0]  cycle_count;
    assign cycle_count = {2'd0, compute_cycle};  // zero-extend 2→4 bits

    // control_fsm → axi4_lite_decode (status)
    wire        busy;
    wire        done;
    wire        cycle_count_valid;

    // axi4_lite_decode → sram_buffer (write port)
    wire        weight_wr_en;
    wire [3:0]  weight_wr_addr;
    wire [31:0] weight_wr_data;

    // BUG-01: axi4_lite_decode → sram_buffer (AXI combinational read port)
    wire [3:0]  weight_rd_addr;
    wire [31:0] weight_rd_data;

    // control_fsm → sram_buffer (read port, LOAD_WEIGHTS state)
    wire        sram_rd;
    wire [3:0]  sram_addr;
    wire [31:0] sram_rd_data;
    wire        ecc_err_detect;
    wire        ecc_err_correct;

    // sram_buffer → systolic_array (weight loading during LOAD_WEIGHTS)
    //   The control_fsm generates weight_row/col addressing for the array.
    //   The sram_rd_data is split into 4 INT8 weights and driven to the array.

    // control_fsm → systolic_array
    wire        weight_wr_fsm;
    wire [1:0]  weight_row_fsm;
    wire [1:0]  weight_col_fsm;
    wire [3:0]  col_enable;
    wire [1:0]  compute_cycle;

    // axi4_lite_decode → systolic_array (activations)
    wire [7:0]  input_act_0;
    wire [7:0]  input_act_1;
    wire [7:0]  input_act_2;
    wire [7:0]  input_act_3;
    wire        input_valid;

    // systolic_array → result_buffer
    wire [31:0] sa_result_0;
    wire [31:0] sa_result_1;
    wire [31:0] sa_result_2;
    wire [31:0] sa_result_3;

    // result_buffer → axi4_lite_decode
    wire [31:0] result_data;
    wire [1:0]  result_rd_addr;

    // axi4_lite_decode → result_buffer (bias)
    wire        bias_wr;
    wire        bias_sel;
    wire [31:0] bias_data;

    // BUG-02: result_buffer → axi4_lite_decode (bias readback)
    wire [31:0] bias_rd_data_0_1;
    wire [31:0] bias_rd_data_2_3;

    // axi4_lite_decode misc
    wire [31:0] ctrl_status;
    wire [3:0]  activation_fn;
    wire [31:0] scale_factor;
    wire        irq_done_en;
    wire        irq_error_en;

    // -------------------------------------------------------------------------
    // Weight loading logic: route SRAM read data to systolic array
    //   During LOAD_WEIGHTS, the control FSM sequentially addresses the SRAM
    //   and the 32-bit word is split into 4 INT8 weights routed to one row.
    //
    //   sram_buffer stores AI_WEIGHT_n as 32-bit words (one row per entry).
    //   For loading into the 4×4 array, we need to write each 8-bit weight
    //   to the correct PE. The FSM provides row/col addressing, and the
    //   appropriate byte from the 32-bit SRAM word is selected.
    // -------------------------------------------------------------------------
    wire [7:0] weight_byte;
    assign weight_byte = (weight_col_fsm == 2'd0) ? sram_rd_data[7:0]   :
                         (weight_col_fsm == 2'd1) ? sram_rd_data[15:8]  :
                         (weight_col_fsm == 2'd2) ? sram_rd_data[23:16] :
                                                    sram_rd_data[31:24];

    // -------------------------------------------------------------------------
    // Ready/valid signals for input loading
    //   inputs_loaded = 1 when AI_INPUT register has been written (BUG-04: flag-based)
    //   weights_loaded = 1 when FSM has cycled through all 16 weight addresses
    // -------------------------------------------------------------------------
    wire weights_loaded;
    reg  [3:0] weight_load_count;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            weight_load_count <= 4'd0;
        end else if (weight_wr_fsm) begin
            weight_load_count <= weight_load_count + 4'd1;
        end
    end

    assign weights_loaded = (weight_load_count == 4'd15) && (weight_row_fsm == 2'd3) &&
                            (weight_col_fsm == 2'd3);
    wire inputs_loaded = input_valid;

    // -------------------------------------------------------------------------
    // SRAM read address: during LOAD_WEIGHTS, route FSM row to SRAM address
    //   The SRAM stores one row of 4 weights per entry (AI_WEIGHT_n).
    //   FSM weight_row indexes the SRAM entry; weight_col selects the byte.
    //   We read the SRAM once per row and fan out to all 4 columns.
    // -------------------------------------------------------------------------
    reg [3:0] sram_row_latched;
    reg       sram_row_valid;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            sram_row_latched <= 4'd0;
            sram_row_valid   <= 1'b0;
        end else if (weight_wr_fsm && weight_col_fsm == 2'd0) begin
            // At start of each row, latch the SRAM address for this row
            sram_row_latched <= {2'd0, weight_row_fsm};
            sram_row_valid   <= 1'b1;
        end else begin
            sram_row_valid <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // BUG-01: Mux sram_buffer FSM read port to serve both FSM and AXI readback
    //   - FSM reads during LOAD_WEIGHTS: sram_rd or sram_row_valid active
    //   - AXI reads during weight register readback: weight_rd_addr driven by decode
    //   Since these never overlap (AXI reads happen in IDLE or DONE states),
    //   a simple priority mux suffices.
    // -------------------------------------------------------------------------
    wire [3:0]  sram_rd_addr_mux;
    wire        sram_rd_en_mux;

    // FSM takes priority; AXI weight readback is transparent passthrough otherwise
    assign sram_rd_en_mux   = (sram_rd || sram_row_valid) ? 1'b1 : 1'b1; // always enabled for combinational read
    assign sram_rd_addr_mux = (sram_rd || sram_row_valid) ?
                              (sram_row_valid ? sram_row_latched : sram_addr) :
                              weight_rd_addr;

    // -------------------------------------------------------------------------
    // Sub-block instantiations
    // -------------------------------------------------------------------------

    // --- AXI4-Lite Decode + Register File ---
    axi4_lite_decode u_axi_decode (
        .clk            (clk_i),
        .rst_n          (rst_n_i),

        // AXI4-Lite slave
        .s_axi_awaddr   (s_axi_awaddr_i),
        .s_axi_awvalid  (s_axi_awvalid_i),
        .s_axi_awready  (s_axi_awready_o),
        .s_axi_wdata    (s_axi_wdata_i),
        .s_axi_wstrb    (s_axi_wstrb_i),
        .s_axi_wvalid   (s_axi_wvalid_i),
        .s_axi_wready   (s_axi_wready_o),
        .s_axi_bresp    (s_axi_bresp_o),
        .s_axi_bvalid   (s_axi_bvalid_o),
        .s_axi_bready   (s_axi_bready_i),
        .s_axi_araddr   (s_axi_araddr_i),
        .s_axi_arvalid  (s_axi_arvalid_i),
        .s_axi_arready  (s_axi_arready_o),
        .s_axi_rdata    (s_axi_rdata_o),
        .s_axi_rresp    (s_axi_rresp_o),
        .s_axi_rvalid   (s_axi_rvalid_o),
        .s_axi_rready   (s_axi_rready_i),

        // Control
        .go             (go),
        .clr_done       (clr_done),
        .clr_error      (clr_error),
        .ctrl_status    (ctrl_status),

        // Status
        .busy           (busy),
        .done           (done),
        .cycle_count    (cycle_count),
        .cycle_count_valid (cycle_count_valid),

        // Weight buffer write
        .weight_wr_en   (weight_wr_en),
        .weight_wr_addr (weight_wr_addr),
        .weight_wr_data (weight_wr_data),

        // Weight readback (BUG-01)
        .weight_rd_addr (weight_rd_addr),
        .weight_rd_data (weight_rd_data),

        // Input activations
        .input_act_0    (input_act_0),
        .input_act_1    (input_act_1),
        .input_act_2    (input_act_2),
        .input_act_3    (input_act_3),
        .input_valid    (input_valid),

        // Result buffer
        .result_data    (result_data),
        .result_rd_addr (result_rd_addr),

        // Bias write
        .bias_wr        (bias_wr),
        .bias_sel       (bias_sel),
        .bias_data      (bias_data),

        // Bias readback (BUG-02)
        .bias_rd_data_0_1 (bias_rd_data_0_1),
        .bias_rd_data_2_3 (bias_rd_data_2_3),

        // Activation / scale
        .activation_fn  (activation_fn),
        .scale_factor   (scale_factor),

        // Interrupts
        .irq_done_en    (irq_done_en),
        .irq_error_en   (irq_error_en),
        .irq_done_o     (irq_done_o),
        .irq_error_o    (irq_error_o),
        .fault_o        (fault_o)
    );

    // --- Control FSM ---
    control_fsm u_control_fsm (
        .clk              (clk_i),
        .rst_n            (rst_n_i),
        .go               (go),
        .weights_loaded   (weights_loaded),
        .inputs_loaded    (inputs_loaded),
        .state            (/* unconnected */),
        .busy             (busy),
        .done             (done),
        .weight_wr        (weight_wr_fsm),
        .weight_row       (weight_row_fsm),
        .weight_col       (weight_col_fsm),
        .col_enable       (col_enable),
        .compute_cycle    (compute_cycle),
        .sram_rd          (sram_rd),
        .sram_addr        (sram_addr),
        .cycle_count_valid (cycle_count_valid)
    );

    // --- Weight SRAM Buffer ---
    sram_buffer u_sram (
        .clk              (clk_i),
        .rst_n            (rst_n_i),
        .wr_en            (weight_wr_en),
        .wr_addr          (weight_wr_addr),
        .wr_data          (weight_wr_data),
        .rd_en            (sram_rd_en_mux),
        .rd_addr          (sram_rd_addr_mux),
        .rd_data          (sram_rd_data),
        .axi_rd_addr      (weight_rd_addr),
        .axi_rd_data      (weight_rd_data),
        .ecc_err_detect   (ecc_err_detect),
        .ecc_err_correct  (ecc_err_correct),
        .ecc_last_addr_o  (),
        .ecc_correct_cnt_o(),
        .ecc_fatal_cnt_o  ()
    );

    // --- 4×4 Systolic Array ---
    systolic_array u_systolic_array (
        .clk              (clk_i),
        .rst_n            (rst_n_i),
        .weight_wr        (weight_wr_fsm),
        .weight_row       (weight_row_fsm),
        .weight_col       (weight_col_fsm),
        .weight_data      (weight_byte),
        .activation_0     (input_act_0),
        .activation_1     (input_act_1),
        .activation_2     (input_act_2),
        .activation_3     (input_act_3),
        .col_enable       (col_enable),
        .result_0         (sa_result_0),
        .result_1         (sa_result_1),
        .result_2         (sa_result_2),
        .result_3         (sa_result_3)
    );

    // --- Result Buffer ---
    result_buffer u_result_buf (
        .clk              (clk_i),
        .rst_n            (rst_n_i),
        .result_0         (sa_result_0),
        .result_1         (sa_result_1),
        .result_2         (sa_result_2),
        .result_3         (sa_result_3),
        .capture          (done),
        .rd_addr          (result_rd_addr),
        .rd_data          (result_data),
        .bias_wr          (bias_wr),
        .bias_sel         (bias_sel),
        .bias_data        (bias_data),
        .bias_rd_data_0_1 (bias_rd_data_0_1),
        .bias_rd_data_2_3 (bias_rd_data_2_3),
        .data_valid       (/* unused */)
    );

endmodule
