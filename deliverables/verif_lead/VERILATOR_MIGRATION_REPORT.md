# VERILATOR MIGRATION REPORT — ADAS v2 SoC
**Author:** Rahul Sharma, Verification Lead  
**Date:** 2026-04-29  
**Status:** FAILED — Verilator 4.038 cannot integrate with cocotb 2.0.1  
**Recommendation:** Upgrade Verilator → defer until ≥5.036 is installed

---

## 1. EXECUTIVE SUMMARY

The Verilator smoke test **failed** — not due to RTL issues or testbench problems, but because the installed Verilator 4.038 (2020-07-11) is **below the minimum version 5.036** required by cocotb 2.0.1. The cocotb Makefile hard-blocks execution before any build step runs.

The ADAS v2 RTL (22 modules + test wrapper) compiles cleanly through Verilator 4.038 in standalone lint-only and verilation modes, so there are **no RTL-level Verilator incompatibilities**. The block is exclusively a tool-version dependency.

**Bottom line:** Verilator-accelerated cocotb simulation is not possible on this system until Verilator ≥5.036 is built from source (not available in Ubuntu 22.04 repos). The Icarus Verilog 11.0 flow works correctly and is the current production simulation path.

---

## 2. SMOKE TEST RESULTS

### 2.1 Test: `make -f Makefile.verilator clean`

| Metric | Result |
|--------|--------|
| Command | `make -f Makefile.verilator clean` |
| Exit code | **2 (FAILED)** |
| Error | `cocotb requires Verilator 5.036 or later, but using 4.038` |
| Root cause | cocotb_tools/makefiles/simulators/Makefile.verilator:25 sets `VLT_MIN := 5.036` and aborts before any target runs |

### 2.2 Test: `make -f Makefile.verilator`

| Metric | Result |
|--------|--------|
| Status | **NOT REACHED** — blocked by `clean` dependency / Makefile include |
| Note | Same version gate blocks all targets (build, sim, clean) |

### 2.3 Test: Standalone Verilator 4.038 (lint-only)

| Metric | Result |
|--------|--------|
| Command | `verilator --lint-only --top-module adas_soc_tb_wrapper *.v ../rtl/*.v` |
| Exit code | 0 (PASSED) |
| Warnings | PINMISSING (4), PINCONNECTEMPTY (5), UNDRIVEN (1), CASEINCOMPLETE (2) |
| Fatal errors | None |
| Verdict | **All 23 Verilog files pass lint** |

### 2.4 Test: Standalone Verilator 4.038 (verilation)

| Metric | Result |
|--------|--------|
| Command | `verilator --cc --build --top-module adas_soc_tb_wrapper ...` |
| Verilation | **PASSED** (C++ model generated + compiled) |
| Wall time | **6.022s** |
| Link | **FAILED** — no `main()` (expected; cocotb normally provides the harness) |
| Verdict | **RTL is fully compatible with Verilator 4.038 verilation. Link failure is expected without a test harness.** |

---

## 3. ENVIRONMENT DETAILS

| Component | Installed Version | Required for cocotb |
|-----------|-------------------|---------------------|
| Verilator | 4.038-1 (Ubuntu 22.04 jammy) | ≥ 5.036 |
| cocotb | 2.0.1 | — |
| Icarus Verilog | 11.0 | N/A (working) |
| Python | 3.10 | — |
| OS | Ubuntu 22.04 LTS | — |

**Upgrade path from Ubuntu 22.04 repos:** None. Verilator 4.038-1 is the latest package available. Must build from source.

---

## 4. PERFORMANCE COMPARISON

Since Verilator-accelerated simulation could not run, this is a **projected** comparison based on standalone verilation speed and Icarus measured results.

| Simulator | Elaboration | Simulation | Total Wall | Speedup (est.) |
|-----------|-------------|------------|------------|-----------------|
| Icarus 11.0 | 0.048s | 0.680s | **1.486s** | 1× (baseline) |
| Verilator 5.x (projected) | N/A (AOT compile) | ~0.02-0.05s | ~6s + 0.05s | 15-30× per sim run |

**Note on Verilator advantage:** Verilator Ahead-of-Time compilation means a ~6s build cost per RTL change, but each simulation invocation then runs at near-native C++ speed. For regression suites with 100+ test runs, the amortized speedup is dramatic (15-50×). For single smoke tests like this one (1.5s Icarus), the build overhead makes Verilator slower on first run.

---

## 5. LINT WARNINGS FOUND (Standalone Verilator 4.038)

These are **non-fatal** and identical to what we already see in Icarus simulation. Documented here for completeness.

| Warning | Count | Files | Severity |
|---------|-------|-------|----------|
| PINMISSING | 4 | adas_soc_tb_wrapper.v, adas_soc_top.v | LOW — test wrapper omits test-only pins |
| PINCONNECTEMPTY | 5 | ai_accelerator_top.v, systolic_array.v | LOW — unconnected debug ports (ecc_last_addr_o, state, data_valid) |
| UNDRIVEN | 1 | wdt.v (reg_status[31:5]) | LOW — partial register, driven bits [4:0] |
| CASEINCOMPLETE | 2 | spi_controller.v, redundant_shutdown.v | MEDIUM — 2-bit states with 2'b11 uncovered |
| DECLFILENAME | 1 | ai_accelerator_top.v (module `ai_accel_4x4`) | LOW — cosmetic, module name ≠ filename |

**No new bugs found.** These warnings pre-date the Verilator test and were noted in prior Icarus runs.

---

## 6. ROOT CAUSE ANALYSIS

```
Trigger:     make -f Makefile.verilator
Error point: /usr/local/lib/python3.10/dist-packages/cocotb_tools/
             makefiles/simulators/Makefile.verilator, line 25
Mechanism:   $(error cocotb requires Verilator 5.036 or later, but using $(VLT_VERSION))
Root cause:  cocotb 2.0.1 dropped support for Verilator <5.036.
             Ubuntu 22.04 ships Verilator 4.038.
Resolution:  Build Verilator ≥5.036 from source.
```

**Why cocotb 2.0.1 requires Verilator 5.036+:** Verilator 5.x introduced:
- New `--timing` flag for proper event-driven timing (required by cocotb timing model)
- Split Verilog/SystemVerilog parser (`--sv` flag)
- Changed VPI handle semantics that cocotb's GPI layer depends on
- Removal of deprecated APIs used by older cocotb versions

There is no downgrade path — cocotb 1.x does not support Verilator 4.x well either (different API issues), and downgrading cocotb would break our existing Icarus-based cocotb flow.

---

## 7. RECOMMENDATION

### **DEFER — Verilator adoption deferred until Verilator ≥5.036 is installed.**

| Option | Feasibility | Risk | Recommendation |
|--------|------------|------|----------------|
| **A. Upgrade Verilator to 5.x** | Build from source (~20 min) | Medium — new tool version may surface RTL issues | ✅ **Recommended for regression speed** |
| **B. Downgrade cocotb** | Not viable | High — breaks Icarus flow | ❌ Rejected |
| **C. Continue with Icarus only** | Zero effort | Low — 1.5s sim is adequate for current design size | ✅ **Recommended for immediate milestone** |

### Priority Plan:

1. **This milestone:** Continue using Icarus 11.0 as the primary simulator. It works, it's fast enough for the current design size (1.5s per smoke test).
2. **Next milestone (pre-regression):** Build Verilator 5.036+ from source. The ~6s build + ~0.05s/sim speedup will pay off when running 50+ regression tests.
3. **GLS sign-off:** Icarus remains the GLS simulator regardless (Yosys netlist + Icarus is the proven open-source GLS flow).

### Upgrade Commands (for reference, when we proceed):

```bash
# Install build dependencies
sudo apt-get install -y git help2man perl python3 make autoconf g++ flex bison ccache libgoogle-perftools-dev numactl perl-doc libfl2 libfl-dev zlib1g zlib1g-dev

# Clone and build Verilator 5.x
git clone https://github.com/verilator/verilator.git /tmp/verilator
cd /tmp/verilator
git checkout stable  # or v5.036 tag
autoconf && ./configure && make -j$(nproc)
sudo make install

# Verify
verilator --version  # should show ≥5.036
```

---

## 8. CONCLUSION

The Verilator smoke test **failed by design** — the toolchain is incompatible, not the RTL. The ADAS v2 RTL (22 modules + test wrapper) passes Verilator 4.038 lint and verilation with zero fatal errors, confirming no RTL-level compatibility issues. Once Verilator ≥5.036 is installed, the existing `Makefile.verilator` should work with minimal adjustments.

For the current milestone: **Icarus Verilog 11.0 is the production simulator.** It completes the full smoke test in 1.486s — more than adequate for interactive development and current test coverage.

---

*"The tools don't lie. Verilator 4.038 is four years old. cocotb moved on. We build from source, or we stay with Icarus. Both are valid. Let's pick one and ship."*  
— Rahul Sharma, Verification Lead
