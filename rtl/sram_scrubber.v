// ============================================================================
// sram_scrubber.v — Background Memory Scrubber with SECDED ECC
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    Memory Scrubber for TCM / SRAM with Hamming(39,32) SECDED
// Author:   Mei-Lin Chang, Digital Design Engineer
// Date:     2026-04-29 (Phase 2b)
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz
//
// Description:
//   Simple FSM: periodically reads each memory address → SECDED decode →
//   if 1-bit error found, correct and write back. Prevents single-bit
//   error accumulation into uncorrectable double-bit errors.
//
// Scrubbing period:
//   TCM: 2048 words × ~10 cycles/word ≈ 20,480 cycles ≈ 205 µs
//   SRAM buffer: 16 words × ~10 cycles/word ≈ 160 cycles ≈ 1.6 µs
//   Full sweep period: ~1 ms at 100 MHz (with configurable interval)
//
// State machine (synthesizable, no behavioral loops):
//   IDLE → READ → DECODE → (CORRECT / NEXT) → WAIT_INTERVAL → READ ...
// ============================================================================

`timescale 1ns / 1ps

module sram_scrubber (
    input  wire        clk,
    input  wire        rst_n,

    // Control register inputs (from fault_aggregator SCRUB_CTRL register)
    input  wire        scr_enable,        // master enable
    input  wire [15:0] scr_interval,      // cycles to wait between addresses (0 = continuous)

    // Status outputs (to SCRUB_CTRL register)
    output reg         scr_busy,          // scrub operation in progress
    output reg         scr_sweep_done,    // one full sweep completed (pulse)
    output reg  [15:0] scr_correct_count, // total corrections this sweep
    output reg  [10:0] scr_addr_current,  // current address (diagnostic)

    // --- TCM Scrubber Interface ---
    output reg         tcm_scr_req,       // request read from TCM
    output reg  [10:0] tcm_scr_addr,      // word address
    input  wire [38:0] tcm_scr_raw,       // raw {ECC[6:0], data[31:0]}
    output reg         tcm_scr_we,        // write corrected data
    output reg  [31:0] tcm_scr_wdata,     // corrected write data
    output reg  [6:0]  tcm_scr_ecc        // recomputed ECC

    // NOTE: SRAM buffer scrubber interface can be added by instantiating
    // a second scrubber instance, or by time-multiplexing this one.
);

    // =========================================================================
    // Hamming(39,32) SECDED — Encoder (identical to sram_buffer.v)
    // =========================================================================

    function [6:0] hamming_encode;
        input [31:0] d;
        reg [6:0] ecc;
        begin
            ecc[0] = d[0] ^ d[1] ^ d[3] ^ d[4] ^ d[6] ^ d[8] ^ d[10] ^ d[11] ^
                     d[13] ^ d[15] ^ d[17] ^ d[19] ^ d[21] ^ d[23] ^ d[25] ^
                     d[26] ^ d[28] ^ d[30];
            ecc[1] = d[0] ^ d[2] ^ d[3] ^ d[5] ^ d[6] ^ d[9] ^ d[10] ^ d[12] ^
                     d[13] ^ d[16] ^ d[17] ^ d[20] ^ d[21] ^ d[24] ^ d[25] ^
                     d[27] ^ d[28] ^ d[31];
            ecc[2] = d[1] ^ d[2] ^ d[3] ^ d[7] ^ d[8] ^ d[9] ^ d[10] ^ d[14] ^
                     d[15] ^ d[16] ^ d[17] ^ d[22] ^ d[23] ^ d[24] ^ d[25] ^
                     d[29] ^ d[30] ^ d[31];
            ecc[3] = d[4] ^ d[5] ^ d[6] ^ d[7] ^ d[8] ^ d[9] ^ d[10] ^ d[18] ^
                     d[19] ^ d[20] ^ d[21] ^ d[22] ^ d[23] ^ d[24] ^ d[25];
            ecc[4] = d[11] ^ d[12] ^ d[13] ^ d[14] ^ d[15] ^ d[16] ^ d[17] ^
                     d[18] ^ d[19] ^ d[20] ^ d[21] ^ d[22] ^ d[23] ^ d[24] ^ d[25];
            ecc[5] = d[26] ^ d[27] ^ d[28] ^ d[29] ^ d[30] ^ d[31];
            ecc[6] = (^d) ^ ecc[0] ^ ecc[1] ^ ecc[2] ^ ecc[3] ^ ecc[4] ^ ecc[5];
            hamming_encode = ecc;
        end
    endfunction

    // =========================================================================
    // Hamming Decoder: syndrome → correction mask (32-bit)
    // =========================================================================

    function [31:0] syndrome_to_correction_mask;
        input [5:0] syndrome;
        begin
            case (syndrome)
                6'd3:  syndrome_to_correction_mask = 32'd1 << 0;
                6'd5:  syndrome_to_correction_mask = 32'd1 << 1;
                6'd6:  syndrome_to_correction_mask = 32'd1 << 2;
                6'd7:  syndrome_to_correction_mask = 32'd1 << 3;
                6'd9:  syndrome_to_correction_mask = 32'd1 << 4;
                6'd10: syndrome_to_correction_mask = 32'd1 << 5;
                6'd11: syndrome_to_correction_mask = 32'd1 << 6;
                6'd12: syndrome_to_correction_mask = 32'd1 << 7;
                6'd13: syndrome_to_correction_mask = 32'd1 << 8;
                6'd14: syndrome_to_correction_mask = 32'd1 << 9;
                6'd15: syndrome_to_correction_mask = 32'd1 << 10;
                6'd17: syndrome_to_correction_mask = 32'd1 << 11;
                6'd18: syndrome_to_correction_mask = 32'd1 << 12;
                6'd19: syndrome_to_correction_mask = 32'd1 << 13;
                6'd20: syndrome_to_correction_mask = 32'd1 << 14;
                6'd21: syndrome_to_correction_mask = 32'd1 << 15;
                6'd22: syndrome_to_correction_mask = 32'd1 << 16;
                6'd23: syndrome_to_correction_mask = 32'd1 << 17;
                6'd24: syndrome_to_correction_mask = 32'd1 << 18;
                6'd25: syndrome_to_correction_mask = 32'd1 << 19;
                6'd26: syndrome_to_correction_mask = 32'd1 << 20;
                6'd27: syndrome_to_correction_mask = 32'd1 << 21;
                6'd28: syndrome_to_correction_mask = 32'd1 << 22;
                6'd29: syndrome_to_correction_mask = 32'd1 << 23;
                6'd30: syndrome_to_correction_mask = 32'd1 << 24;
                6'd31: syndrome_to_correction_mask = 32'd1 << 25;
                6'd33: syndrome_to_correction_mask = 32'd1 << 26;
                6'd34: syndrome_to_correction_mask = 32'd1 << 27;
                6'd35: syndrome_to_correction_mask = 32'd1 << 28;
                6'd36: syndrome_to_correction_mask = 32'd1 << 29;
                6'd37: syndrome_to_correction_mask = 32'd1 << 30;
                6'd38: syndrome_to_correction_mask = 32'd1 << 31;
                default: syndrome_to_correction_mask = 32'd0;
            endcase
        end
    endfunction

    // =========================================================================
    // Scrubbing Parameters
    // =========================================================================
    // TCM has 2048 words → 11-bit address space
    localparam TCM_DEPTH     = 2048;
    localparam TCM_ADDR_W    = 11;

    // =========================================================================
    // FSM States
    // =========================================================================
    localparam S_IDLE           = 3'd0;
    localparam S_READ           = 3'd1;  // assert scr_req, wait 1 cycle
    localparam S_DECODE         = 3'd2;  // raw data available, decode SECDED
    localparam S_CORRECT        = 3'd3;  // assert scr_we to fix single-bit error
    localparam S_NEXT           = 3'd4;  // increment address or sweep done
    localparam S_WAIT           = 3'd5;  // wait for interval between addresses

    reg [2:0] state, state_next;
    reg [10:0] addr;
    reg [15:0] wait_cnt;

    // Registered raw data from TCM read (latched during S_READ→S_DECODE)
    reg [38:0] rd_raw_reg;
    reg [31:0] rd_data_reg;
    reg [6:0]  rd_ecc_reg;

    // SECDED decode wires (computed from registered data)
    wire [6:0]  ecc_computed;
    wire [6:0]  syndrome;
    wire        is_single_err;
    wire        is_double_err;
    wire [31:0] corr_mask;
    wire [31:0] corrected_data;
    wire [6:0]  new_ecc;

    assign ecc_computed    = hamming_encode(rd_data_reg);
    assign syndrome[5:0]   = rd_ecc_reg[5:0] ^ ecc_computed[5:0];
    assign syndrome[6]     = rd_ecc_reg[6]   ^ ecc_computed[6];
    assign is_single_err   = syndrome[6] && (syndrome[5:0] != 6'd0);
    assign is_double_err   = (!syndrome[6]) && (syndrome[5:0] != 6'd0);
    assign corr_mask       = syndrome_to_correction_mask(syndrome[5:0]);
    assign corrected_data  = rd_data_reg ^ corr_mask;
    assign new_ecc         = hamming_encode(corrected_data);

    // =========================================================================
    // FSM — Sequential Logic
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            addr          <= 11'd0;
            wait_cnt      <= 16'd0;
            rd_raw_reg    <= 39'd0;
            rd_data_reg   <= 32'd0;
            rd_ecc_reg    <= 7'd0;
            scr_busy      <= 1'b0;
            scr_sweep_done<= 1'b0;
            scr_correct_count <= 16'd0;
            scr_addr_current  <= 11'd0;
            tcm_scr_req   <= 1'b0;
            tcm_scr_addr  <= 11'd0;
            tcm_scr_we    <= 1'b0;
            tcm_scr_wdata <= 32'd0;
            tcm_scr_ecc   <= 7'd0;
        end else begin
            // Default: de-assert strobes
            tcm_scr_req   <= 1'b0;
            tcm_scr_we    <= 1'b0;
            scr_sweep_done<= 1'b0;

            case (state)
                S_IDLE: begin
                    scr_busy <= 1'b0;
                    if (scr_enable) begin
                        state    <= S_READ;
                        scr_busy <= 1'b1;
                        addr     <= 11'd0;
                        scr_correct_count <= 16'd0;
                    end
                end

                S_READ: begin
                    // Request read from TCM
                    tcm_scr_req  <= 1'b1;
                    tcm_scr_addr <= addr;
                    scr_addr_current <= addr;
                    state <= S_DECODE;
                end

                S_DECODE: begin
                    // Raw data from TCM arrives this cycle (registered in TCM)
                    rd_raw_reg  <= tcm_scr_raw;
                    rd_data_reg <= tcm_scr_raw[31:0];
                    rd_ecc_reg  <= tcm_scr_raw[38:32];
                    state <= S_CORRECT;
                end

                S_CORRECT: begin
                    // Now we have rd_data_reg, rd_ecc_reg, and decoded syndrome
                    if (is_single_err) begin
                        // Write corrected data + recomputed ECC back
                        tcm_scr_we    <= 1'b1;
                        tcm_scr_wdata <= corrected_data;
                        tcm_scr_ecc   <= new_ecc;
                        scr_correct_count <= scr_correct_count + 16'd1;
                    end
                    // Note: double-bit errors are logged by TCM's own error flags;
                    // the scrubber cannot fix them, but the fault aggregator
                    // will detect them through ecc_err_fatal_o from the TCM.
                    state <= S_NEXT;
                end

                S_NEXT: begin
                    if (addr == (TCM_DEPTH - 1)) begin
                        // Sweep complete
                        scr_sweep_done <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        addr <= addr + 11'd1;
                        if (scr_interval == 16'd0) begin
                            // Continuous scrub (no wait)
                            state <= S_READ;
                        end else begin
                            wait_cnt <= scr_interval;
                            state <= S_WAIT;
                        end
                    end
                end

                S_WAIT: begin
                    if (wait_cnt == 16'd0) begin
                        state <= S_READ;
                    end else begin
                        wait_cnt <= wait_cnt - 16'd1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
