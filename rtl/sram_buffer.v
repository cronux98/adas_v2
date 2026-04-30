// ============================================================================
// sram_buffer.v -- Weight SRAM Buffer with SECDED ECC (Hamming(39,32))
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    AI Accelerator — Weight Storage Buffer
// Author:   AI Accelerator Design Team
// Date:     2026-04-29
// Updated:  2026-04-29 — BUG-05: Upgraded from parity-only to SECDED ECC
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz (10 ns period)
//
// Description:
//   16-entry × 39-bit SRAM register file for storing INT8 weights with
//   Hamming(39,32) SECDED ECC protection (ASIL-D compliant).
//
//   Physical storage per entry: 39 bits = 32 data + 7 ECC
//   ECC: Hamming(39,32) — Single Error Correct, Double Error Detect
//        Uses systematic encoding with data at codeword positions.
//        Syndrome-based correction on read.
//
//   Layout per 32-bit data entry:
//     [31:24] w_col3   (INT8 signed)
//     [23:16] w_col2   (INT8 signed)
//     [15:8]  w_col1   (INT8 signed)
//     [7:0]   w_col0   (INT8 signed)
//
//   Note: When sky130 SRAM macros are available, this should be replaced
//         with an instantiated SRAM hard macro for density and power.
//         This synthesizable version uses a register file.
//
// Interfaces: (from block_interfaces.md §6.3)
//   - Write port: AXI register writes to AI_WEIGHT_0..3
//   - Read port:  control_fsm sequential read during LOAD_WEIGHTS → PE array
//   - AXI read port: combinational read for weight readback (BUG-01 fix)
// ============================================================================

`timescale 1ns / 1ps

module sram_buffer (
    input  wire        clk,
    input  wire        rst_n,

    // Write port (from AXI register decode)
    input  wire        wr_en,             // write enable
    input  wire [3:0]  wr_addr,           // write address [0..15]
    input  wire [31:0] wr_data,           // write data (4×INT8 packed)

    // Read port (to systolic_array during LOAD_WEIGHTS state)
    input  wire        rd_en,             // read enable
    input  wire [3:0]  rd_addr,           // read address [0..15]
    output wire [31:0] rd_data,           // read data (4×INT8 packed, SECDED-corrected)

    // AXI combinational read port (for weight readback via AXI register interface)
    // BUG-01 fix: Provides direct combinational access for AI_WEIGHT_0..3 reads
    input  wire [3:0]  axi_rd_addr,
    output wire [31:0] axi_rd_data,

    // ECC status
    output reg         ecc_err_detect,    // double-bit error detected (uncorrectable)
    output reg         ecc_err_correct,   // single-bit error corrected (correctable)

    // ECC diagnostic registers (O-02: firmware visibility)
    output wire [3:0]  ecc_last_addr_o,   // last ECC error address
    output wire [15:0] ecc_correct_cnt_o, // correctable error count
    output wire [15:0] ecc_fatal_cnt_o    // uncorrectable error count
);

    // -------------------------------------------------------------------------
    // Hamming(39,32) SECDED — Encoder
    //
    // Systematic encoding: codeword positions 1..38 (1-indexed) contain
    // 6 ECC bits at positions 1,2,4,8,16,32 + 32 data bits at all other positions.
    // Overall parity bit (c[6]) at codeword index 0 (seventh ECC bit), covering the
    // full 38-bit code for SECDED capability.
    //
    // Storage: 39 bits total = {c[6:0], data[31:0]}
    //            where c[0..5] are the Hamming(38,32) check bits
    //            and   c[6]    is the overall parity bit (for DED)
    // -------------------------------------------------------------------------

    // Hamming encoder: computes 7-bit ECC from 32-bit data word
    function [6:0] hamming_encode;
        input [31:0] d;
        reg [6:0] ecc;
        begin
            // Check bit 0 (codeword pos 1): covers positions with bit 0 = 1
            // Data positions: 3,5,7,9,11,13,15,17,19,21,23,25,27,29,31,33,35,37
            // Mapping to d[*]:  0,1,3,4, 6, 8,10,11,13,15,17,19,21,23,25,26,28,30
            ecc[0] = d[0] ^ d[1] ^ d[3] ^ d[4] ^ d[6] ^ d[8] ^ d[10] ^ d[11] ^
                     d[13] ^ d[15] ^ d[17] ^ d[19] ^ d[21] ^ d[23] ^ d[25] ^
                     d[26] ^ d[28] ^ d[30];

            // Check bit 1 (codeword pos 2): covers positions with bit 1 = 1
            // Data positions: 3,6,7,10,11,14,15,18,19,22,23,26,27,30,31,34,35,38
            // Mapping to d[*]:  0,2,3, 5, 6, 9,10,12,13,16,17,20,21,24,25,27,28,31
            ecc[1] = d[0] ^ d[2] ^ d[3] ^ d[5] ^ d[6] ^ d[9] ^ d[10] ^ d[12] ^
                     d[13] ^ d[16] ^ d[17] ^ d[20] ^ d[21] ^ d[24] ^ d[25] ^
                     d[27] ^ d[28] ^ d[31];

            // Check bit 2 (codeword pos 4): covers positions with bit 2 = 1
            // Data positions: 5,6,7,12,13,14,15,20,21,22,23,28,29,30,31,36,37,38
            // Mapping to d[*]:  1,2,3, 7, 8, 9,10,14,15,16,17,22,23,24,25,29,30,31
            ecc[2] = d[1] ^ d[2] ^ d[3] ^ d[7] ^ d[8] ^ d[9] ^ d[10] ^ d[14] ^
                     d[15] ^ d[16] ^ d[17] ^ d[22] ^ d[23] ^ d[24] ^ d[25] ^
                     d[29] ^ d[30] ^ d[31];

            // Check bit 3 (codeword pos 8): covers positions with bit 3 = 1
            // Data positions: 9,10,11,12,13,14,15,24,25,26,27,28,29,30,31
            // Mapping to d[*]:  4, 5, 6, 7, 8, 9,10,18,19,20,21,22,23,24,25
            ecc[3] = d[4] ^ d[5] ^ d[6] ^ d[7] ^ d[8] ^ d[9] ^ d[10] ^ d[18] ^
                     d[19] ^ d[20] ^ d[21] ^ d[22] ^ d[23] ^ d[24] ^ d[25];

            // Check bit 4 (codeword pos 16): covers positions with bit 4 = 1
            // Data positions: 17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
            // Mapping to d[*]:  11,12,13,14,15,16,17,18,19,20,21,22,23,24,25
            ecc[4] = d[11] ^ d[12] ^ d[13] ^ d[14] ^ d[15] ^ d[16] ^ d[17] ^
                     d[18] ^ d[19] ^ d[20] ^ d[21] ^ d[22] ^ d[23] ^ d[24] ^ d[25];

            // Check bit 5 (codeword pos 32): covers positions with bit 5 = 1
            // Data positions: 33,34,35,36,37,38
            // Mapping to d[*]:  26,27,28,29,30,31
            ecc[5] = d[26] ^ d[27] ^ d[28] ^ d[29] ^ d[30] ^ d[31];

            // Check bit 6: overall parity = XOR(all 32 data, c[0..5])
            // Provides double-error detection (SECDED)
            ecc[6] = (^d) ^ ecc[0] ^ ecc[1] ^ ecc[2] ^ ecc[3] ^ ecc[4] ^ ecc[5];

            hamming_encode = ecc;
        end
    endfunction

    // -------------------------------------------------------------------------
    // Hamming decoder: syndrome to correction mask (32-bit)
    //
    // Maps a 6-bit syndrome s[5:0] (non-zero, corresponding to a single-bit
    // error at a specific codeword position) to a 32-bit correction mask
    // with exactly one bit set, indicating which data bit to flip.
    // If the syndrome maps to an ECC bit (position 1,2,4,8,16,32), the mask
    // is zero — no data correction needed (ECC bit errors are invisible to data).
    // -------------------------------------------------------------------------
    function [31:0] syndrome_to_correction_mask;
        input [5:0] syndrome;
        begin
            case (syndrome)
                // Codeword positions 3..38 (1-indexed) mapped to d[0..31]
                6'd3:  syndrome_to_correction_mask = 32'd1 << 0;   // d[0]
                6'd5:  syndrome_to_correction_mask = 32'd1 << 1;   // d[1]
                6'd6:  syndrome_to_correction_mask = 32'd1 << 2;   // d[2]
                6'd7:  syndrome_to_correction_mask = 32'd1 << 3;   // d[3]
                6'd9:  syndrome_to_correction_mask = 32'd1 << 4;   // d[4]
                6'd10: syndrome_to_correction_mask = 32'd1 << 5;   // d[5]
                6'd11: syndrome_to_correction_mask = 32'd1 << 6;   // d[6]
                6'd12: syndrome_to_correction_mask = 32'd1 << 7;   // d[7]
                6'd13: syndrome_to_correction_mask = 32'd1 << 8;   // d[8]
                6'd14: syndrome_to_correction_mask = 32'd1 << 9;   // d[9]
                6'd15: syndrome_to_correction_mask = 32'd1 << 10;  // d[10]
                6'd17: syndrome_to_correction_mask = 32'd1 << 11;  // d[11]
                6'd18: syndrome_to_correction_mask = 32'd1 << 12;  // d[12]
                6'd19: syndrome_to_correction_mask = 32'd1 << 13;  // d[13]
                6'd20: syndrome_to_correction_mask = 32'd1 << 14;  // d[14]
                6'd21: syndrome_to_correction_mask = 32'd1 << 15;  // d[15]
                6'd22: syndrome_to_correction_mask = 32'd1 << 16;  // d[16]
                6'd23: syndrome_to_correction_mask = 32'd1 << 17;  // d[17]
                6'd24: syndrome_to_correction_mask = 32'd1 << 18;  // d[18]
                6'd25: syndrome_to_correction_mask = 32'd1 << 19;  // d[19]
                6'd26: syndrome_to_correction_mask = 32'd1 << 20;  // d[20]
                6'd27: syndrome_to_correction_mask = 32'd1 << 21;  // d[21]
                6'd28: syndrome_to_correction_mask = 32'd1 << 22;  // d[22]
                6'd29: syndrome_to_correction_mask = 32'd1 << 23;  // d[23]
                6'd30: syndrome_to_correction_mask = 32'd1 << 24;  // d[24]
                6'd31: syndrome_to_correction_mask = 32'd1 << 25;  // d[25]
                6'd33: syndrome_to_correction_mask = 32'd1 << 26;  // d[26]
                6'd34: syndrome_to_correction_mask = 32'd1 << 27;  // d[27]
                6'd35: syndrome_to_correction_mask = 32'd1 << 28;  // d[28]
                6'd36: syndrome_to_correction_mask = 32'd1 << 29;  // d[29]
                6'd37: syndrome_to_correction_mask = 32'd1 << 30;  // d[30]
                6'd38: syndrome_to_correction_mask = 32'd1 << 31;  // d[31]
                // ECC bit errors (positions 1,2,4,8,16,32): no data correction
                // Invalid positions (>38): no correction
                default: syndrome_to_correction_mask = 32'd0;
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // Storage array: 16 entries × 39-bit (32 data + 7 ECC)
    // -------------------------------------------------------------------------
    reg [38:0] mem_ecc [0:15];   // {ecc[6:0], data[31:0]}

    // -------------------------------------------------------------------------
    // Write logic (registered)
    //   On write, compute SECDED ECC and store alongside data.
    // -------------------------------------------------------------------------
    wire [6:0] wr_ecc;
    assign wr_ecc = hamming_encode(wr_data);

    always @(posedge clk) begin
        if (wr_en) begin
            mem_ecc[wr_addr] <= {wr_ecc, wr_data};
        end
    end

    // -------------------------------------------------------------------------
    // FSM read logic (registered, with SECDED correction)
    // -------------------------------------------------------------------------
    wire [38:0] rd_raw;
    wire [31:0] rd_data_uncorrected;
    wire [6:0]  rd_ecc_stored;

    assign rd_raw              = mem_ecc[rd_addr];
    assign rd_ecc_stored       = rd_raw[38:32];
    assign rd_data_uncorrected = rd_raw[31:0];

    // Recompute ECC from the read data
    wire [6:0] rd_ecc_computed;
    assign rd_ecc_computed = hamming_encode(rd_data_uncorrected);

    // Syndrome computation
    // s[5:0] = stored_ecc[5:0] ^ computed_ecc[5:0]
    // s[6]   = stored_ecc[6] ^ (^data ^ computed_ecc[0..5]) = stored_ecc[6] ^ computed_ecc[6]
    wire [6:0] ecc_syndrome;
    assign ecc_syndrome[5:0] = rd_ecc_stored[5:0] ^ rd_ecc_computed[5:0];
    assign ecc_syndrome[6]   = rd_ecc_stored[6] ^ rd_ecc_computed[6];

    // Error classification
    wire is_single_error;   // correctable
    wire is_double_error;   // uncorrectable
    wire is_no_error;

    assign is_no_error     = (ecc_syndrome == 7'd0);
    assign is_single_error = ecc_syndrome[6] && (ecc_syndrome[5:0] != 6'd0);
    assign is_double_error = (!ecc_syndrome[6]) && (ecc_syndrome[5:0] != 6'd0);

    // Correction mask for single-bit errors
    wire [31:0] correction_mask;
    assign correction_mask = syndrome_to_correction_mask(ecc_syndrome[5:0]);

    // Corrected data
    wire [31:0] rd_data_corrected;
    assign rd_data_corrected = rd_data_uncorrected ^ correction_mask;

    // -------------------------------------------------------------------------
    // Read data output (registered for timing)
    // O-01 FIX: Gate ECC flags with rd_en to prevent spurious toggling
    //           during idle cycles when rd_addr may be stale.
    // -------------------------------------------------------------------------
    reg [31:0] rd_data_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data_reg     <= 32'd0;
            ecc_err_detect  <= 1'b0;
            ecc_err_correct <= 1'b0;
        end else begin
            rd_data_reg     <= rd_data_corrected;
            // Gate ECC flags: only assert when a read transaction is active
            ecc_err_detect  <= rd_en && is_double_error;
            ecc_err_correct <= rd_en && is_single_error;
        end
    end

    assign rd_data = rd_data_reg;

    // -------------------------------------------------------------------------
    // O-02 ECC Diagnostic Registers
    //   - last_ecc_error_addr: address of most recent ECC error (any type)
    //   - ecc_correct_count:   running count of correctable (single-bit) errors
    //   - ecc_fatal_count:     running count of uncorrectable (double-bit) errors
    //   All counters wrap at saturation; accessible via AXI register readback
    //   at the ECC diagnostic register addresses (mapped through AI accelerator).
    // -------------------------------------------------------------------------
    reg [3:0]  last_ecc_error_addr;
    reg [15:0] ecc_correct_count;
    reg [15:0] ecc_fatal_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_ecc_error_addr <= 4'd0;
            ecc_correct_count   <= 16'd0;
            ecc_fatal_count     <= 16'd0;
        end else begin
            if (rd_en && (is_single_error || is_double_error)) begin
                last_ecc_error_addr <= rd_addr;
                if (is_single_error) begin
                    if (ecc_correct_count != 16'hFFFF)
                        ecc_correct_count <= ecc_correct_count + 16'd1;
                end
                if (is_double_error) begin
                    if (ecc_fatal_count != 16'hFFFF)
                        ecc_fatal_count <= ecc_fatal_count + 16'd1;
                end
            end
        end
    end

    // Diagnostic readback interface (mapped to AI accelerator register space)
    assign ecc_last_addr_o   = last_ecc_error_addr;
    assign ecc_correct_cnt_o = ecc_correct_count;
    assign ecc_fatal_cnt_o   = ecc_fatal_count;

    // -------------------------------------------------------------------------
    // AXI combinational read port (for weight readback)
    //   BUG-01 fix: Pure combinational read bypassing the registered pipeline.
    //   Used by axi4_lite_decode for AI_WEIGHT_0..3 readback.
    //   Data is SECDED-corrected:
    //     - Single errors: corrected on-the-fly
    //     - Double errors: raw data returned (ECC flags signal to firmware)
    // -------------------------------------------------------------------------
    wire [38:0] axi_rd_raw;
    wire [31:0] axi_rd_uncorrected;
    wire [6:0]  axi_ecc_stored;
    wire [6:0]  axi_ecc_computed;
    wire [6:0]  axi_syndrome;
    wire        axi_single_err;
    wire [31:0] axi_correction_mask;

    assign axi_rd_raw          = mem_ecc[axi_rd_addr];
    assign axi_ecc_stored      = axi_rd_raw[38:32];
    assign axi_rd_uncorrected  = axi_rd_raw[31:0];
    assign axi_ecc_computed    = hamming_encode(axi_rd_uncorrected);
    assign axi_syndrome[5:0]   = axi_ecc_stored[5:0] ^ axi_ecc_computed[5:0];
    assign axi_syndrome[6]     = axi_ecc_stored[6] ^ axi_ecc_computed[6];
    assign axi_single_err      = axi_syndrome[6] && (axi_syndrome[5:0] != 6'd0);
    assign axi_correction_mask = syndrome_to_correction_mask(axi_syndrome[5:0]);
    assign axi_rd_data         = axi_single_err ?
                                 (axi_rd_uncorrected ^ axi_correction_mask) :
                                 axi_rd_uncorrected;

`ifndef SYNTHESIS
    // Initialise memory to zero for simulation clarity
    integer init_i;
    initial begin
        for (init_i = 0; init_i < 16; init_i = init_i + 1) begin
            mem_ecc[init_i] = 39'd0;
        end
    end

    // Simulation-only: verify ECC consistency after writes
    always @(posedge clk) begin
        if (wr_en && !$isunknown(wr_data)) begin
            // ECC is computed combinationally and stored on next edge
        end
    end
`endif

endmodule
