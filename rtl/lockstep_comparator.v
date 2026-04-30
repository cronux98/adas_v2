// ============================================================================
// lockstep_comparator.v - Dual-Core Lockstep Comparator (ASIL-D)
// ============================================================================
// Project:  adas_v2 - ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    Cycle-by-cycle dual-core lockstep comparator
// Author:   Mei-Lin Chang, Digital Design Engineer
// Date:     2026-04-29  (rewritten for dual-core lockstep per ARCH-AD-001)
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz
//
// Architecture (ARCH-AD-001 §5.6):
//   Compares two independent RV32IM core outputs cycle-by-cycle.
//   Master core outputs (already delay-compensated by dual_lockstep_top)
//   are XOR-compared against checker core outputs.
//   On mismatch: assert lockstep_mismatch_o, increment mismatch counter.
//
//   The delay pipeline from v1 (time-diversity self-comparison) has been
//   removed. The dual_lockstep_top wrapper handles all time-stagger management.
//   This comparator is now a simple dual-input XOR comparison with mask.
//
// Inputs:
//   master_outputs_i[31:0]  - Core A outputs (delay-compensated by wrapper)
//   master_pc_i[31:0]       - Core A program counter
//   master_valid_i          - Core A valid strobe
//   checker_outputs_i[31:0] - Core B outputs (direct)
//   checker_pc_i[31:0]      - Core B program counter
//   checker_valid_i         - Core B valid strobe
//   enable_i                - Comparator enable (from safety ctrl)
//   mask_i[31:0]            - Configurable signal mask (0=ignore, 1=compare)
//   threshold_i[3:0]        - Consecutive mismatch threshold (0=any)
//   self_test_i             - Self-test: inverts LSB of master lane for 1 cycle
//
// Outputs:
//   mismatch_o              - Mismatch detected (pulse, 1 cycle)
//   mismatch_pc_o[31:0]     - PC at mismatch
//   mismatch_count_o[31:0]  - Cumulative mismatch counter (saturating)
//   master_output_o[31:0]   - Master output at last mismatch (diagnostic)
//   checker_output_o[31:0]  - Checker output at last mismatch (diagnostic)
//
// Reference: SafeLS — Lockstep NOEL-V Core, arXiv:2307.15436
//            Trikarenos — Gate-Level Fault Injection, arXiv:2407.05938
//            ARCH-AD-001 lockstep_architecture_decision.md §5.6
// ============================================================================

`timescale 1ns / 1ps

module lockstep_comparator (
    input  wire        clk_i,
    input  wire        rst_n_i,

    // Master core outputs (already delay-compensated by dual_lockstep_top)
    input  wire [31:0] master_outputs_i,
    input  wire [31:0] master_pc_i,
    input  wire        master_valid_i,

    // Checker core outputs (direct - naturally time-aligned with master)
    input  wire [31:0] checker_outputs_i,
    input  wire [31:0] checker_pc_i,
    input  wire        checker_valid_i,

    // Configuration (from safety control registers)
    input  wire        enable_i,           // Comparator enable
    input  wire [31:0] mask_i,             // Bit mask (0=ignore, 1=compare)
    input  wire [3:0]  threshold_i,        // Consecutive mismatch threshold
    input  wire        self_test_i,        // Self-test: inject known mismatch

    // Outputs
    output reg         mismatch_o,         // Mismatch pulse (1 cycle)
    output reg  [31:0] mismatch_pc_o,      // PC at mismatch
    output reg  [31:0] mismatch_count_o,   // Cumulative mismatch counter
    output reg  [31:0] master_output_o,    // Master output at mismatch
    output reg  [31:0] checker_output_o    // Checker output at mismatch
);

    // =========================================================================
    // Comparator Logic
    // =========================================================================
    // Both cores should produce identical outputs every valid cycle.
    // The mask_i register allows firmware to ignore specific bits that
    // may legitimately differ (e.g., cycle counters, performance monitors).
    //
    // Comparison: (master_outputs & mask) vs (checker_outputs & mask)
    // Valid comparison requires: enable, both valid, and same cycle.

    wire [31:0] master_masked;
    wire [31:0] checker_masked;
    wire        cycle_mismatch;

    // Self-test: when self_test_i=1, invert bit 0 of master_masked to force
    // a deliberate mismatch. This validates the comparator's XOR tree is not
    // stuck-at-0 (single point of failure per Trikarenos arXiv:2407.05938).
    // The mismatch propagates through the normal pipeline so firmware can
    // read MISMATCH_COUNT to verify the comparator is working.
    wire [31:0] master_masked_selftest;
    assign master_masked_selftest = master_outputs_i & mask_i;
    assign master_masked  = self_test_i ? {master_masked_selftest[31:1], ~master_masked_selftest[0]} : master_masked_selftest;
    assign checker_masked = checker_outputs_i & mask_i;

    // Mismatch detection: both cores must be valid AND produce different
    // masked outputs in the same cycle.
    assign cycle_mismatch = enable_i && master_valid_i && checker_valid_i &&
                            (master_masked != checker_masked);

    // =========================================================================
    // Consecutive Mismatch Counter (Threshold Filter)
    // =========================================================================
    // A single-cycle mismatch may be a glitch; the threshold register
    // requires consecutive mismatches before asserting mismatch_o.
    // threshold_i = 0: assert immediately on first mismatch.
    // threshold_i = N: assert after N+1 consecutive mismatches.

    reg [3:0] consecutive_mismatch_cnt;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            consecutive_mismatch_cnt <= 4'd0;
        end else begin
            if (cycle_mismatch) begin
                if (consecutive_mismatch_cnt < threshold_i)
                    consecutive_mismatch_cnt <= consecutive_mismatch_cnt + 4'd1;
                // else: held at threshold+1 until we fire mismatch
            end else begin
                consecutive_mismatch_cnt <= 4'd0;  // reset on non-mismatch
            end
        end
    end

    // =========================================================================
    // Mismatch Output Generation
    // =========================================================================
    // mismatch_o is a single-cycle pulse.
    // mismatch_count_o is cumulative, saturating at 0xFFFFFFFF.
    // Diagnostic registers capture the state at the moment of mismatch.

    wire mismatch_fire;

    assign mismatch_fire = enable_i && master_valid_i && checker_valid_i &&
                           (consecutive_mismatch_cnt >= threshold_i) &&
                           (master_masked != checker_masked);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            mismatch_o        <= 1'b0;
            mismatch_pc_o     <= 32'd0;
            mismatch_count_o  <= 32'd0;
            master_output_o   <= 32'd0;
            checker_output_o  <= 32'd0;
        end else begin
            mismatch_o <= 1'b0;  // auto-clear (pulse)

            if (mismatch_fire) begin
                mismatch_o <= 1'b1;
                mismatch_pc_o <= master_pc_i;  // PC from master at mismatch

                // Saturating counter
                if (mismatch_count_o != 32'hFFFF_FFFF)
                    mismatch_count_o <= mismatch_count_o + 32'd1;

                // Diagnostic capture
                master_output_o  <= master_masked;
                checker_output_o <= checker_masked;
            end
        end
    end

`ifndef SYNTHESIS
    // ---------------------------------------------------------------------
    // Simulation assertions
    // ---------------------------------------------------------------------

    // Assertion: When both cores are valid and enabled, masked outputs
    // should be identical. Any difference is a lockstep violation.
    //
    // This is checked WITH the threshold filter - the assertion fires
    // after the threshold is reached, same as the hardware mismatch_o.
    always @(posedge clk_i) begin
        if (mismatch_fire) begin
            $display("[LOCKSTEP] MISMATCH DETECTED at PC=%08h: master=%08h checker=%08h mask=%08h",
                     master_pc_i, master_masked, checker_masked, mask_i);
        end
    end

    // Coverage: track how often both cores are valid simultaneously
    // (indication that lockstep is operating correctly)
    reg [31:0] lockstep_sync_count;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            lockstep_sync_count <= 32'd0;
        else if (enable_i && master_valid_i && checker_valid_i)
            lockstep_sync_count <= lockstep_sync_count + 32'd1;
    end
`endif

endmodule
