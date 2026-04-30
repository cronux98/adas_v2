// ============================================================================
// axi4_lite_decode.v -- AXI4-Lite Slave Decode + Register File
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    AI Accelerator — AXI4-Lite Slave Interface
// Author:   AI Accelerator Design Team
// Date:     2026-04-29
// Updated:  2026-04-29 — BUG-01,02,03,04 fixes
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz (10 ns period)
//
// Description:
//   Implements a 32-bit AXI4-Lite slave interface (ARM IHI 0022E compliant)
//   with the ADAS v2 AI accelerator register map. All register accesses are
//   registered (read data available 1 cycle after ARVALID/ARREADY handshake).
//
//   Register Map (per REGISTER_MAP.md §2):
//     Offset  Name             Access  Description
//     0x00    AI_CTRL          RW      Control (GO, DONE, ERROR, RELU_EN, etc.)
//     0x04    AI_STATUS        RO      Status (CYCLE_COUNT, ERROR_CODE)
//     0x08-   AI_WEIGHT_0..3   RW      4×INT8 packed weights per row
//     0x14
//     0x18    AI_INPUT         RW      Input activations a0..a3 (INT8 packed)
//     0x1C    AI_BIAS_0_1      RW      Biases 0,1 (INT16 each)
//     0x20    AI_BIAS_2_3      RW      Biases 2,3 (INT16 each)
//     0x24-   AI_OUTPUT_0..3   RO      Accumulated outputs (INT32)
//     0x30
//     0x34    AI_ACTIVATION    RW      Activation function control
//     0x38    AI_SCALE         RW      Output scaling factor (Q8.8)
//     0x3C    AI_INTR_MASK     RW      Interrupt mask (DONE_IE, ERROR_IE)
//
//   AXI4-Lite Compliance:
//     - Single-cycle read/write transactions (no burst support)
//     - bresp/rresp: OKAY(00) or SLVERR(10) for invalid addresses
//     - wstrb support: 4-bit byte-enable
//
//   Changelog — BUG FIXES 2026-04-29:
//     BUG-01: Weight readback via sram_buffer axi_rd port (was SLVERR)
//     BUG-02: Bias readback via result_buffer bias_rd_data ports (was 0x0)
//     BUG-03: CLK_EN bit 8 is now fully read-write (was write-only-1)
//     BUG-04: input_valid driven by input_written_flag (was |reg_ai_input)
// ============================================================================

`timescale 1ns / 1ps

module axi4_lite_decode (
    input  wire        clk,
    input  wire        rst_n,

    // =====================================================================
    // AXI4-Lite Write Address Channel
    // =====================================================================
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,

    // =====================================================================
    // AXI4-Lite Write Data Channel
    // =====================================================================
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,

    // =====================================================================
    // AXI4-Lite Write Response Channel
    // =====================================================================
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,

    // =====================================================================
    // AXI4-Lite Read Address Channel
    // =====================================================================
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,

    // =====================================================================
    // AXI4-Lite Read Data Channel
    // =====================================================================
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    // =====================================================================
    // Control outputs → control_fsm
    // =====================================================================
    output reg         go,                // start computation (pulse)
    output reg         clr_done,          // clear DONE flag
    output reg         clr_error,         // clear ERROR flag
    output wire [31:0] ctrl_status,       // combined control/status word

    // =====================================================================
    // Status inputs ← control_fsm
    // =====================================================================
    input  wire        busy,
    input  wire        done,
    input  wire [3:0]  cycle_count,       // from FSM cycle counter
    input  wire        cycle_count_valid,

    // =====================================================================
    // Weight buffer interface → sram_buffer
    // =====================================================================
    output reg         weight_wr_en,
    output reg  [3:0]  weight_wr_addr,
    output reg  [31:0] weight_wr_data,

    // =====================================================================
    // Weight readback interface → sram_buffer (BUG-01 fix)
    // =====================================================================
    output reg  [3:0]  weight_rd_addr,
    input  wire [31:0] weight_rd_data,

    // =====================================================================
    // Input activation (AI_INPUT register)
    // =====================================================================
    output wire [7:0]  input_act_0,       // activation a[0]
    output wire [7:0]  input_act_1,       // activation a[1]
    output wire [7:0]  input_act_2,       // activation a[2]
    output wire [7:0]  input_act_3,       // activation a[3]
    output wire        input_valid,       // inputs have been loaded (BUG-04: flag-based)

    // =====================================================================
    // Result buffer interface → result_buffer
    // =====================================================================
    input  wire [31:0] result_data,       // output data from result_buffer
    output reg  [1:0]  result_rd_addr,    // output select

    // =====================================================================
    // Bias register interface → result_buffer
    // =====================================================================
    output reg         bias_wr,
    output reg         bias_sel,
    output reg  [31:0] bias_data,

    // =====================================================================
    // Bias readback interface ← result_buffer (BUG-02 fix)
    // =====================================================================
    input  wire [31:0] bias_rd_data_0_1,
    input  wire [31:0] bias_rd_data_2_3,

    // =====================================================================
    // Activation function / scale registers
    // =====================================================================
    output reg  [3:0]  activation_fn,     // ACT_NONE, ACT_RELU, ACT_SIGMOID, ACT_TANH
    output reg  [31:0] scale_factor,       // Q8.8 scaling

    // =====================================================================
    // Interrupt mask / IRQ outputs
    // =====================================================================
    output reg         irq_done_en,        // DONE interrupt enable
    output reg         irq_error_en,       // ERROR interrupt enable
    output reg         irq_done_o,         // DONE IRQ output
    output reg         irq_error_o,        // ERROR IRQ output
    output reg         fault_o             // hard fault (to safety monitor)
);

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam AXI_RESP_OKAY   = 2'b00;
    localparam AXI_RESP_SLVERR = 2'b10;

    // -------------------------------------------------------------------------
    // Register file
    // -------------------------------------------------------------------------
    reg [31:0] reg_ai_ctrl;         // 0x00
    reg [31:0] reg_ai_status;       // 0x04 (not used; computed from ai_status_computed)
    reg [31:0] reg_ai_input;        // 0x18
    reg [31:0] reg_ai_activation;   // 0x34
    reg [31:0] reg_ai_scale;        // 0x38
    reg [31:0] reg_ai_intr_mask;    // 0x3C

    // Computed status
    wire [31:0] ai_status_computed;
    reg  [3:0]  cycle_count_captured;
    reg  [3:0]  error_code;

    // -------------------------------------------------------------------------
    // BUG-04 fix: input_written_flag replaces reduction-OR for input_valid
    //   Set when AI_INPUT is written, cleared when GO is pulsed.
    //   This correctly handles zero-valued input activations (e.g., ReLU zeros).
    // -------------------------------------------------------------------------
    reg input_written_flag;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            input_written_flag <= 1'b0;
        else if (wr_active && wr_is_input)
            input_written_flag <= 1'b1;
        else if (go)  // computation started — inputs consumed
            input_written_flag <= 1'b0;
    end

    // -------------------------------------------------------------------------
    // AXI write state machine
    // -------------------------------------------------------------------------
    reg [31:0] awaddr_latched;       // latched write address
    reg        aw_valid_latched;     // address phase complete

    // Write FSM states
    localparam W_IDLE  = 2'd0;
    localparam W_ADDR  = 2'd1;
    localparam W_DATA  = 2'd2;
    localparam W_RESP  = 2'd3;

    reg [1:0] w_state, w_next;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            w_state <= W_IDLE;
        else
            w_state <= w_next;
    end

    always @(*) begin
        w_next = w_state;
        case (w_state)
            W_IDLE: begin
                if (s_axi_awvalid && s_axi_wvalid)
                    w_next = W_RESP;    // both channels ready simultaneously
                else if (s_axi_awvalid)
                    w_next = W_ADDR;    // address first
                else if (s_axi_wvalid)
                    w_next = W_DATA;    // data first (AXI allows out-of-order arrival)
            end
            W_ADDR: begin
                if (s_axi_wvalid)
                    w_next = W_RESP;
            end
            W_DATA: begin
                if (s_axi_awvalid)
                    w_next = W_RESP;
            end
            W_RESP: begin
                if (s_axi_bready)
                    w_next = W_IDLE;
            end
            default: w_next = W_IDLE;
        endcase
    end

    // Write address handshake
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready     <= 1'b0;
            awaddr_latched    <= 32'd0;
            aw_valid_latched  <= 1'b0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    s_axi_awready <= 1'b1;
                    if (s_axi_awvalid) begin
                        awaddr_latched   <= s_axi_awaddr;
                        aw_valid_latched <= 1'b1;
                    end
                end
                W_ADDR: begin
                    s_axi_awready <= 1'b1;
                    if (s_axi_awvalid && !aw_valid_latched) begin
                        awaddr_latched   <= s_axi_awaddr;
                        aw_valid_latched <= 1'b1;
                    end
                end
                default: begin
                    s_axi_awready <= 1'b0;
                end
            endcase
            // Clear latched address after write completes
            if (w_state == W_RESP && s_axi_bready)
                aw_valid_latched <= 1'b0;
        end
    end

    // Write data handshake
    reg [31:0] wdata_latched;
    reg [3:0]  wstrb_latched;
    reg        wdata_valid_latched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_wready        <= 1'b0;
            wdata_latched       <= 32'd0;
            wstrb_latched       <= 4'd0;
            wdata_valid_latched <= 1'b0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    s_axi_wready <= 1'b1;
                    if (s_axi_wvalid) begin
                        wdata_latched       <= s_axi_wdata;
                        wstrb_latched       <= s_axi_wstrb;
                        wdata_valid_latched <= 1'b1;
                    end
                end
                W_DATA: begin
                    s_axi_wready <= 1'b1;
                    if (s_axi_wvalid && !wdata_valid_latched) begin
                        wdata_latched       <= s_axi_wdata;
                        wstrb_latched       <= s_axi_wstrb;
                        wdata_valid_latched <= 1'b1;
                    end
                end
                default: begin
                    s_axi_wready <= 1'b0;
                end
            endcase
            if (w_state == W_RESP && s_axi_bready)
                wdata_valid_latched <= 1'b0;
        end
    end

    // Write response
    reg [1:0] w_resp;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= AXI_RESP_OKAY;
        end else begin
            case (w_state)
                W_RESP: begin
                    s_axi_bvalid <= 1'b1;
                    s_axi_bresp  <= w_resp;
                end
                default: begin
                    if (s_axi_bready)
                        s_axi_bvalid <= 1'b0;
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // AXI read state machine
    // -------------------------------------------------------------------------
    localparam R_IDLE  = 2'd0;
    localparam R_ADDR  = 2'd1;
    localparam R_DATA  = 2'd2;

    reg [1:0] r_state, r_next;
    reg [31:0] araddr_latched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            r_state <= R_IDLE;
        else
            r_state <= r_next;
    end

    always @(*) begin
        r_next = r_state;
        case (r_state)
            R_IDLE:  if (s_axi_arvalid) r_next = R_ADDR;
            R_ADDR:  r_next = R_DATA;
            R_DATA:  if (s_axi_rready) r_next = R_IDLE;
            default: r_next = R_IDLE;
        endcase
    end

    // Read address handshake
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready    <= 1'b0;
            araddr_latched   <= 32'd0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    s_axi_arready <= 1'b1;
                    if (s_axi_arvalid) begin
                        araddr_latched <= s_axi_araddr;
                        s_axi_arready  <= 1'b0;
                    end
                end
                default: s_axi_arready <= 1'b0;
            endcase
        end
    end

    // Read data response
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= 32'd0;
            s_axi_rresp  <= AXI_RESP_OKAY;
        end else begin
            case (r_state)
                R_DATA: begin
                    s_axi_rvalid <= 1'b1;
                    s_axi_rdata  <= araddr_read_data;
                    s_axi_rresp  <= araddr_resp;
                end
                default: begin
                    if (s_axi_rready)
                        s_axi_rvalid <= 1'b0;
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Address decode and read data mux
    //
    // BUG-01 fix: AI_WEIGHT_0..3 now route through sram_buffer axi_rd port
    // BUG-02 fix: AI_BIAS_0_1 and AI_BIAS_2_3 now read actual bias values
    // -------------------------------------------------------------------------
    wire [5:0]  rd_offset = araddr_latched[7:2];   // 32-bit aligned offset
    reg  [31:0] araddr_read_data;
    reg  [1:0]  araddr_resp;

    always @(*) begin
        // Default outputs
        araddr_resp      = AXI_RESP_OKAY;
        araddr_read_data = 32'd0;
        // Drive weight_rd_addr to 0 unless a weight read is active
        weight_rd_addr   = 4'd0;
        // P0 FIX: default result_rd_addr to prevent latch inference
        result_rd_addr   = 2'd0;

        case (rd_offset)
            // 0x00 — AI_CTRL: RW
            6'h00: araddr_read_data = reg_ai_ctrl;

            // 0x04 — AI_STATUS: RO
            6'h01: araddr_read_data = ai_status_computed;

            // 0x08 — AI_WEIGHT_0: RW (BUG-01 fix — was SLVERR)
            6'h02: begin
                weight_rd_addr = 4'd0;
                araddr_read_data = weight_rd_data;
            end

            // 0x0C — AI_WEIGHT_1: RW (BUG-01 fix — was SLVERR)
            6'h03: begin
                weight_rd_addr = 4'd1;
                araddr_read_data = weight_rd_data;
            end

            // 0x10 — AI_WEIGHT_2: RW (BUG-01 fix — was SLVERR)
            6'h04: begin
                weight_rd_addr = 4'd2;
                araddr_read_data = weight_rd_data;
            end

            // 0x14 — AI_WEIGHT_3: RW (BUG-01 fix — was SLVERR)
            6'h05: begin
                weight_rd_addr = 4'd3;
                araddr_read_data = weight_rd_data;
            end

            // 0x18 — AI_INPUT: RW
            6'h06: araddr_read_data = reg_ai_input;

            // 0x1C — AI_BIAS_0_1: RW (BUG-02 fix — was always 0x0)
            6'h07: araddr_read_data = bias_rd_data_0_1;

            // 0x20 — AI_BIAS_2_3: RW (BUG-02 fix — was always 0x0)
            6'h08: araddr_read_data = bias_rd_data_2_3;

            // 0x24 — AI_OUTPUT_0: RO
            6'h09: begin result_rd_addr = 2'd0; araddr_read_data = result_data; end

            // 0x28 — AI_OUTPUT_1: RO
            6'h0A: begin result_rd_addr = 2'd1; araddr_read_data = result_data; end

            // 0x2C — AI_OUTPUT_2: RO
            6'h0B: begin result_rd_addr = 2'd2; araddr_read_data = result_data; end

            // 0x30 — AI_OUTPUT_3: RO
            6'h0C: begin result_rd_addr = 2'd3; araddr_read_data = result_data; end

            // 0x34 — AI_ACTIVATION: RW
            6'h0D: araddr_read_data = reg_ai_activation;

            // 0x38 — AI_SCALE: RW
            6'h0E: araddr_read_data = reg_ai_scale;

            // 0x3C — AI_INTR_MASK: RW
            6'h0F: araddr_read_data = reg_ai_intr_mask;

            // Reserved/unmapped offsets → SLVERR
            default: begin
                araddr_resp = AXI_RESP_SLVERR;
                araddr_read_data = 32'd0;
            end
        endcase
    end

    // REMOVED: bias_data_read register (was always 0x0 — BUG-02)
    // Bias readback now uses combinational bias_rd_data_0_1 / bias_rd_data_2_3 ports.

    // -------------------------------------------------------------------------
    // Write address decode and write data routing
    //   Evaluated when write completes (w_state == W_RESP)
    // -------------------------------------------------------------------------
    wire [5:0]  wr_offset = awaddr_latched[7:2];
    // Write decode
    wire wr_is_ctrl       = (wr_offset == 6'h00);
    wire wr_is_weight_0   = (wr_offset == 6'h02);
    wire wr_is_weight_1   = (wr_offset == 6'h03);
    wire wr_is_weight_2   = (wr_offset == 6'h04);
    wire wr_is_weight_3   = (wr_offset == 6'h05);
    wire wr_is_input      = (wr_offset == 6'h06);
    wire wr_is_bias_0_1   = (wr_offset == 6'h07);
    wire wr_is_bias_2_3   = (wr_offset == 6'h08);
    wire wr_is_activation = (wr_offset == 6'h0D);
    wire wr_is_scale      = (wr_offset == 6'h0E);
    wire wr_is_intr_mask  = (wr_offset == 6'h0F);
    wire wr_is_valid      = wr_is_ctrl || wr_is_weight_0 || wr_is_weight_1 ||
                            wr_is_weight_2 || wr_is_weight_3 || wr_is_input ||
                            wr_is_bias_0_1 || wr_is_bias_2_3 ||
                            wr_is_activation || wr_is_scale || wr_is_intr_mask;

    // Write response: computed from address validity (no combinational loop)
    always @(*) begin
        w_resp = wr_is_valid ? AXI_RESP_OKAY : AXI_RESP_SLVERR;
    end

    // wr_active: asserted during write response phase
    wire wr_active = (w_state == W_RESP);

    // -------------------------------------------------------------------------
    // Register write logic
    // -------------------------------------------------------------------------

    // AI_CTRL (0x00) — control register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ai_ctrl <= 32'd0;
        end else if (wr_active && wr_is_ctrl) begin
            // GO bit: auto-clear after one cycle
            // DONE/ERROR bits: write-1-to-clear
            if (wdata_latched[0]) begin
                // GO: will be pulsed by go logic below
                reg_ai_ctrl[0] <= 1'b0;  // auto-clear
            end
            if (wdata_latched[2]) begin
                reg_ai_ctrl[2] <= 1'b0;  // clear DONE
            end
            if (wdata_latched[3]) begin
                reg_ai_ctrl[3] <= 1'b0;  // clear ERROR
            end
            // BUG-03 fix: CLK_EN (bit 8) is now fully read-write via strb gating
            // Was: if (wdata_latched[8]) reg_ai_ctrl[8] <= 1'b1; // write-only-1
            // Now: follow wstrb[1] for byte-access semantics
            if (wstrb_latched[1]) begin
                reg_ai_ctrl[15:8] <= wdata_latched[15:8];  // includes CLK_EN at bit 8
            end
            if (wdata_latched[9]) begin
                reg_ai_ctrl[9] <= 1'b0;  // RST (self-clearing)
            end
            // Direct write for bits [7:4] (RELU_EN, QUANT_EN, reserved)
            if (wstrb_latched[0]) begin
                reg_ai_ctrl[7:0] <= wdata_latched[7:0];
            end
        end else begin
            // BUSY is read-only, driven by FSM
            reg_ai_ctrl[1] <= busy;
            // DONE is set by FSM, cleared by W1C above
            if (done)
                reg_ai_ctrl[2] <= 1'b1;
            if (clr_done)
                reg_ai_ctrl[2] <= 1'b0;
            // RST self-clearing
            if (reg_ai_ctrl[9])
                reg_ai_ctrl[9] <= 1'b0;
        end
    end

    // GO pulse generation
    reg go_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            go    <= 1'b0;
            go_d1 <= 1'b0;
        end else begin
            go_d1 <= 1'b0;
            go    <= 1'b0;
            if (wr_active && wr_is_ctrl && wdata_latched[0]) begin
                go    <= 1'b1;
                go_d1 <= 1'b1;
            end
            // Hold go for one cycle; then auto-clear
            if (go_d1) begin
                go <= 1'b0;
            end
        end
    end

    // Clear signals
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clr_done  <= 1'b0;
            clr_error <= 1'b0;
        end else begin
            clr_done  <= (wr_active && wr_is_ctrl && wdata_latched[2]);
            clr_error <= (wr_active && wr_is_ctrl && wdata_latched[3]);
        end
    end

    // Error code (for AI_STATUS)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            error_code <= 4'h0;
        end else begin
            error_code <= 4'h0; // no error by default
            // TODO: detect overflow, underflow, invalid config
        end
    end

    // AI_INPUT (0x18) — input activation register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ai_input <= 32'd0;
        end else if (wr_active && wr_is_input) begin
            if (wstrb_latched[0]) reg_ai_input[7:0]   <= wdata_latched[7:0];
            if (wstrb_latched[1]) reg_ai_input[15:8]  <= wdata_latched[15:8];
            if (wstrb_latched[2]) reg_ai_input[23:16] <= wdata_latched[23:16];
            if (wstrb_latched[3]) reg_ai_input[31:24] <= wdata_latched[31:24];
        end
    end

    // AI_ACTIVATION (0x34) — activation function control
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ai_activation <= 32'd0;
        end else if (wr_active && wr_is_activation) begin
            if (wstrb_latched[0]) reg_ai_activation[7:0] <= wdata_latched[7:0];
        end
    end

    // AI_SCALE (0x38) — scaling factor
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ai_scale <= 32'h0000_1000;  // default Q8.8 scale = 1.0
        end else if (wr_active && wr_is_scale) begin
            reg_ai_scale <= wdata_latched;
        end
    end

    // AI_INTR_MASK (0x3C) — interrupt mask
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ai_intr_mask <= 32'd0;
        end else if (wr_active && wr_is_intr_mask) begin
            if (wstrb_latched[0]) reg_ai_intr_mask[7:0] <= wdata_latched[7:0];
        end
    end

    // -------------------------------------------------------------------------
    // Weight buffer write routing
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_wr_en   <= 1'b0;
            weight_wr_addr <= 4'd0;
            weight_wr_data <= 32'd0;
        end else begin
            weight_wr_en <= 1'b0;
            if (wr_active && wr_is_weight_0) begin
                weight_wr_en   <= 1'b1;
                weight_wr_addr <= 4'd0;
                weight_wr_data <= wdata_latched;
            end else if (wr_active && wr_is_weight_1) begin
                weight_wr_en   <= 1'b1;
                weight_wr_addr <= 4'd1;
                weight_wr_data <= wdata_latched;
            end else if (wr_active && wr_is_weight_2) begin
                weight_wr_en   <= 1'b1;
                weight_wr_addr <= 4'd2;
                weight_wr_data <= wdata_latched;
            end else if (wr_active && wr_is_weight_3) begin
                weight_wr_en   <= 1'b1;
                weight_wr_addr <= 4'd3;
                weight_wr_data <= wdata_latched;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Bias write routing → result_buffer
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bias_wr   <= 1'b0;
            bias_sel  <= 1'b0;
            bias_data <= 32'd0;
        end else begin
            bias_wr <= 1'b0;
            if (wr_active && wr_is_bias_0_1) begin
                bias_wr   <= 1'b1;
                bias_sel  <= 1'b0;
                bias_data <= wdata_latched;
            end else if (wr_active && wr_is_bias_2_3) begin
                bias_wr   <= 1'b1;
                bias_sel  <= 1'b1;
                bias_data <= wdata_latched;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Derived outputs
    // -------------------------------------------------------------------------

    // Input activations (from AI_INPUT register)
    assign input_act_0  = reg_ai_input[7:0];
    assign input_act_1  = reg_ai_input[15:8];
    assign input_act_2  = reg_ai_input[23:16];
    assign input_act_3  = reg_ai_input[31:24];

    // BUG-04 fix: input_valid is now driven by input_written_flag,
    // not |reg_ai_input. This correctly handles zero-valued inputs.
    assign input_valid  = input_written_flag;

    // Activation function control
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            activation_fn <= 4'b0001;  // default: ACT_NONE
        end else begin
            activation_fn <= reg_ai_activation[3:0];
        end
    end

    // Scale factor
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scale_factor <= 32'h0000_1000;
        end else begin
            scale_factor <= reg_ai_scale;
        end
    end

    // Interrupt mask
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_done_en  <= 1'b0;
            irq_error_en <= 1'b0;
        end else begin
            irq_done_en  <= reg_ai_intr_mask[0];
            irq_error_en <= reg_ai_intr_mask[1];
        end
    end

    // Cycle count capture
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count_captured <= 4'd0;
        end else if (cycle_count_valid) begin
            cycle_count_captured <= cycle_count;  // both 4 bits wide
        end
    end

    // AI_STATUS register (computed)
    assign ai_status_computed = {16'd0, 4'd0, error_code, 4'd0, cycle_count_captured};

    // Combined status for top-level
    assign ctrl_status = reg_ai_ctrl;

    // -------------------------------------------------------------------------
    // Interrupt outputs
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_done_o  <= 1'b0;
            irq_error_o <= 1'b0;
        end else begin
            irq_done_o  <= irq_done_en && done;
            irq_error_o <= irq_error_en && (error_code != 4'd0);
        end
    end

    // Fault output (to safety monitor — block_interfaces.md §6.2)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fault_o <= 1'b0;
        end else begin
            // Hard fault on uncorrectable ECC error or hardware error
            // (error_code 0xFF = internal hardware fault)
            fault_o <= (error_code == 4'hF);
        end
    end

`ifndef SYNTHESIS
    // Simulation-only: print register writes
    always @(posedge clk) begin
        if (wr_active && wr_is_valid) begin
            $display("[axi4lite] WRITE offset=0x%06h data=0x%08h strb=%b",
                     wr_offset, wdata_latched, wstrb_latched);
        end
    end
`endif

endmodule
