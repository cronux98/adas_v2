// ============================================================================
// tcm_8kb.v — 8KB Tightly Coupled Memory with SECDED ECC (Hamming(39,32))
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    8KB TCM (2048 × 39-bit) with SECDED protection
// Author:   Mei-Lin Chang, Digital Design Engineer
// Date:     2026-04-29
// Updated:  2026-04-29 — Phase 2b: Upgraded from byte-parity to SECDED ECC
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz
//
// Interface (block_interfaces.md §4):
//   Single-cycle access, 4-bit byte write enable, SECDED ECC protection
//
// ECC: Hamming(39,32) — Single Error Correct, Double Error Detect
//   - Encode on write: 32-bit data → 39-bit codeword (32 data + 7 check bits)
//   - Decode on read: detect 1-bit / 2-bit errors, CORRECT 1-bit errors
//   - ecc_err_correct_o: single-bit error corrected (firmware informational)
//   - ecc_err_fatal_o:   double-bit error detected (uncorrectable → safety action)
//   - ECC functions REUSED from sram_buffer.v Hamming(39,32) implementation
//
// Scrubber port: enables background memory scrubbing to prevent accumulation
//   of single-bit errors into uncorrectable double-bit errors.
// ============================================================================

`timescale 1ns / 1ps

module tcm_8kb (
    input  wire        clk_i,
    input  wire        rst_n_i,  // not used (SRAM retains on reset)

    input  wire [12:0] addr_i,      // byte address bits [14:2]
    input  wire [31:0] wdata_i,
    input  wire [3:0]  we_i,        // byte write enables
    input  wire        req_i,

    output reg  [31:0] rdata_o,
    output reg         ack_o,
    output reg         ecc_err_correct_o,   // single-bit error corrected
    output reg         ecc_err_fatal_o,     // double-bit error (uncorrectable)

    // Scrubber interface
    input  wire        scr_req_i,           // scrubber requests read
    input  wire [10:0] scr_addr_i,          // word address for scrub
    output reg  [38:0] scr_raw_o,           // raw {ECC[6:0], data[31:0]} readback
    input  wire        scr_we_i,            // scrubber writes corrected data
    input  wire [31:0] scr_wdata_i,         // corrected data from scrubber
    input  wire [6:0]  scr_ecc_i            // recomputed ECC from scrubber
);

    // =========================================================================
    // Hamming(39,32) SECDED — Encoder (REUSED from sram_buffer.v)
    // =========================================================================

    function [6:0] hamming_encode;
        input [31:0] d;
        reg [6:0] ecc;
        begin
            // Check bit 0 (codeword pos 1)
            ecc[0] = d[0] ^ d[1] ^ d[3] ^ d[4] ^ d[6] ^ d[8] ^ d[10] ^ d[11] ^
                     d[13] ^ d[15] ^ d[17] ^ d[19] ^ d[21] ^ d[23] ^ d[25] ^
                     d[26] ^ d[28] ^ d[30];
            // Check bit 1 (codeword pos 2)
            ecc[1] = d[0] ^ d[2] ^ d[3] ^ d[5] ^ d[6] ^ d[9] ^ d[10] ^ d[12] ^
                     d[13] ^ d[16] ^ d[17] ^ d[20] ^ d[21] ^ d[24] ^ d[25] ^
                     d[27] ^ d[28] ^ d[31];
            // Check bit 2 (codeword pos 4)
            ecc[2] = d[1] ^ d[2] ^ d[3] ^ d[7] ^ d[8] ^ d[9] ^ d[10] ^ d[14] ^
                     d[15] ^ d[16] ^ d[17] ^ d[22] ^ d[23] ^ d[24] ^ d[25] ^
                     d[29] ^ d[30] ^ d[31];
            // Check bit 3 (codeword pos 8)
            ecc[3] = d[4] ^ d[5] ^ d[6] ^ d[7] ^ d[8] ^ d[9] ^ d[10] ^ d[18] ^
                     d[19] ^ d[20] ^ d[21] ^ d[22] ^ d[23] ^ d[24] ^ d[25];
            // Check bit 4 (codeword pos 16)
            ecc[4] = d[11] ^ d[12] ^ d[13] ^ d[14] ^ d[15] ^ d[16] ^ d[17] ^
                     d[18] ^ d[19] ^ d[20] ^ d[21] ^ d[22] ^ d[23] ^ d[24] ^ d[25];
            // Check bit 5 (codeword pos 32)
            ecc[5] = d[26] ^ d[27] ^ d[28] ^ d[29] ^ d[30] ^ d[31];
            // Check bit 6: overall parity = XOR(all data, ecc[0..5])
            ecc[6] = (^d) ^ ecc[0] ^ ecc[1] ^ ecc[2] ^ ecc[3] ^ ecc[4] ^ ecc[5];
            hamming_encode = ecc;
        end
    endfunction

    // =========================================================================
    // Hamming decoder: syndrome → correction mask (32-bit) (REUSED from sram_buffer.v)
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
    // Storage array: 2048 words × 39 bits (32 data + 7 ECC) = 8 KB + 1.75 KB ECC
    // =========================================================================
    reg [38:0] mem [0:2047];   // {ecc[6:0], data[31:0]}

    wire [10:0] word_addr = addr_i[12:2];  // word-aligned

    // =========================================================================
    // SECDED Read Decode (combinational, fed from raw memory read)
    // =========================================================================
    wire [38:0] rd_raw         = mem[word_addr];
    wire [31:0] rd_data        = rd_raw[31:0];
    wire [6:0]  rd_ecc         = rd_raw[38:32];
    wire [6:0]  rd_ecc_comp    = hamming_encode(rd_data);

    wire [6:0]  rd_syndrome;
    assign rd_syndrome[5:0] = rd_ecc[5:0] ^ rd_ecc_comp[5:0];
    assign rd_syndrome[6]   = rd_ecc[6]   ^ rd_ecc_comp[6];

    wire rd_is_single_err = rd_syndrome[6] && (rd_syndrome[5:0] != 6'd0);
    wire rd_is_double_err = (!rd_syndrome[6]) && (rd_syndrome[5:0] != 6'd0);

    wire [31:0] rd_corr_mask     = syndrome_to_correction_mask(rd_syndrome[5:0]);
    wire [31:0] rd_data_corrected = rd_data ^ rd_corr_mask;

    // =========================================================================
    // Write data merge (for partial byte writes with SECDED)
    //
    // Partial byte writes require read-modify-write of the full 32-bit word.
    // We use the corrected read data for unmodified bytes, wdata_i for
    // modified bytes, then recompute ECC across the merged word.
    // Full-word writes (we=0xF) use wdata_i directly.
    // =========================================================================
    wire [31:0] wr_merged_data;
    assign wr_merged_data[7:0]   = we_i[0] ? wdata_i[7:0]   : rd_data_corrected[7:0];
    assign wr_merged_data[15:8]  = we_i[1] ? wdata_i[15:8]  : rd_data_corrected[15:8];
    assign wr_merged_data[23:16] = we_i[2] ? wdata_i[23:16] : rd_data_corrected[23:16];
    assign wr_merged_data[31:24] = we_i[3] ? wdata_i[31:24] : rd_data_corrected[31:24];

    wire [6:0] wr_ecc = hamming_encode(wr_merged_data);

    // =========================================================================
    // Main TCM access (single-cycle read + optional write)
    // =========================================================================
    always @(posedge clk_i) begin
        ack_o <= 1'b0;
        if (req_i) begin
            // Read: return SECDED-corrected data; available next cycle
            rdata_o <= rd_data_corrected;
            ack_o   <= 1'b1;

            // SECDED error flags (latched until next req)
            ecc_err_correct_o <= rd_is_single_err;
            ecc_err_fatal_o   <= rd_is_double_err;

            // Write: per-byte enable with SECDED ECC
            if (|we_i) begin
                mem[word_addr] <= {wr_ecc, wr_merged_data};
            end
        end
    end

    // =========================================================================
    // Scrubber Interface
    //
    // Provides independent access for the background memory scrubber.
    // scr_req_i reads the raw memory entry; scr_we_i writes corrected data.
    // Both are registered operations (1-cycle latency).
    // =========================================================================
    always @(posedge clk_i) begin
        if (scr_req_i) begin
            scr_raw_o <= mem[scr_addr_i];
        end
        if (scr_we_i) begin
            mem[scr_addr_i] <= {scr_ecc_i, scr_wdata_i};
        end
    end

`ifndef SYNTHESIS
    // Initialise memory to zero for simulation
    integer init_i;
    initial begin
        for (init_i = 0; init_i < 2048; init_i = init_i + 1)
            mem[init_i] = 39'd0;
    end
`endif

endmodule
