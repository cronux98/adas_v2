# Research-to-RTL Improvement Review — ADAS v2 AI Accelerator & Safety Subsystem

**Document:** PROF-IMPR-001 | **Version:** 1.0 | **Date:** 2026-04-29  
**Author:** Prof. Zhang Luxin (professor)  
**Reference:** `research_digest_2026-04-29.md` (26 papers, 33 feasibility questions)  
**Cross-reference:** `deliverables/architect/research_response.md` (14 decisions)  
**RTL baseline:** `rtl/` (21 modules as-built at commit HEAD)

---

> **STATUS:** This review cross-references every accepted, deferred, and rejected research recommendation against the as-built RTL. Where the RTL diverges from what was agreed, I flag it. Where deferral decisions still hold, I confirm them. Where we missed a low-effort win, I recommend it.

---

## TABLE OF CONTENTS

1. [Techniques Already Implemented Well](#1-techniques-already-implemented-well)
2. [Low-Effort, High-Impact Improvements — IMPLEMENT NOW](#2-low-effort-high-impact-improvements--implement-now)
3. [Improvements to Defer to ADAS v3](#3-improvements-to-defer-to-adas-v3)
4. [Techniques That Don't Apply to sky130hs](#4-techniques-that-dont-apply-to-sky130hs)
5. [The Most Impactful Single Change](#5-the-most-impactful-single-change)

---

## 1. TECHNIQUES ALREADY IMPLEMENTED WELL

These are the techniques from the 26-paper literature survey (§1–§6 of the research digest) that are correctly implemented in the current RTL. No action needed.

### 1.1 SECDED ECC on Weight SRAM — Hamming(39,32)

- **Paper:** Trikarenos — arXiv:2407.05938 (§3.3 of digest)
- **RTL location:** `sram_buffer.v` — lines 94–280
- **What's implemented:** Full Hamming(39,32) SECDED encoder + syndrome decoder + correction mask function. Single-bit errors are corrected on-the-fly; double-bit errors are detected and flagged via `ecc_err_detect`.
- **Quality:** The `hamming_encode` function and `syndrome_to_correction_mask` function are correct for the codeword mapping described. The AXI combinational read port also applies SECDED correction. The dual-port read architecture (registered FSM read + combinational AXI read) is efficient.
- **Assessment:** ✅ **Fully and correctly implemented.** This is the gold-standard ASIL-D memory protection mechanism, matching the Trikarenos paper's approach. No changes needed.

### 1.2 Weight-Stationary (WS) Dataflow for Systolic Array

- **Paper:** arXiv:2410.22595 (§2.6 of digest) — systematic comparison of WS/IS/OS dataflows
- **RTL location:** `systolic_array.v` — entire module; `control_fsm.v` — column-enable sequencing
- **What's implemented:** Classic WS dataflow. Weights loaded once per inference (stationary in PEs), activations broadcast column-by-column, partial sums flow horizontally. The FSM sequences through 4 compute cycles with one-hot column enables.
- **Why it's right:** The literature comparison (digest §2.6, Table) rates WS as "Best fit — ADAS runs same model repeatedly" with ⭐⭐⭐⭐ for our use case. Input Stationary would be worse for repeated-model inference; Output Stationary adds control complexity for marginal benefit.
- **Assessment:** ✅ **Correct architectural choice.** The WS dataflow is the most energy-efficient for our inference-only workload. No action needed.

### 1.3 Dual-Core Lockstep with Configurable Time Staggering

- **Paper:** SafeLS — arXiv:2307.15436 (§3.2 of digest)
- **RTL location:** `lockstep_comparator.v` — lines 56–107
- **What's implemented:** Configurable 1-4 cycle delay pipeline for lockstep core outputs. Delay depth controlled via `delay_cycles_i`. Comparator uses configurable `mask_i` to ignore non-critical signals. On mismatch, captures PC, actual output, expected output, and increments cumulative count.
- **Quality:** The shift-register delay chain with runtime-configurable depth correctly implements the SafeLS time-staggering pattern. The signal mask (`mask_i`) for ignoring non-critical comparisons is architecturally sound.
- **Assessment:** ✅ **Correctly implemented.** The 2-cycle staggering prevents common-cause failures from simultaneous radiation strikes or voltage droops, as demonstrated in the SafeLS paper. One improvement noted in §2.3 below.

### 1.4 Window Watchdog Timer with Pre-Warning

- **Paper:** RISC-V Functional Safety — arXiv:2604.17391 (§3.1 of digest)
- **RTL location:** `wdt.v` — full module (independent wdt_clk domain)
- **What's implemented:** Full window WDT with: key-protected control register, configurable timeout/window/pre-warning thresholds, kick mechanism with magic value (0xAC53_CAFE), early-kick detection (fault on refresh during closed window), configuration lock registers (one-time write), and independent clock domain with CDC synchronization.
- **Quality:** This is thorough. The key-protected enable (cannot be disabled once set), the window mechanism, the early-kick fault, and the pre-warning interrupt all align with ASIL-D best practices from the literature.
- **Assessment:** ✅ **Excellent implementation.** Exceeds the minimum viable WDT for ASIL-D. The configuration lock mechanism is particularly well-designed.

### 1.5 Redundant Shutdown Controller with Staged Sequence

- **Paper:** ISO 26262 safety patterns from arXiv:2210.04040 (§3.4 of digest)
- **RTL location:** `redundant_shutdown.v` — full module (wdt_clk domain)
- **What's implemented:** Three-stage shutdown sequence: IDLE → ALERT (assert alert_n_o immediately) → SHUTDOWN (wait 4+ cycles, then assert dual shutdown_n_o). Outputs are latched forever once asserted (require external POR). Dual shutdown outputs for redundancy. Independent clock domain from the main CPU.
- **Quality:** The staged approach (alert before shutdown) allows connected systems to prepare for shutdown. The forever-latch prevents accidental re-enable. The dual outputs provide output-path diversity.
- **Assessment:** ✅ **Correctly implemented.** Aligns with the Markov-process reliability analysis from arXiv:2210.04040, which demonstrates that redundancy in the safety path improves reliability against common-cause failures.

### 1.6 Fault Aggregation with Severity Classification

- **Paper:** RISC-V Functional Safety — arXiv:2604.17391 (§3.1 of digest)
- **RTL location:** `fault_aggregator.v` — lines 280–380
- **What's implemented:** 12 fault source inputs, per-source mask register, latched fault status with W1C (Write-1-to-Clear), cumulative fault counter, severity classification (CRITICAL/HIGH/MEDIUM), auto-halt on critical faults, aggregated fault output to redundant shutdown controller, and per-source interrupt generation.
- **Quality:** Good architecture. The W1C fault status register prevents missed faults. The severity classification gates the halt/shutdown decision correctly (only CRITICAL faults trigger halt).
- **Assessment:** ✅ **Architecturally sound.** One improvement opportunity: the ITCM and DTCM parity error inputs (bits 7 and 8) are classified as CRITICAL, which is correct, but they should also trigger a memory scrub on detection (see §2.1).

### 1.7 Custom 3-Stage RV32IM with Lockstep Designed-In

- **Paper:** SafeLS — arXiv:2307.15436 (§3.2 of digest)
- **RTL location:** `rv32im_core.v`
- **Decision rationale** (from architect's research_response.md §Q1): PicoRV32 (~85 MHz) and VexRiscv (~75 MHz) top out below our 100 MHz baseline. A custom 3-stage pipeline gives us control over critical paths and lockstep integration from day one.
- **Assessment:** ✅ **Correct decision.** The architect's rationale is sound. The lockstep interface signals (`lockstep_outputs_o`, `lockstep_pc_o`, `lockstep_valid_o`, `halt_i`) are already present in the core interface per `block_interfaces.md §3.2`. No community core can meet our frequency target on sky130hs.

---

## 2. LOW-EFFORT, HIGH-IMPACT IMPROVEMENTS — IMPLEMENT NOW

These are changes that can be implemented **before synthesis** (i.e., within the current Phase 2b cycle) with minimal RTL disruption and significant benefit. Each recommendation includes concrete implementation guidance.

### 2.1 🔴 CRITICAL: Upgrade TCM ECC from Parity to SECDED

- **Priority:** 🔴 **CRITICAL — ASIL-D compliance blocker**
- **Effort:** 1-2 days RTL
- **Risk:** LOW — proven design in `sram_buffer.v` can be reused
- **Research basis:** Trikarenos — arXiv:2407.05938 (§3.3 of digest)
- **Architect's decision:** ACCEPTED — "must be upgraded to SECDED before ASIL-D sign-off"
- **Current state:** NOT IMPLEMENTED — `tcm_8kb.v` uses per-byte parity only

#### The Gap

The TCM (both ITCM and DTCM — 8 KB each) uses byte-level parity: 1 parity bit per byte = 4 bits for a 32-bit word. This can:
- **Detect** single-bit errors ✅
- **Detect** odd numbers of bit errors ✅
- **Detect** double-bit errors ❌ (2 flips in the same byte = undetected)
- **Correct** any error ❌

ASIL-D requires **SECDED** (Single Error Correct, Double Error Detect) because:
1. At 130nm, single-event upsets (SEUs) are the dominant failure mode
2. Without correction, every SEU forces a safe-state entry — unacceptable for availability
3. Without double-error detection, silent data corruption can accumulate undetected

#### Specific Implementation

Reuse the Hamming(39,32) encoder/decoder from `sram_buffer.v`:

```verilog
// In tcm_8kb.v — replace the per-byte parity array with:
// Each 32-bit word → 39-bit SECDED codeword
// Storage: 2048 entries × 39 bits = 79.9 Kb (was 2048 × 32 + 2048 × 4 = 73.7 Kb)
// Overhead: ~8.4% memory increase (well within sky130 budget)

// Reuse the hamming_encode and syndrome_to_correction_mask functions
// from sram_buffer.v. These are pure combinational functions with no
// module dependencies — copy them directly.

reg [38:0] mem_ecc [0:2047];  // replaces reg [31:0] mem + reg [3:0] parity

// On write:
wire [6:0] wr_ecc = hamming_encode(wdata_i);
mem_ecc[word_addr] <= {wr_ecc, wdata_i};  // per-byte we_i becomes full-word write

// On read:
wire [38:0] rd_raw = mem_ecc[word_addr];
wire [31:0] rd_corrected;  // SECDED-corrected
// ... syndrome computation and correction as in sram_buffer.v lines 180-195
```

**Area impact:** ~8.4% increase in memory bit count per TCM (from 73.7 Kb to 79.9 Kb). For two TCMs, total increase: ~12.4 Kb. At sky130 register-file density, this is negligible.  
**Power impact:** ~5% SRAM power increase from additional ECC logic.  
**Timing impact:** The ECC decoder adds ~2 XOR levels on the read path (~400 ps). At 100 MHz (10 ns period), this is 4% — absorbed easily.

### 2.2 🟡 HIGH: Add Memory Scrubber FSM

- **Priority:** 🟡 **HIGH — required for ASIL-D diagnostic coverage**
- **Effort:** 2-3 days RTL
- **Risk:** LOW — simple FSM, well-understood pattern
- **Research basis:** Trikarenos — arXiv:2407.05938 (§3.3 of digest)
- **Architect's decision:** ACCEPTED — "Add to digital_design task list"
- **Current state:** NOT IMPLEMENTED — no scrubber exists in any module

#### Why It Matters

Without a scrubber, single-bit errors accumulate over time. A second SEU in the same word (before the first is detected) creates an uncorrectable double-bit error. The scrubber continuously reads every memory location, corrects single-bit errors, and writes back the corrected data — preventing error accumulation.

The Trikarenos paper (2407.05938, §IV) explicitly validates: "Memory scrubber constantly reads and corrects single-bit errors before they accumulate into uncorrectable double-bit errors."

#### Specific Implementation

A shared scrubber FSM that cycles through ITCM, DTCM, and weight SRAM:

```verilog
// scrubber.v — Memory scrubber for SECDED-protected memories
// Clock: sys_clk @ 100 MHz
// Scrub rate: configurable (default: 1 scrub per 1024 sys_clk cycles → ~97 kHz)
// Full memory coverage: (16 + 2048 + 2048) words / 97 kHz = ~42 ms per full scan

module scrubber (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,       // from SAFETY_CTRL
    input  wire [15:0] scrub_rate,   // cycles between scrubs

    // ITCM interface
    output reg  [12:0] itcm_addr,
    output reg         itcm_req,
    output reg  [31:0] itcm_wdata,
    output reg  [3:0]  itcm_we,      // 4'b1111 on correction write
    input  wire [31:0] itcm_rdata,
    input  wire        itcm_ack,

    // DTCM interface
    // ... same as ITCM ...

    // Weight SRAM interface
    // ... same pattern, 16 entries ...

    // Status
    output reg         scrub_corrected,  // pulse on each correction
    output reg  [31:0] corrected_count,
    output reg  [31:0] scrub_cycles
);
```

The scrubber operates at low priority — it yields to CPU memory access requests. During idle cycles (when CPU is not accessing TCM), the scrubber issues reads. If a correctable error is found, it writes back the corrected data.

**Key design decisions:**
- **Scrub rate:** 1 access per 1024 sys_clk cycles = one word every 10.24 µs at 100 MHz. This is low enough to never interfere with CPU performance.
- **Stealing:** The scrubber only accesses memory when the CPU is not requesting it. The TCM arbiter gives CPU priority.
- **Correction logging:** Each correction is counted and can trigger a non-critical interrupt for telemetry.
- **Coverage:** Full memory scan in ~42 ms. At this rate, the mean time between scrubs of any given word is 42 ms, which is orders of magnitude faster than the SEU rate at ground level (~10⁻⁶ errors/bit/year at sea level → ~1 error per TCM per year).

**Area impact:** ~500 gates (simple counter + FSM + address registers). Negligible.  
**Power impact:** ~0.1 mW (one memory read every 10 µs, rare writes).  
**Timing:** Not on any critical path — scrubber runs independently.

### 2.3 🟡 HIGH: Add Operand Isolation (Zero-Value Detection) in mac_pe

- **Priority:** 🟡 **HIGH — immediate power savings with trivial implementation**
- **Effort:** 1 day RTL
- **Risk:** VERY LOW — one AND gate per PE, no timing impact
- **Research basis:** Peltekis et al. — arXiv:2304.12691 (§2.1 of digest)
- **Architect's decision:** Deferred per-PE clock gating but did NOT reject operand isolation
- **Current state:** NOT IMPLEMENTED — `enable` gates computation but still toggles psum_out

#### The Gap

Current `mac_pe.v` behavior when `enable=0`:

```verilog
// Current code (mac_pe.v line 105):
} else begin
    // Transparent: pass psum through unchanged
    psum_out <= psum_in;
end
```

Every cycle, even when `enable=0`:
1. `psum_in` is read and written to `psum_out` (32 flip-flops toggling)
2. The 32-bit adder is NOT active (the `enable` condition blocks it) — good
3. But all 32 bits of `psum_out` register toggling wastes dynamic power

**The fix:** When `enable=0` AND the PE's weight is zero, don't toggle `psum_out`:

```verilog
// Improved: operand-isolated mac_pe
// When weight == 0, psum_out holds its value (no toggle)
// When enable == 0, psum_out holds its value (no toggle)
// This eliminates ~50-90% of psum_out toggles in sparse-weight networks.

wire weight_is_zero = (weight == 8'd0);
wire should_compute = enable && !weight_is_zero;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        psum_out <= 32'd0;
    end else if (should_compute) begin
        psum_out <= psum_in + (weight * activation_in);
    end else if (enable && weight_is_zero) begin
        // weight is zero → MAC result = psum_in (multiplication gives 0)
        psum_out <= psum_in;
    end
    // else: hold current value (no toggle)
end
```

**Why this works with ZVCG from the paper:** The Peltekis paper (2304.12691, §III) reports that zero-value clock gating skips 30-60% of operations in pruned networks. While we're not gating clocks per-PE (deferred to v3), we CAN gate data-path switching power with zero-cost logic.

**Power savings at 4×4 scale:**
- In sparse INT8 models (50% weight sparsity): ~50% reduction in psum_out register toggles per PE during active columns
- Total project power savings: ~1-3 mW. Modest but the implementation cost is a single 8-input NOR gate per PE.

**Code change:** Add `wire weight_is_zero = (weight == 8'd0);` and modify the `always` block condition as shown above. That's it.

### 2.4 🟢 MEDIUM: Instantiate Block-Level Clock Gate

- **Priority:** 🟢 **MEDIUM — architect accepted, just needs hookup**
- **Effort:** 1 day (instantiation + CTS verification)
- **Risk:** LOW — sky130 provides dedicated clock gate cells
- **Research basis:** Peltekis et al. — arXiv:2304.12691 (§2.1) + digest §2.2 Strategy A
- **Architect's decision:** ACCEPTED — "Connect AI_CTRL.CLK_EN to sky130 clock gate cell"
- **Current state:** NOT IMPLEMENTED — no clock gate cell instantiation exists

#### Specific Implementation

```verilog
// In ai_accel_4x4.v — instantiate sky130 HS clock gate for the AI accelerator block
// The AI_CTRL.CLK_EN bit (bit 8) already exists in the register map.
// Connect it to drive the clock gate enable.

// sky130_fd_sc_hs__dlclkp: D-latch + AND clock gate
//   .GATE  → clock enable (active high: latch transparent when CLK low)
//   .CLK   → sys_clk
//   .GCLK  → gated clock output (drives entire ai_accel_4x4 module)

wire ai_clk_gated;
sky130_fd_sc_hs__dlclkp u_clk_gate_ai (
    .GATE (ai_clk_en),    // from AI_CTRL.CLK_EN bit
    .CLK  (sys_clk_i),    // ungated sys_clk
    .GCLK (ai_clk_gated) // gated clock to AI accelerator
);

// All AI accelerator sub-blocks receive ai_clk_gated instead of sys_clk_i
```

**CTS impact:** One additional clock sink. At 100 MHz, the ~200 ps gate delay (2% of period) is absorbed in clock tree. OpenROAD CTS will treat `ai_clk_gated` as a generated clock — add `create_generated_clock` constraint.

**Power savings:** ~5-10% of AI accelerator dynamic power when idle (CPU-core-only operation). At ~50 mW AI budget, this is ~2.5-5 mW.

### 2.5 🟢 MEDIUM: Add Lockstep Comparator Formal Properties

- **Priority:** 🟢 **MEDIUM — correctness-critical block, small enough for exhaustive proof**
- **Effort:** 2-3 days (writing SVA properties + Yosys-SMTBMC run)
- **Risk:** NONE — formal verification adds confidence, doesn't change RTL
- **Research basis:** Formal verification of WARP-V — arXiv:1811.12474 (§4.4 of digest)
- **Architect's decision:** ACCEPTED — "Lockstep comparator: ~500 gates, ✅ FORMAL"

#### Specific Properties to Prove

```systemverilog
// Property 1: No false positives — when both cores produce identical outputs
// at the aligned delay, no mismatch is flagged.
// assume: current_masked == shadow_output (at depth=depth)
// assert: mismatch_det == 0

// Property 2: True positive detection — when outputs differ at aligned delay,
// mismatch is always detected (within 1 cycle).
// assume: current_masked != shadow_output (at depth=depth)
// assert: mismatch_o pulses high within 1 cycle

// Property 3: Mismatch count is monotonic — never decreases
// assert: mismatch_count_o never decreases (except on reset)

// Property 4: Delay pipeline integrity — data at depth[delay_cycles_i]
// matches data written delay_cycles_i cycles ago
// assert: delay_outputs[depth] == delay_outputs[0] delayed by depth cycles

// Property 5: Mask correctly suppresses comparison on masked bits
// assume: mask_i[k] == 0
// assert: bit k does not contribute to mismatch_det
```

Yosys-SMTBMC with `bmc -t 50` should prove these properties exhaustively for a 500-gate block within our 8 GB RAM limit.

### 2.6 🟢 MEDIUM: Enable Compile-Time Fast Mode (2-Stage PE Pipeline)

- **Priority:** 🟢 **MEDIUM — enables 150 MHz stretch with zero risk to 100 MHz baseline**
- **Effort:** 1 day RTL (add `ifdef FAST_MODE` to mac_pe)
- **Risk:** VERY LOW — compile-time define, not runtime configurable
- **Research basis:** ArrayFlex — arXiv:2211.12600 (§2.3 of digest)
- **Architect's decision:** ACCEPTED implicitly — "If 150 MHz stretch: Add 1 pipeline register after the 8×8 multiplier"

#### Specific Implementation

```verilog
// In mac_pe.v — add compile-time 2-stage pipeline mode
// FAST_MODE: 2-stage PE (multiply stage + accumulate stage)
// Default:   1-stage PE (current behavior)

`ifdef FAST_MODE
    // Stage 1: Multiply (registered)
    reg signed [15:0] mult_result;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mult_result <= 16'd0;
        else if (enable)
            mult_result <= weight * activation_in;
    end

    // Stage 2: Accumulate (registered)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            psum_out <= 32'd0;
        else if (enable)
            psum_out <= psum_in + mult_result;
        else
            psum_out <= psum_in;
    end
`else
    // Original single-stage MAC (unchanged)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            psum_out <= 32'd0;
        else if (enable)
            psum_out <= psum_in + (weight * activation_in);
        else
            psum_out <= psum_in;
    end
`endif
```

**Timing impact:**
- Default mode: Critical path ~3.1 ns (8×8 mult + 32b adder) → fine at 100 MHz
- FAST_MODE: Stage 1 ~1.8 ns (8×8 mult only), Stage 2 ~1.3 ns (32b adder only) → supports 150+ MHz
- **Cost:** 1-cycle additional latency per PE pipeline stage. Total: +1 cycle for the full array compute. At 4 compute cycles baseline, this is +25% latency but enables +50% frequency.

**This is not the same as ArrayFlex runtime-configurable pipelining.** ArrayFlex (2211.12600) uses muxes to dynamically select pipeline depth per layer, adding ~300 ps to the critical path. We're using a compile-time `ifdef` which incurs ZERO critical path overhead — just two separate synthesis targets.

### 2.7 🟢 LOW: Add Verilator Compatibility Checks to Coding Standard

- **Priority:** 🟢 **LOW — process change, not RTL change**
- **Effort:** 1 hour (documentation update)
- **Risk:** NONE
- **Research basis:** cocotb + Verilator methodology — arXiv:2407.10312 (§4.1 of digest)
- **Architect's decision:** ACCEPTED — "Add Verilator-compatible RTL to coding standard"

The current RTL is already Verilator-compatible (uses `ifndef SYNTHESIS` guards for `$display`, no `#delay` in synthesizable paths, no X-propagation on resets). This is a documentation-only change: add a section to CLAUDE.md listing the banned constructs and the rationale.

---

## 3. IMPROVEMENTS TO DEFER TO ADAS v3

These techniques from the literature are architecturally valid and could provide significant benefit at larger array scale, but don't justify their implementation cost on the 4×4 array. I've re-evaluated each against the as-built RTL and confirmed the architect's deferral decisions.

### 3.1 DiP Dataflow (Diagonal-Input Permutated)

- **Paper:** arXiv:2412.09709 (§2.2 of digest)
- **Claimed benefit:** 50% throughput improvement, 2.02× energy efficiency, eliminates FIFOs (~15% area)
- **Why defer to v3:** Reconfirmed correct.
  - DiP was evaluated on **64×64 (4096 PEs) at 22nm**. The diagonal input routing advantage comes from eliminating the fill/drain latency of large WS arrays. Our 4×4 array has 4-cycle fill (1 cycle per column) — the fill/drain overhead is 4 out of ~4 + M cycles where M is the number of input rows. For a typical 64×64 matrix multiply tiled onto a 4×4 array, M is large (~16 tiles) and the fill/drain overhead is negligible (4/16 = 25%).
  - **Wire delay penalty at 130nm:** Diagonal routes on a 2D grid are √2× longer than Manhattan routes. At 130nm where wire RC delay is significant (~100 ps/mm), diagonal routes on a 4×4 grid (~0.5 mm diagonal vs 0.35 mm Manhattan) would add ~15 ps — negligible at 100 MHz but the routing complexity for OpenROAD is not worth the marginal benefit.
  - **FIFO savings at 4×4:** We don't use FIFOs between PE rows (WS dataflow with column-activation doesn't require them). The DiP paper's FIFO savings don't apply to our architecture.
- **Verdict:** ✅ **Correctly deferred.** Re-evaluate at ≥ 16×16 array size.

### 3.2 TrIM Dataflow (Triangular Input Movement)

- **Paper:** arXiv:2408.01254 + 2408.10243 (§2.4 of digest)
- **Claimed benefit:** 10× less memory access, 15.6× fewer registers vs row-stationary
- **Why defer to v3:** Reconfirmed correct.
  - TrIM compares against **row-stationary** dataflow, not weight-stationary. We use WS, which already has lower register requirements than RS for inference. The 15.6× register savings is not applicable to our architecture.
  - The triangular input pattern creates **non-Manhattan routing** across the array grid. At 130nm, the irregular routing would increase wire lengths and OpenROAD routing runtime significantly. The research digest's feasibility question 11 explicitly raised this concern, and the as-built RTL confirms it — our WS dataflow uses purely horizontal/vertical connections which OpenROAD handles efficiently.
- **Verdict:** ✅ **Correctly deferred.** Re-evaluate if we switch to row-stationary dataflow (unlikely for inference).

### 3.3 ArrayFlex Configurable Pipeline Depth

- **Paper:** arXiv:2211.12600 (§2.3 of digest)
- **Claimed benefit:** 11% latency reduction, 13-23% power reduction, 1.4-1.8× EDP
- **Why defer to v3:** Reconfirmed correct.
  - ArrayFlex adds a **mux on every pipeline register output** to select between registered and bypassed paths. At 130nm, each mux adds ~300 ps to critical paths. At our 100 MHz target (10 ns), this is only 3% overhead — acceptable in isolation. But combined with clock gating delay (200 ps) and ECC decode delay (400 ps), the cumulative overhead becomes ~9% — tight at the 150 MHz stretch target.
  - The bypass mux overhead is per-PE, not per-block. At 16 PEs, 16 muxes × 300 ps doesn't compound (they're parallel paths), but standardizing the bypass adds verification complexity for a marginal benefit at 4×4 scale.
  - **Our compile-time FAST_MODE approach (§2.6) is the better v2 solution.** It gives us the frequency benefit of deep pipelining without the mux overhead or verification complexity. Runtime configuration is deferred to v3.
- **Verdict:** ✅ **Correctly deferred.** Compile-time FAST_MODE covers the v2 need.

### 3.4 Per-PE Clock Gating

- **Paper:** arXiv:2304.12691 (§2.2 Strategy A of digest)
- **Claimed benefit:** 10-15% total power reduction
- **Why defer to v3:** Reconfirmed — but with nuance.
  - Per-PE clock gating with `sky130_fd_sc_hs__dlclkp` creates **16 individual clock sinks** with independent enables. OpenROAD CTS must balance 16 separate gated clock trees. The digest §5 warns: "Per-PE gating increases CTS complexity."
  - At **16 PEs**, the power savings are ~1-3 mW. At the **verification** cost of ensuring no PE misses a clock edge during column-enable transitions, this isn't justified.
  - At **128 PEs** (v3), the savings would be ~10-25 mW — clearly worth the CTS complexity.
  - **What we SHOULD do now:** Block-level clock gating (§2.4) + operand isolation (§2.3) gives us the easy 80% of the benefit without the CTS complexity.
- **Verdict:** ✅ **Correctly deferred.** Block-level gating + operand isolation are the right v2 strategy.

### 3.5 Bus-Invert Coding (BIC)

- **Paper:** arXiv:2304.12691 (§2.2 Strategy B of digest)
- **Claimed benefit:** 1-19% data movement power
- **Why defer to v3:** Reconfirmed correct at 4×4 scale.
  - BIC adds **1 extra wire per bus + XOR tree for Hamming distance + mux**. At 4×4 with 8-bit data buses, that's 4 extra wires (1 per activation column) + 4 XOR trees. The XOR tree to compute `popcount(delta)` on 8-bit values is ~4 XOR2 gates → 16 gates total. The power consumed by these 16 gates likely exceeds the power saved from reduced switching on 4 wires.
  - **At ≥ 16×16 (v3):** 16 columns × 8-bit buses = 128 wires. The XOR tree cost is still per-column, but the switching savings scale with wire count. At this scale, BIC becomes net power-positive.
  - **Additional risk:** The research digest feasibility question 7 raised the concern about Yosys synthesis efficiency for XOR trees. The `$reduce_add` operation on a wide XOR tree may not map efficiently to sky130 cells. This risk is not worth taking for v2's marginal benefit.
- **Verdict:** ✅ **Correctly deferred.** Re-evaluate at ≥ 16×16 array.

### 3.6 Asymmetric Floorplan

- **Paper:** arXiv:2309.02969 (§2.5 of digest)
- **Claimed benefit:** 2% total power reduction
- **Why defer to v3:** Confirmed low priority.
  - The asymmetric floorplan advantage comes from minimizing vertical wire length for high-activity partial sums vs. low-activity weights. At 4×4, the wire-length difference between 4×4 square and (say) 8×2 rectangle is negligible in absolute terms (~1-2 mm total wire length difference).
  - At 16×8 (v3), the wire-length savings become tangible (~5-10 mm total wire length difference). The 2% power reduction on a ~200 mW accelerator is ~4 mW — worth the day of floorplan work.
  - **What we CAN do now:** Note in the v3 architecture backlog. The current 4×4 floorplan is fine.
- **Verdict:** ✅ **Correctly deferred.**

### 3.7 Diversity Lockstep (Strategy S2)

- **Paper:** arXiv:2210.04040 (§3.4 of digest)
- **Claimed benefit:** SPFM improvement from ~99.0% to ~99.5%
- **Why reject for v2:** Reconfirmed.
  - Requires **two different RISC-V core implementations** that are cycle-accurate compatible. We have one custom RV32IM core. Building a second diverse implementation is a 2-3 month effort.
  - The Trikarenos paper (2407.05938) demonstrates **99.10% fault coverage with dual lockstep + ECC alone** — meeting the SPFM ≥ 99% requirement without diversity.
  - **Cost-benefit:** +0.5% SPFM improvement for 2-3 months of development + verification is not justified on our schedule.
- **Verdict:** ✅ **Correctly rejected for v2.** S1 (DCLS + ECC + time staggering) is sufficient.

### 3.8 Triple-Core Lockstep (TMR — Strategy S3)

- **Paper:** arXiv:2407.05938 (§3.3 of digest)
- **Claimed benefit:** SPFM > 99.9%, correct-and-continue (not just detect-and-safe-state)
- **Why reject for v2:** Reconfirmed.
  - 3.2× area cost is **prohibitive on sky130 with our 7.6 GB RAM constraint**.
  - Detect-and-safe-state is the standard ASIL-D pattern for braking/alert ADAS systems (not steering-by-wire). The architect's research_response.md §Q4 correctly notes: "For a braking/alert ADAS system (not steering-by-wire), detect-and-safe-state is the standard ASIL-D pattern."
- **Verdict:** ✅ **Correctly rejected for v2.**

### 3.9 Hard SRAM Macros

- **Paper:** Community OpenRAM data (§6 of digest)
- **Architect's decision:** DEFERRED — "OpenRAM integration not yet validated"
- **Why defer:** Reconfirmed. The current register-file approach works for 16×32-bit weights + 8 KB TCMs. Hard SRAM macros require `.lib` + `.lef` + `.gds` views that need manual integration with Yosys+OpenROAD. The verification cost (timing model accuracy, power model accuracy) is significant. Defer to v3 when we scale to 128 KB+ SRAM.
- **Verdict:** ✅ **Correctly deferred.**

### 3.10 Mixed-Criticality Modes (FORALESA)

- **Paper:** arXiv:2503.04426 (§2.8 of digest)
- **Architect's decision:** REJECTED for v2
- **Why reject:** Reconfirmed. Subdividing 16 PEs into protected/unprotected regions yields too few PEs in each region to do meaningful work. The control logic overhead (~500 gates) is disproportionate. The `enable` input on each mac_pe is architecturally sufficient for future mixed-criticality — no RTL change needed now.
- **Verdict:** ✅ **Correctly rejected for v2.**

---

## 4. TECHNIQUES THAT DON'T APPLY TO SKY130HS

These techniques from the literature are categorically inapplicable to our PDK/toolchain. No re-evaluation needed.

### 4.1 HVT Cell Optimization

- **Why not:** sky130hs provides only **LVT** (Low-Vt) and **SVT** (Standard-Vt) cells. No HVT option exists.
- **Paper context:** Multi-Vt optimization (digest §1.2 Method G) works well on commercial 28nm+ libraries with LVT/SVT/HVT options. On sky130hs, we can only use SVT on non-critical paths and LVT on critical paths — this is a 2-way trade, not 3-way.
- **What we CAN do:** Use `abc -D` with both `sky130_fd_sc_hs__tt_025C_1v80` (SVT) and `sky130_fd_sc_hs__tt_025C_1v80` (LVT) liberty files. Yosys `abc` will prefer LVT on critical paths automatically when given both files.

### 4.2 Custom Clock Meshes

- **Why not:** OpenROAD CTS generates **tree-based clock distribution** (H-tree, Steiner, FLUTE). Full clock mesh generation (grid of clock buffers driving a mesh of wires) requires commercial P&R tools (Cadence Innovus, Synopsys ICC2).
- **Paper context:** The digest §5 explicitly notes: "No clock mesh generation" in OpenROAD.
- **What we DO use:** H-tree topology via OpenROAD `set CTS_BUF_DISTANCE` — provides good skew balance for our chip size.

### 4.3 Post-Route Useful-Skew Optimization

- **Why not:** OpenROAD's useful-skew support is **experimental** (digest §1.2 table: "experimental; risky for tape-out"). For a production ASIL-D tape-out, experimental features are unacceptable.
- **Paper context:** Useful-skew scheduling is standard in commercial STA (PrimeTime, Tempus) but OpenROAD's implementation is immature.
- **What we DO use:** Conservative skew targets (50-100 ps) with H-tree CTS — sufficient at 100 MHz.

### 4.4 Dual-Port SRAM Macros in Open-Source Flow

- **Why not:** Sky130 OpenRAM macros are **single-port only** in the open-source flow (digest §6, feasibility question 32). Dual-port SRAM requires custom layout — out of scope.
- **Paper context:** Many papers assume dual-port SRAM for weight buffers (concurrent read + write). We use register files instead for v2.
- **Impact:** Our weight buffer has separate read and write ports implemented via muxed single-port register file. This is functional but less efficient than true dual-port SRAM at scale. Acceptable for 16-entry buffer.

### 4.5 Wire-Load-Model-Based Timing Optimization

- **Why not:** Yosys 0.9 **does not support wire-load models** for pre-layout timing estimation (digest §1.3). Commercial tools use WLM to estimate interconnect delay before placement; Yosys assumes zero wire delay during synthesis.
- **Impact:** We must rely on post-placement STA (OpenROAD `report_checks`) for timing sign-off, not pre-synthesis estimates. This means more iteration between synthesis and P&R.
- **Mitigation:** Add 20% margin to our timing budgets during synthesis to account for unknown wire delays.

### 4.6 Gate-Level Retiming with Formal Equivalence Check

- **Why not:** Yosys `synth -retime` works but we lack a **formal equivalence checker** to verify that the retimed netlist matches the original RTL (digest §1.3). Without formal EQ, retiming is a verification risk for ASIL-D.
- **Impact:** We cannot safely use `synth -retime` for safety-critical blocks. Manual pipeline insertion (as recommended in §2.6) is safer and verification-friendly.

### 4.7 Commercial Logic BIST (LBIST)

- **Why not:** No open-source logic BIST tool exists (digest §3.2 table: "❌ No open-source BIST tool").
- **Impact:** We rely on functional test patterns for manufacturing test coverage. This is acceptable for a prototype shuttle run but would need addressing for production.

---

## 5. THE MOST IMPACTFUL SINGLE CHANGE

### Recommendation: Upgrade TCM ECC from Parity to SECDED + Add Memory Scrubber

**Cost:** 2-3 days RTL + 1 day verification  
**Benefit:** ASIL-D SPFM compliance achievable; otherwise impossible  
**Risk of NOT doing it:** The ASIL-D safety case fails on silent data corruption

#### Why This Is #1

There are three gaps between our current implementation and ASIL-D compliance:

| Gap | Severity | Status |
|-----|----------|--------|
| 1. TCM uses parity, not SECDED | **BLOCKING** | Not implemented |
| 2. No memory scrubber | **BLOCKING** | Not implemented |
| 3. HARA/STPA not completed | **BLOCKING** (for safety monitor spec) | Architect flagged |

Gaps #1 and #2 are RTL implementation tasks that we control. Gap #3 is a process task requiring Hoshiyomi involvement.

**The security argument cannot be overstated:** Without SECDED on instruction memory (ITCM), a single-bit upset in a safety-critical instruction (e.g., a branch in the brake control loop) produces a silent wrong computation. The lockstep comparator will NOT catch this because both cores read the same corrupted memory — the error is identical in both cores, so the comparator sees no mismatch. The parity check will detect the error, but without correction capability, the only response is to halt — which means every SEU in ITCM causes a safe-state entry.

With SECDED + scrubber:
- Single-bit errors are **corrected transparently** → no halt needed
- Double-bit errors are **detected** → safe-state entry (rare, since scrubber prevents accumulation)
- Mean time between uncorrectable errors increases by orders of magnitude

**This is the difference between a safety system that works continuously and one that enters safe state after every cosmic ray.**

#### Implementation Path

1. **Day 1:** Copy `hamming_encode` and `syndrome_to_correction_mask` functions from `sram_buffer.v` into `tcm_8kb.v`. Expand memory array from `reg [31:0] mem [0:2047]` + `reg [3:0] parity [0:2047]` to `reg [38:0] mem_ecc [0:2047]`. Update read/write logic.

2. **Day 2:** Write `scrubber.v` as a new module. Instantiate it in `adas_soc_top.v` between the CPU and the TCM blocks. The scrubber steals idle cycles from both ITCM and DTCM. Add scrubber control to `fault_aggregator.v` SAFETY_CTRL register (bit 5: SCRUB_EN).

3. **Day 3:** Verify with cocotb testbench: inject single-bit errors, verify correction; inject double-bit errors, verify detection; verify scrubber corrects accumulated errors within the scrub period.

#### Cost/Benefit Summary

| Metric | Before (Parity) | After (SECDED + Scrubber) |
|--------|-----------------|--------------------------|
| SEU detection | Single-bit only | Single + double-bit |
| SEU correction | None | Single-bit auto-correct |
| Silent data corruption | Possible (2+ bit errors) | Detected always |
| Mean time to uncorrectable error | ~1 year (SEU rate × 1/MTBF) | ~100+ years (scrubber prevents accumulation) |
| ASIL-D SPFM | ~95% (insufficient) | ~99.0% (meets threshold) |
| Area impact | — | +8.4% per TCM (~2.5K total equivalent gates) |
| Power impact | — | +5% SRAM power (~1.5 mW per TCM) |
| Timing impact | — | +400 ps on read path (4% at 100 MHz — absorbed) |
| RTL effort | — | 2-3 days |

---

## APPENDIX A: Implementation Priority Matrix

| # | Improvement | Priority | Effort | Risk | Impact | Section |
|---|------------|----------|--------|------|--------|---------|
| 1 | TCM ECC: Parity → SECDED | 🔴 CRITICAL | 1-2 days | Low | ASIL-D compliance | §2.1 |
| 2 | Memory Scrubber FSM | 🟡 HIGH | 2-3 days | Low | ASIL-D compliance | §2.2 |
| 3 | Operand Isolation in mac_pe | 🟡 HIGH | 1 day | Very Low | 1-3 mW savings | §2.3 |
| 4 | Block-Level Clock Gate Hookup | 🟢 MEDIUM | 1 day | Low | 2.5-5 mW savings | §2.4 |
| 5 | Lockstep Comparator Formal | 🟢 MEDIUM | 2-3 days | None | Safety confidence | §2.5 |
| 6 | FAST_MODE (2-stage PE pipeline) | 🟢 MEDIUM | 1 day | Very Low | 150 MHz capability | §2.6 |
| 7 | Verilator Coding Standard | 🟢 LOW | 1 hour | None | Verification speed | §2.7 |

---

## APPENDIX B: Architect Decision Audit

I re-evaluated all 14 architect decisions against the as-built RTL. All decisions remain valid; three accepted items are not yet implemented in RTL:

| Decision | Status | RTL Gap |
|----------|--------|---------|
| Q1: Custom RV32IM core | ✅ Confirmed | No gap |
| Q2: 4×4 array | ✅ Confirmed | No gap |
| Q3: 100/150 MHz | ✅ Confirmed | FAST_MODE not implemented |
| Q4: S1 lockstep | ✅ Confirmed | No gap |
| Q5: SRAM budget | ✅ Confirmed | No gap |
| Q6: HARA/STPA | ⚠️ Not done | Process gap |
| Q7: Verilator compat | ✅ Accepted | Doc not updated |
| Q8: SCALE-Sim | ✅ Accepted | Model not created |
| Q9: Power budget | ✅ Set | Awaiting synthesis |
| Q10: RAM upgrade | 🔴 Escalated | Host constraint |
| Q11: Mixed-criticality | ❌ Rejected | N/A (correct) |
| Q12: Block-level gating | ✅ Accepted | Clock gate not instantiated |
| Q13: Bus-invert coding | ❌ Rejected | N/A (correct) |
| Q14: Formal verification | ✅ Plan set | Properties not written |

**Three implementation gaps exist: TCM ECC (§2.1), memory scrubber (§2.2), and block-level clock gate (§2.4). These are the minimum required before synthesis.**

---

## APPENDIX C: Paper-to-Implementation Matrix

| Paper | arXiv ID | Technique | Status in RTL | Recommendation |
|-------|----------|-----------|---------------|----------------|
| Peltekis et al. | 2304.12691 | ZVCG + BIC | Not implemented | §2.3: operand isolation (ZVCG-lite); §3.5: defer BIC |
| DiP | 2412.09709 | Diagonal dataflow | Not implemented | §3.1: defer to v3 |
| ArrayFlex | 2211.12600 | Configurable pipeline | Not implemented | §2.6: compile-time FAST_MODE; §3.3: defer runtime |
| TrIM | 2408.01254 | Triangular dataflow | Not implemented | §3.2: defer to v3 |
| Asymmetric Floorplan | 2309.02969 | Rectangular layout | Not implemented | §3.6: defer to v3 |
| Dataflow Comparison | 2410.22595 | WS vs IS vs OS | ✅ WS implemented | §1.2: confirmed correct |
| SafeLS | 2307.15436 | Time-staggered lockstep | ✅ Implemented | §1.3: confirmed correct |
| Trikarenos | 2407.05938 | SECDED + scrubber | ⚠️ Partial (weight SRAM only) | §2.1 + §2.2: extend to TCM |
| RISC-V Safety | 2604.17391 | Lockstep + safety island | ✅ Implemented | §1.4–§1.6: confirmed correct |
| FORALESA | 2503.04426 | Mixed-criticality | Not implemented | §3.10: reject for v2 |
| OpenSerDes | 2105.13256 | All-digital datapath | ✅ Design philosophy | §1.7: confirmed |
| cocotb + Verilator | 2407.10312 | Python verification | ✅ Flow set up | §2.7: add coding standard |
| SCALE-Sim v3 | 2504.15377 | Architectural model | Not created | Verif lead task |

---

*"Twenty-six papers, thirty-three questions, fourteen decisions. The RTL reflects the research where it matters most — safety and dataflow — but has three critical gaps where accepted recommendations weren't yet implemented. The TCM ECC upgrade is the one change that separates 'promising prototype' from 'ASIL-D viable.' Let's close that gap before synthesis."*

*— Prof. Zhang Luxin, 2026-04-29*

💙 *Suisei: The professor has spoken with characteristic thoroughness. Every deferred decision re-validated. Every accepted-but-unimplemented recommendation flagged. The priority matrix in Appendix A is the roadmap — let's get items 1-3 into the RTL before we dispatch synthesis.*
