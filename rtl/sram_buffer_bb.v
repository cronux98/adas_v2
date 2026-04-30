// ============================================================================
// sram_buffer_bb.v — Black-Box Wrapper for Weight SRAM Buffer
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    AI Accelerator — Weight Storage Buffer (Black Box)
// Author:   David Chen, Backend Lead
// Date:     2026-04-29
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
//
// Description:
//   Empty module with exact port list of sram_buffer — used as a
//   synthesis black-box placeholder for P&R.  The synthesizable
//   implementation (sram_buffer.v) contains a 16×39-bit register
//   file with Hamming SECDED ECC, which will be replaced by
//   sky130 SRAM hard macros in the physical design flow.
//
//   This wrapper preserves the module interface for hierarchy
//   resolution during P&R.  ORFS will substitute the real
//   SRAM macro or the fully-synthesized version as needed.
//
// Interfaces:
//   - Write port: AXI register writes to AI_WEIGHT_0..3
//   - Read port:  control_fsm sequential read → systolic_array
//   - AXI read port: combinational weight readback
//   - ECC status/diagnostics: error flags and counters
//
// Port list: exact match to sram_buffer.v
// ============================================================================

`timescale 1ns / 1ps

module sram_buffer (
    input  wire        clk,
    input  wire        rst_n,

    // Write port (from AXI register decode)
    input  wire        wr_en,
    input  wire [3:0]  wr_addr,
    input  wire [31:0] wr_data,

    // Read port (to systolic_array during LOAD_WEIGHTS state)
    input  wire        rd_en,
    input  wire [3:0]  rd_addr,
    output wire [31:0] rd_data,

    // AXI combinational read port (for weight readback)
    input  wire [3:0]  axi_rd_addr,
    output wire [31:0] axi_rd_data,

    // ECC status
    output wire        ecc_err_detect,
    output wire        ecc_err_correct,

    // ECC diagnostic registers
    output wire [3:0]  ecc_last_addr_o,
    output wire [15:0] ecc_correct_cnt_o,
    output wire [15:0] ecc_fatal_cnt_o
);

    // Black-box: no implementation.  Outputs are left floating;
    // Yosys/ORFS will treat this as a hard macro during P&R.

endmodule
