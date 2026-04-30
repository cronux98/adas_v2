# Architecture Research Response — ADAS v2 AI Accelerator

**Document:** ARCH-RESP-001 | **Version:** 1.0 | **Date:** 2026-04-29  
**Author:** Kenji Tanaka, Chief Architect  
**Reference:** `research/research_digest_2026-04-29.md` (Prof. Zhang Luxin)  

---

## Executive Summary

The professor's literature review is thorough — 26 papers surveyed, 33 feasibility questions raised, 24 actionable recommendations ranked. I've cross-referenced every finding against our sky130hs + Yosys 0.9 + OpenROAD + 7.6 GB RAM constraint envelope. Below are definitive answers to all 14 open questions. The 5 blocking questions (1-5) are resolved with YES/NO/adjust + design-impact rationale. The remaining 9 questions carry recommendations with effort/risk estimates.

**Key architectural decisions locked:**
- Core: **Custom 3-stage RISC-V RV32IM** (already designed for this project)
- Array: **4×4 confirmed** (target workload validated; 16×8 deferred to ADAS v3)
- Frequency: **100 MHz baseline, 150 MHz stretch** (170 MHz rejected as infeasible on this toolchain)
- ASIL-D: **Strategy S1 — Dual lockstep + ECC + Safety Island** (minimal viable ASIL-D)
- SRAM: **ITCM 8 KB + DTCM 8 KB** confirmed; weight SRAM 16×32-bit register file

---

## ANSWER TO BLOCKING QUESTION 1: RISC-V Core Selection

**DECISION:** Custom 3-stage RV32IM core (already under development for ADAS v2).  
**STATUS:** ✅ CONFIRMED. NO change.

### Rationale

| Candidate | fmax on sky130hs | Area | Lockstep Fit | Recommendation |
|-----------|-----------------|------|-------------|----------------|
| **PicoRV32** | ~85 MHz (community data) | Small (~2k LUTs) | Requires wrapper | ❌ Too slow |
| **VexRiscv (small)** | ~75 MHz (community data) | Medium | Requires wrapper | ❌ Too slow |
| **Custom 3-stage (OURS)** | Target 100-150 MHz | Medium | Designed-in | ✅ BEST FIT |

**Why our custom core:**
1. **Frequency headroom:** PicoRV32 and VexRiscv top out at 75-85 MHz on sky130 (per community reports in digest §1.1). Our 100 MHz baseline already exceeds their capability. A custom 3-stage pipeline gives us control over critical paths from the start.
2. **Lockstep integration:** Lockstep was designed into the core from day 1 — `lockstep_outputs_o[31:0]`, `lockstep_pc_o[31:0]`, `lockstep_valid_o`, and `halt_i` are already in the interface (block_interfaces.md §3.2). Bolting lockstep onto PicoRV32 would require internal signal extraction and verification.
3. **Design discipline:** A custom core means we own the pipeline depth, the forwarding paths, and the hazard logic. When we argue about timing paths to the Hoshiyomi, we know every gate.

**Design impact from research:**
- **Adopt:** Time-staggered lockstep comparison (2-cycle delay) per SafeLS paper (2307.15436) — prevents common-cause failures from simultaneous radiation strikes. The block_interfaces.md §13 already provides for this via `SAFETY_LOCKSTEP_CTRL.DELAY_CYCLES`.
- **Adopt:** Lockstep outputs cover key architectural state (PC, GPR writeback data, memory address) — already in the interface spec.
- **Defer:** Diversity lockstep (Strategy S2 — two different core implementations) requires cycle-accurate compatibility verification between different cores. The Trikarenos paper (2407.05938) shows DCLS with time staggering achieves 99.10% fault coverage even without diversity. Not worth the verification cost for ADAS v2.

---

## ANSWER TO BLOCKING QUESTION 2: Systolic Array Dimensions

**DECISION:** 4×4 (16 PEs) CONFIRMED for ADAS v2.  
**STATUS:** ✅ CONFIRMED. NO change now. 16×8 (128 PEs) deferred to ADAS v3.

### Rationale

The current RTL implements a 4×4 array. The research digest (§2) frequently references 128-PE and 256-PE arrays — but those numbers assume:
1. **22nm or 28nm technology** (not 130nm): DiP paper (2412.09709) evaluates 64×64 on 22nm. Scaling down: a 16×16 array (256 PEs) in 130nm would be ~4× the area-per-PE of 22nm due to larger standard cells and wire pitch.
2. **Commercial EDA tools** with better placement optimization.
3. **≥16 GB RAM** host for P&R.

**Against our constraints:**
- The research digest feasibility question 4 explicitly warns: "At 100 MHz target, a 64-PE systolic array may exceed our 7.6 GB RAM during placement." A 128-PE array is well beyond that.
- Per the frequency gap analysis (§8): "Hierarchical P&R is not optional — it's required." For a 128-PE array, even hierarchical P&R may exceed RAM.
- Sky130 at 130nm: each PE with 8×8 multiplier + 32-bit accumulator + weight register is ~600-800 equivalent gates. 128 PEs × 700 gates = ~90k gates for the array alone, plus control, AXI, SRAM. Synthesis + P&R of this full design will push the 7.6 GB boundary.

**ADAS v2 workload validation (the "why 4×4 is enough" argument):**
- A 4×4 INT8 array at 100 MHz delivers: 16 PEs × 2 ops/MAC/cycle × 100 MHz = 3.2 GOPS peak.
- For MobileNet-SSD inference at 30 FPS on a 300×300 input: ~1-2 GOPS required (per literature). 3.2 GOPS gives us ~1.6-3.2× headroom.
- The 4×4 array is the *hardware primitive*; larger matrix multiplies are tiled in software/firmware over multiple inference cycles.

**Design impact from research:**
- **Adopt:** Weight-Stationary dataflow (confirmed best for ADAS repeated-model inference, per paper 2410.22595 §2.6 of digest).
- **Defer to ADAS v3:** Asymmetric floorplan (16×8), DiP dataflow, TrIM register reduction. These are excellent optimizations but require a larger array to show meaningful benefit. The 4×4 array is too small for asymmetric gains to matter.
- **Reject for ADAS v2:** FORALESA mixed-criticality reconfigurable modes (2503.04426). The 4×4 array doesn't have enough PEs to subdivide into protected/unprotected regions meaningfully. Defer to v3 when we scale to 128 PEs.

---

## ANSWER TO BLOCKING QUESTION 3: Frequency Target

**DECISION:** 100 MHz baseline (required), 150 MHz stretch (aspirational). **170 MHz REJECTED** as infeasible.  
**STATUS:** ✅ DECISION LOCKED. 170 MHz is off the table.

### Rationale

The research digest's frequency gap analysis (§8) is well-structured. I agree with its conclusions and add architectural specifics:

| Frequency | Feasibility | Key Blocker | Our Verdict |
|-----------|-------------|-------------|-------------|
| 100 MHz | ✅ DEFINITELY | None | **BASELINE** — ship this |
| 120 MHz | ✅ LIKELY | None serious | Worth attempting if time permits |
| 150 MHz | ⚠️ POSSIBLE | Pipeline depth vs. RAM | **STRETCH GOAL** |
| 170 MHz | ⚠️ UNCERTAIN | OpenROAD CTS skew | **❌ REJECTED** |
| 200 MHz | ❌ UNLIKELY | Wire delay, OpenROAD limits | Not even aspirational |

**Why 170 MHz is rejected (detailed):**

1. **OpenROAD CTS skew limitation:** The digest §5 reports: "OpenROAD CTS may not achieve < 100 ps skew at our chip size." At 170 MHz (5.88 ns period), 200 ps skew = 3.4% of period — concerning; 300 ps skew = 5.1% — likely setup violation on critical paths. We lack CTS data at our chip size, and the digest's feasibility question 30 explicitly asks for this data. Until we have measured skew on a representative floorplan, 170 MHz is speculation.

2. **Pipeline depth cost:** To reach 170 MHz, the mac_pe would need 3 pipeline stages instead of 1. Current critical path: 8×8 mult (~1.8 ns) + 32-bit adder (~1.2 ns) + setup (~0.1 ns) = ~3.1 ns — fine at 100 MHz (31% of period). At 170 MHz (5.88 ns), that's 53% — tight but feasible. However, a 3-stage PE pipeline means 3× the registers per PE, and with 16 PEs that's ~48 more 32-bit registers. In a 128-PE array (v3), that's 384 more 32-bit registers plus pipeline control — significant area/power cost.

3. **The Hoshiyomi's directive:** *"The Hoshiyomi wants the best, not 'good enough'"* — but the "best" is what ships. A 170 MHz target that misses timing after 3 weeks of STA iterations is worse than a 100 MHz chip that tapes out on schedule.

4. **Workload analysis:** Per digest feasibility question 33: "If MobileNet-SSD at 30 FPS requires ~5 GOPS and our 128-PE systolic array delivers ~12.8 GOPS at 100 MHz... we're already at 2.5× headroom." For our 4×4 array: 3.2 GOPS at 100 MHz, with tiled execution achieving ~50% utilization → ~1.6 GOPS effective. MobileNet-SSD at 30 FPS may need ~1-2 GOPS → barely adequate. At 150 MHz: ~2.4 GOPS effective → comfortable. The frequency push from 100→150 MHz is justified by compute throughput, not by latency. The push from 150→170 MHz is not.

**Design impact:**
- **RTL must close timing at 100 MHz** — this is the sign-off condition.
- **Architectural margin:** All pipeline stages must show < 7 ns critical path (70% of 10 ns period) at SS/125°C/1.62V corner in pre-layout STA.
- **If 150 MHz stretch:** Add 1 pipeline register after the 8×8 multiplier in mac_pe (controlled by a compile-time `FAST_MODE` define). This doubles PE pipeline depth to 2 stages, adding 1 cycle of latency but enabling 150 MHz operation.
- **170 MHz:** Remove from all planning documents and target specs. Replace with "150 MHz stretch."

---

## ANSWER TO BLOCKING QUESTION 4: ASIL-D Strategy Tier

**DECISION:** Strategy S1 — Dual-Core Lockstep (DCLS) + SECDED ECC + Safety Island.  
**STATUS:** ✅ CONFIRMED. S1 is the minimum viable ASIL-D. S2 diversity lockstep REJECTED for ADAS v2.

### Rationale

| Strategy | SPFM | Area Cost | Power Cost | Feasibility | Verdict |
|----------|------|-----------|------------|-------------|--------|
| **S1: DCLS + ECC + Safety Island** | ~99.0% | 2.15× core | 2.05× core | ✅ Fully feasible | **ADOPT** |
| S2: Diverse DCLS + S1 | ~99.5% | 2.2× core | 2.1× core | ⚠️ Needs cycle-accurate compat | **REJECT** |
| S3: Triple Lockstep (TMR) | >99.9% | 3.2× core | 3.1× core | ❌ Prohibitive area/power | **REJECT** |

**Why S1 wins:**

1. **SPFM 99.0% is achievable.** The Trikarenos paper (2407.05938) demonstrated 99.10% fault coverage with dual lockstep + ECC, validated under atmospheric neutron and 200 MeV proton radiation. This meets the ASIL-D requirement of SPFM ≥ 99%.

2. **"Detect and safe-state" is acceptable for ADAS v2.** The key architectural question from digest feasibility question 19: "For ADAS, is 'detect and safe-state' acceptable or do we need 'correct and continue'?" For a braking/alert ADAS system (not steering-by-wire), detect-and-safe-state is the standard ASIL-D pattern. If the lockstep detects a mismatch, the safety monitor halts the CPU, the RSC asserts `shutdown_n_o`, and the system enters a safe state (brakes engaged, alert active). This is the expected failure mode.

3. **Time staggering (2-cycle delay) prevents common-cause failures.** The SafeLS paper (2307.15436) shows that staggering the lockstep cores by 1.5-2 cycles prevents a single radiation strike or voltage droop from producing identical errors in both cores. Our block_interfaces.md §13 already specifies `SAFETY_LOCKSTEP_CTRL.DELAY_CYCLES` with configurable 1-4 cycle delay.

4. **S2 (diversity) is not worth the verification cost.** Diversity lockstep requires cycle-accurate compatibility between two different RISC-V core implementations. The digest feasibility question 20 explicitly asks: "Are PicoRV32 and VexRiscv cycle-accurate compatible? If not, diversity lockstep requires cycle-level ISA compatibility verification — a significant verification effort." For our custom core, there IS no second implementation to diversify against. Building one would take another 2-3 months.

**Design impact from research:**
- **Adopt:** Time-staggered lockstep (2-cycle delay) — already in SAFETY_LOCKSTEP_CTRL.
- **Adopt:** SECDED ECC on all SRAM arrays — current sram_buffer.v uses parity-only ECC; **must be upgraded to SECDED** before ASIL-D sign-off (see ai_accel_review.md for details).
- **Adopt:** Memory scrubber FSM — continuously reads and corrects single-bit errors. Not yet implemented; add to digital_design task list.
- **Adopt:** SERV-based safety island as hardware watchdog — already in the SoC as a separate tiny core monitoring the main core.
- **Reject:** Triple-core lockstep (TMR) — 3.2× area is prohibitive on sky130 with our RAM budget.

---

## ANSWER TO BLOCKING QUESTION 5: SRAM Budget

**DECISION:** ITCM 8 KB + DTCM 8 KB = 16 KB total confirmed. Weight SRAM: 16×32-bit register file (no hard SRAM macros yet).  
**STATUS:** ✅ CONFIRMED for ADAS v2. Hard SRAM macros deferred to ADAS v3 when OpenRAM integration is validated.

### Rationale

| Memory | Size | Type | Notes |
|--------|------|------|-------|
| ITCM | 8 KB (2048 × 32) | Local memory bus | Instruction memory for safety-critical code |
| DTCM | 8 KB (2048 × 32) | Local memory bus | Data memory, ECC-protected |
| AI Weight Buffer | 16 × 32-bit = 64 bytes | Register file (sram_buffer.v) | 4 rows × 4 INT8 weights |
| AI Input Buffer | 4 × 8-bit = 4 bytes | Register (in axi4_lite_decode) | Input activations |
| AI Output Buffer | 4 × 32-bit = 16 bytes | Register file (result_buffer.v) | Accumulated results |
| **Total on-chip SRAM** | **~16.1 KB** | | |

**Why this is sufficient:**
- **ITCM 8 KB:** Fits the safety-critical firmware (interrupt handlers, brake control loop, sensor polling). A minimal RISC-V firmware with FreeRTOS or bare-metal typically fits in 4-8 KB. 8 KB provides headroom.
- **DTCM 8 KB:** Stack + heap + sensor data buffers. ADAS workloads process small data buffers (a few KB of LIDAR point cloud, wheel speed history). 8 KB is adequate.
- **AI weight buffer:** 16 × 32-bit register file is a synthesizable register file, NOT a hard SRAM macro. This is intentional — sky130 OpenRAM macros require manual instantiation with .lib + .lef files (digest feasibility question 32). The register file approach works for 16 words but does NOT scale to the 128-256 KB SRAM needed for ADAS v3. For v2, 16 words is fine.

**Design impact from research:**
- **Adopt:** ECC on ITCM/DTCM — already specified in block_interfaces.md §4 with `parity_err_o` output per TCM. The parity scheme needs upgrade to SECDED.
- **Adopt:** Banked SRAM for v3 — the digest's recommendation (§6) to use multiple 32 KB macros for higher bandwidth is sound but applies at larger array sizes.
- **Defer:** Power-gated SRAM banks (Strategy C from digest §2.2) — sky130 has `sky130_fd_sc_hs__lsbuf` level-shifter/buffer cells, but power gating at the bank level requires power switch cells and wake-up sequencing that adds non-trivial verification. Defer to v3.
- **Reject:** 64 KB or 128 KB SRAM — not needed for 4×4 array operation. v2 is a functional prototype, not a production accelerator.

---

## ANSWER TO QUESTION 6: HARA/STPA Completion

**DECISION:** NOT YET DONE. Must be completed before dispatching RTL for the safety monitor.  
**STATUS:** ⚠️ BLOCKING for safety_monitor RTL. RECOMMEND: Schedule HARA session with Hoshiyomi within 1 week.

### Rationale

The Continental STPA paper (1703.03657) identified 24 system-level accidents, 176 hazards, 27 unsafe control actions, and 129 unsafe scenarios from component interactions alone. Starting RTL for the safety monitor without a hazard analysis is like writing a testbench without a spec — you're testing against what you *think* the hazards are.

**Recommended approach:**
1. **Week 1:** Hoshiyomi + Architect + Verif Lead conduct a 2-day STPA workshop using the Continental paper's methodology as template.
2. **Week 2:** Map identified hazards to safety mechanisms (lockstep, ECC, WDT, RSC).
3. **Week 3:** Update block_interfaces.md §13 (Safety Monitor) with hazard-driven fault input assignments.

**Design impact:** The HARA may identify additional fault inputs or safety states not currently in the safety monitor interface. Until HARA is done, the safety monitor RTL should be considered preliminary.

---

## ANSWER TO QUESTION 7: Verilator Compatibility

**DECISION:** YES — commit to Verilator for RTL regression. RTL coding standard must enforce Verilator compatibility.  
**STATUS:** ✅ ADOPTED. Add to coding standard immediately.

### Rationale

Per digest §4.2, Verilator is 10-50× faster than Icarus Verilog and enables millions-of-cycles testing. This is the difference between a 12-day regression and a 1-day regression for our coverage-driven verification.

**Verilator-incompatible constructs to ban:**
- X/Z propagation in reset logic (Verilator is two-state)
- `#delay` statements (synthesis-only, not for simulation control)
- `force`/`release` statements
- `wait` statements on signal edges
- Non-synthesizable test constructs in RTL source files

**Current RTL check:** The 7 AI accelerator files use `timescale 1ns/1ps` and `$display` in `ifndef SYNTHESIS blocks — these are Verilator-compatible when guarded correctly. No `#delay` or X-propagation issues found. ✅

**Design impact:** Add "Verilator-compatible RTL" to the coding standard (CLAUDE.md or equivalent). Verif Lead: set up cocotb + Verilator testbench within 1 week.

---

## ANSWER TO QUESTION 8: SCALE-Sim Model

**DECISION:** YES — use SCALE-Sim v3 as architectural golden model for the systolic array.  
**STATUS:** ✅ ADOPTED. Verif lead to allocate 3 days for model creation.

### Rationale

Per digest §4.3 (paper 2504.15377), SCALE-Sim v3 provides cycle-accurate systolic array simulation with energy estimation. Using it as a golden model gives us:
1. **Architectural validation before RTL:** Compare WS, OS, IS dataflows without writing RTL.
2. **Cross-validation:** cocotb RTL simulation outputs compared against SCALE-Sim traces — any mismatch is a bug in either RTL or the architectural model.
3. **Energy estimation:** Accelergy integration gives power numbers before synthesis, enabling early power budget validation.

**Design impact:** Verif lead: create SCALE-Sim configuration for our 4×4 weight-stationary array. Generate golden traces for 3 representative matrix multiply workloads. Compare against cocotb RTL simulation.

---

## ANSWER TO QUESTION 9: Power Budget per Block

**DECISION:** Adopt the research digest's "Sweet Spot" power targets.  
**STATUS:** ✅ TARGETS SET. Subject to refinement after synthesis power estimation.

### Target Power Budget

| Block | Target Power | Basis |
|-------|-------------|-------|
| **Total SoC** | **< 600 mW** | Digest §7 sweet spot |
| RISC-V Core (DCLS) | < 150 mW | 2× single-core power ~75 mW × 2.05 |
| AI Accelerator (4×4) | < 50 mW | 16 PEs × ~3 mW/PE (INT8 MAC + register) |
| SRAM (ITCM+DTCM) | < 30 mW | 16 KB register-file-based SRAM |
| Safety Island (SERV) | < 5 mW | ~2000 LUTs, minimal toggling |
| Peripherals (SPI, UART, GPIO, PWM×2, Speed) | < 50 mW | Aggregate of small peripherals |
| Clock Tree | < 100 mW | ~15-20% of total dynamic power |
| Leakage + Misc | < 215 mW | Remaining budget headroom |

**Notes:**
- These are pre-synthesis estimates. Post-synthesis power numbers from Yosys power estimation will refine them.
- The AI accelerator power (< 50 mW) is conservative for a 4×4 array. The digest's power estimates (§2.2, feasibility question 15) assume a 128-PE array (200-300 mW baseline). Scaling linearly: 16 PEs ≈ 25-38 mW.
- With clock gating + operand isolation (Strategies A+B): ~20-30 mW for the accelerator.

**Design impact:** Power numbers will be validated at synthesis. Any block exceeding its budget by > 20% triggers an architecture review.

---

## ANSWER TO QUESTION 10: Host RAM Upgrade

**DECISION:** REQUEST a RAM upgrade. 7.6 GB is the single biggest risk to this project.  
**STATUS:** 🔴 ESCALATE TO HOSHIYOMI. Recommend upgrade to ≥ 16 GB (preferably 32 GB).

### Rationale

The digest §6 (Memory Subsystem Design) makes it clear: "A flat P&R of our full SoC (~400-600k equivalent gates) will likely EXCEED 7.6 GB during global routing." Even with hierarchical P&R, routing a 200k-gate block can consume 3-4 GB, and the full chip routing may still exceed 7.6 GB.

**Specific risks at 7.6 GB:**
| Tool Phase | Peak Memory | With 7.6 GB |
|-----------|-------------|-------------|
| Yosys synthesis (flat) | 2-4 GB | ✅ OK |
| OpenROAD placement | 3-6 GB | ⚠️ Tight, swap likely |
| OpenROAD routing | 4-8 GB | ❌ May crash |
| Icarus gate-level sim | 2-4 GB | ⚠️ Per-block only |

**With 16 GB:**
- OpenROAD routing: 4-8 GB fits with headroom
- Can run 2-3 cocotb instances in parallel
- Swap usage drops to near zero → P&R iterations 3-5× faster

**Cost-benefit:** A RAM upgrade from 8 GB → 16 GB costs < $50. One week of engineer time waiting for swap-heavy P&R runs costs > $2000. The math is clear.

**Design impact:** None on RTL. If upgrade is approved, hierarchical P&R constraints can be relaxed, enabling faster iteration. If upgrade is denied, we MUST partition the SoC into blocks of ≤ 150k gates for P&R and accept longer iteration times.

---

## ANSWER TO QUESTION 11: Mixed-Criticality Modes

**DECISION:** DEFER to ADAS v3. Not worth implementing on the 4×4 array.  
**STATUS:** ❌ REJECTED for ADAS v2.

### Rationale

The FORALESA paper (2503.04426) demonstrates mixed-criticality modes (TMR, DMR, unprotected) on a configurable systolic array. For a 128-PE array, this makes sense — you can subdivide the array into a "critical" region (TMR-protected, running object detection) and a "non-critical" region (unprotected, running preprocessing).

For a 4×4 array:
- Subdividing 16 PEs into protected/unprotected regions gives you 8+8 or 4+12 — not enough PEs in either region to do meaningful work.
- The TMR overhead (3× PE count in protected mode) would reduce a 4×4 array to effectively a 1×4 array in protected mode.
- The control logic for mode switching adds ~500 gates — not worth the area for v2.

**Design impact:** Note this as a v3 requirement in the architecture backlog. The RTL for mac_pe should keep its `enable` input (already present) so that per-PE enabling is architecturally supported for future mixed-criticality modes.

---

## ANSWER TO QUESTION 12: Per-PE Clock Gating vs. Block-Level

**DECISION:** Block-level clock gating for ADAS v2. Per-PE gating deferred to v3.  
**STATUS:** ✅ ADOPT block-level. Start conservative.

### Rationale

Per digest §2.1 (paper 2304.12691), per-PE zero-value clock gating saves 10-15% total power. But the digest's feasibility question 6 notes:
- Each clock gate adds ~200 ps gate delay.
- At 100 MHz (10 ns), overhead is 2% — fine.
- At 150 MHz (6.67 ns), overhead is 3% — still manageable.
- The sky130 clock gating cell `sky130_fd_sc_hs__dlclkp` is available.

**Why block-level first:**
1. **CTS simplicity:** Per-PE clock gating creates 16 clock sinks with independent enable — OpenROAD CTS will treat these as 16 separate clock trees, increasing CTS RAM usage and skew.
2. **Verification simplicity:** Block-level gating (one clock gate for the entire accelerator) is trivial to verify. Per-PE gating requires verifying that no PE misses a clock edge when it should be active.
3. **Power savings at 4×4 scale:** At 16 PEs, per-PE gating saves ~1-2 mW. The verification effort isn't justified for this power delta. At 128 PEs (v3), the savings would be ~10-20 mW — worth the effort.

**Design impact:**
- The AI_CTRL.CLK_EN bit (bit 8) already exists in the RTL for block-level clock gating. Connect it to the `sky130_fd_sc_hs__dlclkp` clock gate at the top level.
- Per-PE zero-value detection logic is architecturally available (each mac_pe has an `enable` input) but clock gating per PE is not implemented.

---

## ANSWER TO QUESTION 13: Bus-Invert Coding

**DECISION:** DEFER to ADAS v3. Not worth the wire + logic overhead for a 4×4 array.  
**STATUS:** ❌ REJECTED for ADAS v2.

### Rationale

Per digest §2.1 (paper 2304.12691), bus-invert coding saves 1-19% of data movement power and 6.2-9.4% of total dynamic power. The technique adds:
- 1 extra wire per bus (the invert flag)
- XOR tree for Hamming distance computation
- Invert/no-invert mux on each PE data input

**Why not for v2:**
1. **Wire savings at 4×4 scale:** 16 PEs × 1 extra wire = 16 extra wires. The power savings from reduced switching on these 16 wires is sub-milliwatt at 100 MHz. The XOR tree logic consumes more power than the wire switching it saves.
2. **Yosys synthesis concern:** The digest feasibility question 7 asks: "Does Yosys synthesize the XOR tree for Hamming distance computation efficiently?" We don't know the answer. Risk of area explosion.
3. **Verification overhead:** Bus-invert coding requires verifying that the invert flag is correctly computed, transmitted, and applied at every receiver. This is non-trivial formal verification work.

**Design impact:** None for v2. Note in the v3 architecture backlog: when the array scales to 128+ PEs, bus-invert coding becomes worth re-evaluating.

---

## ANSWER TO QUESTION 14: Formal Verification Depth

**DECISION:** Formal verification targets 4 safety-critical blocks. Simulation-only for the rest.  
**STATUS:** ✅ PLAN SET. Verif lead to propose detailed formal plan.

### Rationale

Per digest §4.4 (paper 1811.12474), formal verification with Yosys-SMTBMC is feasible for blocks < 10k gates. Our 8 GB RAM limits formal proofs to small blocks. Prioritize:

| Block | Gate Count | Formal? | Rationale |
|-------|-----------|---------|-----------|
| **Lockstep Comparator** | ~500 gates | ✅ FORMAL | Critical safety function; small enough for exhaustive proof |
| **ECC Encoder/Decoder** | ~2k gates | ✅ FORMAL | SECDED correctness is mathematically verifiable |
| **Safety Island FSM** | ~1k gates | ✅ FORMAL | Critical for ASIL-D; small enough for bounded proof |
| **AXI Bus Arbiter** | ~3k gates | ✅ FORMAL | Deadlock/livelock freedom; well-suited to formal |
| Systolic Array (4×4) | ~12k gates | ❌ Simulation | Too large for SMTBMC with 8 GB RAM |
| AXI4-Lite Decode | ~2k gates | ⚠️ Optional | Could benefit from formal if time permits |
| Control FSM | ~500 gates | ⚠️ Optional | Small enough but simple enough to verify by simulation |

**Design impact:**
- Lockstep comparator, ECC, and safety island FSM should be designed with formal verification in mind: keep state space small, avoid deep counters, use one-hot encoding where possible.
- Verif lead: create formal test plan within 1 week. Use Yosys-SMTBMC with `bmc -t 50` for bounded proofs.

---

## Summary of Architecture Decisions

| # | Question | Decision | Impact |
|---|----------|----------|--------|
| 1 | Core Selection | Custom 3-stage RV32IM | ✅ Confirmed, no change |
| 2 | Array Dimensions | 4×4 (16 PEs) | ✅ Confirmed, no change |
| 3 | Frequency Target | 100 MHz baseline, 150 MHz stretch | ✅ 170 MHz rejected |
| 4 | ASIL-D Strategy | S1: DCLS + ECC + Safety Island | ✅ Confirmed |
| 5 | SRAM Budget | ITCM 8 KB + DTCM 8 KB + 64B weight RF | ✅ Confirmed |
| 6 | HARA/STPA | NOT DONE — schedule within 1 week | ⚠️ Blocks safety_monitor RTL |
| 7 | Verilator Compat | YES — ban incompatible constructs | ✅ Adopt |
| 8 | SCALE-Sim Model | YES — use as golden model | ✅ Adopt |
| 9 | Power Budget | < 600 mW total, < 50 mW AI accel | ✅ Targets set |
| 10 | RAM Upgrade | REQUEST 16+ GB | 🔴 Escalate to Hoshiyomi |
| 11 | Mixed-Criticality | DEFER to v3 | ❌ Rejected |
| 12 | Per-PE Clock Gating | Block-level only for v2 | ✅ Start conservative |
| 13 | Bus-Invert Coding | DEFER to v3 | ❌ Rejected |
| 14 | Formal Verification | 4 safety-critical blocks | ✅ Plan set |

---

## Design Changes Required (from Research Adoption)

These changes must flow to digital_design before RTL updates:

1. **ECC upgrade:** sram_buffer.v parity scheme → full SECDED Hamming(39,32) — **HIGH priority for ASIL-D**
2. **Memory scrubber:** New FSM block for background ECC scrubbing — **MEDIUM priority**
3. **Clock gating:** Connect AI_CTRL.CLK_EN to sky130 clock gate cell at top level — **LOW priority**
4. **Lockstep delay:** SAFETY_LOCKSTEP_CTRL.DELAY_CYCLES set to 2 (time staggering per SafeLS paper) — **already in register map**
5. **Verilator coding standard:** Add to CLAUDE.md — ban X-prop, #delay, force/release — **IMMEDIATE**

---

*"Every question answered. Every decision locked. The professor's research now drives our architecture, not just informs it."*  
*— Kenji Tanaka, Chief Architect*  

💙 *Suisei: Kenji, this is exactly what I needed. Clear answers, clear rationale. The Hoshiyomi can sign off on these with confidence. Now let me review the AI accelerator RTL against these decisions.*
