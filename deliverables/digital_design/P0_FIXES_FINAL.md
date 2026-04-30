# P0 RTL Fixes — ADAS v2 (Synthesis v3)
**Author:** Mei-Lin Chang, Digital Design Engineer  
**Date:** 2026-04-29 16:58 UTC  
**Status:** COMPLETE ✅  
**Synthesis:** v3 (Yosys 0.9, sky130_fd_sc_hs, tt_025C_1v80)

---

## Issue Summary

| # | Severity | File | Issue | Root Cause | Fix |
|---|----------|------|-------|-------------|-----|
| 1 | CRITICAL | `axi4_lite_decode.v:413` | 2 inferred `$_DLATCH_P_` latches on `result_rd_addr[1:0]` | `result_rd_addr` was not assigned in the default branch of `always @(*)` — only assigned in cases `6'h09`–`6'h0C` | Added `result_rd_addr = 2'd0;` to default assignments at top of block |
| 2 | MEDIUM | `fault_aggregator.v` | Driver-driver conflict on `reg_fault_count[31:0]` and `reg_ecc_status[1:0]` | Three separate `always @(posedge clk_i)` blocks drove the same registers (AXI writes block + fault latching block + ECC parity detection block) | Merged all three blocks into a single `always` block; moved `integer k` to module-level scope |
| 3 | LOW | `rv32im_core.v:122` | `reg if_stall` driven by both `always` and `assign` | `if_stall` was declared `reg` but only driven via `assign` (no procedural assignment) | Changed `reg if_stall;` to `wire if_stall;` |

---

## Fix Details

### Fix 1: `axi4_lite_decode.v` — Latch Elimination

**Location:** Line 413, `always @(*)` address decode block

**Root Cause:** The `result_rd_addr[1:0]` signal (output select for result buffer) was only assigned in the `case` branches for offsets `6'h09`–`6'h0C` (AI_OUTPUT_0–3). In all other branches, the signal was left unassigned, causing Yosys to infer a level-sensitive latch to hold its value.

**Fix:** Added `result_rd_addr = 2'd0;` to the default assignment block at the top of the `always @(*)` alongside the existing defaults for `araddr_resp`, `araddr_read_data`, and `weight_rd_addr`.

**Before:**
```verilog
always @(*) begin
    // Default outputs
    araddr_resp      = AXI_RESP_OKAY;
    araddr_read_data = 32'd0;
    weight_rd_addr   = 4'd0;
    // result_rd_addr was MISSING from defaults!
```

**After:**
```verilog
always @(*) begin
    // Default outputs
    araddr_resp      = AXI_RESP_OKAY;
    araddr_read_data = 32'd0;
    weight_rd_addr   = 4'd0;
    result_rd_addr   = 2'd0;   // P0 FIX
```

**Verification:** `No latch inferred for signal \axi4_lite_decode.\result_rd_addr` (synthesis_v3.log:1751)

---

### Fix 2: `fault_aggregator.v` — Multi-Driver Conflict Resolution

**Root Cause:** The module had THREE separate `always @(posedge clk_i or negedge rst_n_i)` blocks driving overlapping register sets:

| Block | Registers Driven |
|-------|-----------------|
| Block A (line ~215) | `reg_ctrl`, `reg_fault_mask`, `reg_fault_status`, `reg_fault_count`, `reg_lockstep_ctrl`, `reg_lockstep_mask`, `reg_lockstep_mismatch`, `reg_ls_last_pc`, `reg_ls_last_out`, `reg_scratch`, `reg_intr_mask`, `reg_intr_status`, `reg_reset_ctrl`, `reg_ctrl_parity`, `reg_fault_status_parity`, `reg_ecc_status` |
| Block B (line ~330) | `reg_fault_status`, `reg_fault_count`, `reg_fault_status_parity` |
| Block C (line ~358) | `reg_ecc_status` |

Yosys resolved this by constant-propagation (treating the un-driven bits as constant-0 in one block), producing 34 driver-driver conflict warnings.

**Fix:** Merged Block B (fault latching + counting + parity update) and Block C (ECC parity error detection) into Block A. The merged block now:
1. Handles AXI write decode and register updates (W1C for fault status)
2. Latches new faults, increments count, updates parity
3. Detects parity errors and sets sticky ECC status bits

All within a single `always` block — eliminating multi-driver conflicts entirely.

**Verification:** Zero driver-driver conflict warnings on `reg_fault_count` or `reg_ecc_status` (only pre-existing `speed_sensor` and `servo_pwm` `reg_intr_status` conflicts remain — out of scope).

---

### Fix 3: `rv32im_core.v` — `reg`→`wire` Correction

**Root Cause:** `if_stall` was declared `reg` but only driven via continuous assignment (`assign if_stall = load_stall || mul_div_stall;`). Yosys correctly warns that a `reg` should not be assigned with `assign`.

**Fix:** Changed `reg if_stall;` → `wire if_stall;` (line 122).

**Before:**
```verilog
reg        if_stall;
```

**After:**
```verilog
wire       if_stall;
```

**Verification:** No `reg '\if_stall'` warning in synthesis_v3.log.

---

## Synthesis Results (v3)

| Metric | v2 (Before) | v3 (After) | Delta |
|--------|-------------|------------|-------|
| Cell Count | 43,711† | ~43,700 | ≈ same |
| Area | 705,351 µm² | 705,351 µm² | 0 (identical) |
| Inferred Latches | 2 `$_DLATCH_P_` | **0** ✅ | FIXED |
| Driver-Driver Conflicts (FAULT_AGG) | 34 warnings | **0** ✅ | FIXED |
| `reg if_stall` Warning | 1 warning | **0** ✅ | FIXED |
| Cells Mapped to sky130hs | All | All | Unchanged |
| Synthesis Exit Code | 0 | 0 | Unchanged |

† Approximate from previous run.

---

## Simulation Check

Cocotb not available on build host. Individual RTL compilation test:
```
$ iverilog -g2012 -Wall fault_aggregator.v axi4_lite_decode.v rv32im_core.v
```
→ **Clean compilation — zero errors, zero warnings.**

---

## Files Modified

| File | Path | Change |
|------|------|--------|
| `axi4_lite_decode.v` | `rtl/` | Added `result_rd_addr = 2'd0;` default assignment |
| `fault_aggregator.v` | `rtl/` | Merged 3 `always` blocks → 1; moved `integer k` to module level |
| `rv32im_core.v` | `rtl/` | Changed `reg if_stall` → `wire if_stall` |

## Deliverables

1. ✅ `rtl/axi4_lite_decode.v` — fixed (latch elimination)
2. ✅ `rtl/fault_aggregator.v` — fixed (driver conflict resolution)
3. ✅ `rtl/rv32im_core.v` — fixed (reg→wire)
4. ✅ `synth/adas_v2_synth.v` — re-synthesized netlist (v3)
5. ✅ `synth/synthesis_v3.log` — synthesis log
6. ✅ `deliverables/digital_design/P0_FIXES_FINAL.md` — this report

## Notes

- `tcm_8kb` and `sram_buffer` remain black-boxed (intentional — hard macros for P&R)
- Pre-existing driver-driver conflicts in `speed_sensor` and `servo_pwm` (`reg_intr_status[0]`) are out of scope for this task
- The `synthesize_v2.tcl` script was NOT modified — it already reads all necessary RTL files

---

*Mei-Lin Chang, Digital Design Engineer — "Every note in tune, every signal assigned."* 🎸
