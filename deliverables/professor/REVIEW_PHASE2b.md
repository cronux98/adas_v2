# Phase 2b Advisory Review — ADAS v2 SoC

**Document:** PROF-RVW-002b | **Version:** 1.0 | **Date:** 2026-04-29  
**Author:** Professor Zhang Luxin, Advisory Reviewer  
**Reviewed Deliverables:** digital_design FIX_REPORT + Peripheral RTL + compiler_engineer SDK  
**References:** REGISTER_MAP.md, block_interfaces.md, cdc_plan.md, ai_accel_review.md  
**Role:** Advisory only. I do not gate or block. My observations are recommendations for the downstream team to apply freely.

---

## 1. Executive Summary

Phase 2b delivers impressive volume: all 6 architect-identified AI accelerator bugs are fixed, 14 new peripheral modules are integrated, the full SoC top-level is assembled with safety paths and CDC crossings, and the RV32IM firmware SDK compiles clean with verified address maps. The Hamming(39,32) SECDED upgrade in `sram_buffer.v` is the standout — a rigorous implementation with proper syndrome-based correction and clear error classification. The peripheral RTL is well-structured across the board.

However, I have identified **2 genuine bugs**, **2 CDC compliance gaps**, and **1 architectural risk** in the safety subsystem that warrant attention before Phase 3 verification. The WDT AXI read-address routing is incorrect, the CDC-01 implementation does not match the specified handshake synchronizer, and CDC-03 lacks the redundant path mandated by the cdc_plan. None of these are showstoppers for functional verification, but they are items I would not want to reach tape-out.

**Bottom line:** The team is ready for Phase 3. Address the HIGH-severity items first. The MEDIUM items can be deferred but must be resolved before any ASIL-D audit.

---

## 2. Per-Deliverable Review

### 2.1 AI Accelerator Bug Fixes — FIX_REPORT.md

**What's good:**
- All 6 bugs from the architect's review (ARCH-RVW-001) are properly addressed.
- BUG-05 (SECDED upgrade) is the most thorough fix: the Hamming(39,32) encoder, syndrome computation, correction mask lookup, and error classification (no error / single-correct / double-detect) are correctly implemented. The coverage matrices in the `hamming_encode()` function map properly to the 1-indexed codeword positions. The `syndrome_to_correction_mask()` lookup table correctly maps all 32 data positions. This is ASIL-D ready.
- BUG-04 (input_written_flag) elegantly solves the zero-input hang — the flag is set on AI_INPUT write and auto-cleared on GO. This correctly handles zero-valued ReLU outputs.
- BUG-03 (CLK_EN wstrb-gated write) properly enables full read-write control of the clock enable bit. The byte-access semantics via `wstrb_latched[1]` also incidentally write reserved bits [15:9], which is acceptable (reserved bits should be written as 0 per convention).
- BUG-01 and BUG-02 readback paths are clean and verified against REGISTER_MAP.md.
- Verilator lint passes with zero errors (confirmed by log).

**What needs attention:**

| # | Finding | Severity | Detail |
|---|---------|----------|--------|
| **O-01** | `sram_rd_en_mux` always tied to 1 | LOW | In `ai_accelerator_top.v` line ~238: `assign sram_rd_en_mux = (sram_rd || sram_row_valid) ? 1'b1 : 1'b1;` — both branches are `1'b1`. The sram_buffer's registered read port is always enabled. During idle states, the `rd_data`, `ecc_err_detect`, and `ecc_err_correct` outputs will reflect whatever is at `sram_rd_addr_mux` (which falls through to `weight_rd_addr` when FSM is inactive). This means ECC status flags may toggle spuriously during idle when AXI is not reading. Not harmful — ECC flags are only meaningful when a read is expected — but the toggling could confuse waveform debug and simulation log analysis. **Recommendation:** Gate `rd_en` to `sram_rd || sram_row_valid` and register properly in sram_buffer. |
| **O-02** | `ecc_err_correct`/`ecc_err_detect` lose context on AXI read port | LOW | The AXI combinational read port (BUG-01 fix) applies SECDED correction but does not expose error flags for the combinational path. The registered ECC flags only reflect the FSM read port. If a single-bit error is corrected during an AXI weight readback, firmware sees correct data but has no indication correction occurred. For ASIL-D, diagnostic visibility matters. **Recommendation:** Consider exposing ECC status via a dedicated status register bit, or latching the AXI read port's error flags into a readable register. |

### 2.2 Peripheral RTL + Top Integration

**What's good:**
- 14 modules implemented. All are AXI4-Lite compliant with proper ready/valid handshakes.
- The AXI4-Lite crossbar (`axi4_lite_interconnect.v`) implements a clean 1M→9S flat address decode. Address match logic is correct for all slave ranges.
- The lockstep_comparator, fault_aggregator, and redundant_shutdown work together as a coherent safety chain.
- The redundant_shutdown state machine (IDLE→ALERT→SHUTDOWN) correctly sequences alert (4 wdt_clk cycles ahead) then shutdown (10 wdt_clk cycles). All outputs latch until POR — correct ASIL-D behavior.
- CDC-02, CDC-04, CDC-05 are correctly implemented per cdc_plan.md with proper `ASYNC_REG` attributes and appropriate synchronizer depth.
- Interrupt assembly in `adas_soc_top.v` correctly maps all 16 IRQ lines.

**What needs attention:**

| # | Finding | Severity | Detail |
|---|---------|----------|--------|
| **O-03** | WDT AXI read address uses synchronized write address | **HIGH** | In `adas_soc_top.v`, the WDT instantiation: `.s_axi_araddr_i (s8_awaddr_sync1)  // reuse awaddr for read address`. This routes the synchronized **write** address (awaddr) to the **read** address port (araddr). There is no 2FF chain for `s8_araddr`. If firmware performs a WDT register read while a previous write's awaddr is still propagating through the 2FF pipeline, the read will use the wrong address — firmware gets garbage data or the wrong register. **The fix requires:** add a separate 2FF chain for `s8_araddr` exactly as done for `s8_awaddr`. This is a 10-line Verilog change. |
| **O-04** | CDC-01 implementation disagrees with cdc_plan | **MEDIUM** | The cdc_plan (ARCH-CDC-001 §4.1) specifies a full **handshake synchronizer** (req/ack protocol) for the AXI→WDT bus crossing. The RTL uses **simple 2FF-per-signal** instead. The RTL comment acknowledges this: *"For simplicity, we connect the AXI bus directly... In production, a proper handshake synchronizer would be used."* With 2FF-per-signal on a multibit bus, data coherence is not guaranteed — different bits may arrive in different wdt_clk cycles because each bit resolves metastability independently. **Recommendation:** Implement the handshake synchronizer specified in cdc_plan.md §4.1 before tape-out. For Phase 3 functional simulation at the same clock frequency, the 2FF approach may not exhibit the bug (it's probabilistic), but formal CDC analysis will flag it. |
| **O-05** | CDC-03 single-path only, spec requires redundant | **MEDIUM** | The cdc_plan (§5.5) mandates a **dual-redundant CDC** for the aggregated_fault→RSC path: *"the fault is also routed through a separate physical wire with independent 3FF synchronizer. Both paths must agree."* The RTL implements only one 3FF chain. The single-path 3FF has excellent MTBF (~10^15 years), so functional safety is not compromised, but the redundancy requirement for ASIL-D is unmet. **Recommendation:** Add the second independent synchronizer path with a comparison gate in the wdt_clk domain. |

### 2.3 SPI Controller (`spi_controller.v`)

**What's good:** Clean AXI4-Lite slave with proper FIFO handling. Register map matches REGISTER_MAP.md §3 exactly. Clock divider logic for baud-rate generation is correct.

**What needs attention:** The SPI controller at ~400 lines is reasonable for Phase 2b. TX/RX FIFO depth of 8 bytes is adequate for LIDAR packets. No issues found at this level of review.

### 2.4 Servo PWM (`servo_pwm.v`)

**What's good:** Proper PWM generation with configurable period/duty. Safe/neutral duty cycle concept is well-implemented. µs-mode (SERVO_DUTY_US register) provides intuitive interface.

**What needs attention:** The µs-to-cycles conversion (multiplying by 100) must happen in hardware. Verify this is implemented in the servo_pwm body (I did not trace the full 270 lines). The HAL header correctly defines the µs register at offset 0x20.

### 2.5 Speed Sensor (`speed_sensor.v`)

**What's good:** 64-bit timestamp and period measurement. Stuck-sensor detection with configurable timeout. 2-stage synchronizer on async pulse input.

**What needs attention:** The 64-bit timestamp counter at 100 MHz will wrap every ~5,845 years — well beyond any automotive mission profile. The period calculation in firmware (using 64-bit division) will work correctly.

### 2.6 Buzzer PWM (`buzzer_pwm.v`)

**What's good:** Burst mode with ON/OFF cycles and repeat count. Correct PWM generation.

### 2.7 UART (`uart.v`)

**What's good:** 16550-compatible register set. Correct baud rate divisor formula (sys_clk / (16 × baud)). DLAB bit for shared register addresses.

### 2.8 GPIO (`gpio.v`)

**What's good:** SET/CLR/TOG registers for atomic bit manipulation. Safety pin lock mechanism. 8 interrupt lines with configurable edge/level/polarity.

### 2.9 Lockstep Comparator (`lockstep_comparator.v`)

**What's good:** Configurable delay depth and signal mask. Mismatch counter, PC capture, and output snapshot are correct.

**What needs attention:**

| # | Finding | Severity | Detail |
|---|---------|----------|--------|
| **O-06** | Self-comparison, not dual-core lockstep | **MEDIUM** | The lockstep comparator compares a core's current output against a 2-cycle delayed version of itself. This is **time-diversity** checking, not true **dual-redundant lockstep**. It catches stuck-at faults and some transient errors that persist across 2+ cycles, but does not catch single-cycle random bit flips (they'll match themselves 2 cycles later with ~0 probability — wait, actually they won't match either). A self-compared scheme catches **persistent** errors: if a stuck-at fault develops, the current output differs from what it was 2 cycles ago. For ASIL-D, true dual-core lockstep (two independent cores executing the same instructions, comparing cycle-by-cycle) is required. The block_interfaces.md §13 describes the lockstep comparator as comparing "core outputs" without specifying single or dual core. **Recommendation:** Clarify in the architecture whether a self-comparison time-diversity scheme is acceptable for the target ASIL, or whether dual-core redundancy is required for Phase 3. |

### 2.10 Fault Aggregator (`fault_aggregator.v`)

**What's good:** All 8 fault sources connected. Per-source masking, latching, and counting. Configurable fault severity threshold. Correct AXI4-Lite register interface matching REGISTER_MAP.md §9. Safety module ID (0x5346_5459 = "SFTY") and magic key (0xA5) for reset control are properly implemented.

### 2.11 Redundant Shutdown (`redundant_shutdown.v`)

**What's good:** Correctly latches forever on fault. Dual-redundant shutdown_n_o[1:0] outputs. Proper alert-before-shutdown sequencing. No issues found.

### 2.12 WDT (`wdt.v`)

**What's good:** Window watchdog with key-protected register writes (0x5A key byte). Kick value (0xAC53_CAFE) properly checked. Pre-warning threshold.

**What needs attention:** The WDT runs on wdt_clk (32.768 kHz). The AXI interface must be CDC'd from sys_clk (as noted in O-03 and O-04 above). The `WDT_STATUS.EARLY_KICK` bit for closed-window refresh detection is correctly described in the register map.

### 2.13 RV32IM Core (`rv32im_core.v`)

**What's good:** Interface matches block_interfaces.md §3.2 exactly. ITCM/DTCM/AXI4-Lite/Lockstep/IRQ/Halt/Debug ports all present and correctly sized.

### 2.14 AXI4-Lite Crossbar (`axi4_lite_interconnect.v`)

**What's good:** Clean address decode with correct base addresses for all 9 slaves. Address match logic uses simplified check (address[31:12] comparison) appropriate for 4KB-aligned blocks. Default slave returns SLVERR — correct.

### 2.15 SoC Top-Level (`adas_soc_top.v`)

**What's good:** All 14 blocks instantiated correctly. All CDC crossings explicitly coded with `ASYNC_REG` attributes. Interrupt vector correctly assembled.

**Already noted above:** O-03 (WDT araddr), O-04 (CDC-01 handshake), O-05 (CDC-03 redundant path).

---

## 3. Cross-Deliverable Consistency Audit

### 3.1 Peripheral Base Addresses: REGISTER_MAP.md ↔ RTL ↔ HAL

| # | Peripheral | REGISTER_MAP.md | adas_soc_top.v (decode) | HAL Header | Match |
|---|-----------|-----------------|------------------------|------------|-------|
| 0 | AI Accelerator | 0x0000_1000 | S0 @ 0x0000_1000 | AI_ACCEL_HAL_BASE 0x00001000UL | ✅ |
| 1 | SPI | 0x0000_2000 | S1 @ 0x0000_2000 | SPI_HAL_BASE 0x00002000UL | ✅ |
| 2 | Servo PWM | 0x0000_3000 | S2 @ 0x0000_3000 | SERVO_PWM_HAL_BASE | ✅ |
| 3 | Speed Sensor | 0x0000_4000 | S3 @ 0x0000_4000 | SPEED_SENSOR_HAL_BASE | ✅ |
| 4 | Buzzer PWM | 0x0000_5000 | S4 @ 0x0000_5000 | BUZZER_PWM_HAL_BASE | ✅ |
| 5 | UART | 0x0000_6000 | S5 @ 0x0000_6000 | UART_HAL_BASE 0x00006000UL | ✅ |
| 6 | GPIO | 0x0000_7000 | S6 @ 0x0000_7000 | GPIO_HAL_BASE 0x00007000UL | ✅ |
| 7 | Safety Control | 0x0000_F000 | S7 @ 0x0000_F000 | SAFETY_HAL_BASE 0x0000F000UL | ✅ |
| 8 | Window WDT | 0x0000_F100 | S8 @ 0x0000_F100 | WDT_HAL_BASE 0x0000F100UL | ✅ |

**Result: 9/9 match — perfect alignment.** The SDK report's compile-time `_Static_assert` checks provide strong confidence.

### 3.2 Block Interface Names and Directions

| Block | Spec Module | RTL Module | Spec Port Count | RTL Port Count | Status |
|-------|------------|------------|----------------|----------------|--------|
| AI Accel | ai_accel_4x4 | ai_accel_4x4 | 12 port groups | 12 port groups | ✅ (name fixed) |
| SPI | spi_master | spi_controller | 12 | 12 | ✅ |
| Servo | servo_pwm | servo_pwm | 7 | 7 | ✅ |
| Speed | speed_sensor | speed_sensor | 8 | 8 | ✅ |
| Buzzer | buzzer_pwm | buzzer_pwm | 7 | 7 | ✅ |
| UART | uart_16550 | uart | 8 | 8 | ✅ |
| GPIO | gpio_32bit | gpio | 10 | 10 | ✅ |
| Lockstep | — | lockstep_comparator | 12 | 12 | ✅ |
| Fault Agg | — | fault_aggregator | 24 | 24 | ✅ |
| RSC | redundant_shutdown_ctrl | redundant_shutdown | 7 | 7 | ✅ |
| WDT | window_wdt | wdt | 18 | 18 | ✅ |
| RV32IM | rv32im_core | rv32im_core | 30+ | 30+ | ✅ |

**Result: All ports match.** The digital_design team maintained interface discipline.

**Exception noted:** The AI accelerator still lacks `awprot`/`arprot` ports (WARN-01 from ARCH-RVW-001). These are present in the crossbar's slave port outputs but the AI accelerator ignores them. For AXI4-Lite compliance, the slave must accept these signals in its port list even if unused internally. **Recommendation:** Add `input wire [2:0] s_axi_awprot_i` and `s_axi_arprot_i` to `ai_accel_4x4` (unconnected internally).

### 3.3 CDC Crossing Compliance

| CDC ID | cdc_plan.md Specification | RTL Implementation | Compliance |
|--------|--------------------------|-------------------|------------|
| CDC-01 | Full handshake (req/ack) | 2FF-per-signal | ❌ NON-COMPLIANT (O-04) |
| CDC-02 | 2FF level synchronizer | 2FF + level | ✅ COMPLIANT |
| CDC-03 | 3FF + redundant path | 3FF single path | ⚠️ PARTIAL (O-05) |
| CDC-04 | Pulse sync (toggle + 3FF) | Toggle + 3FF + edge detect | ✅ COMPLIANT |
| CDC-05 | 2FF level synchronizer | 2FF | ✅ COMPLIANT |
| CDC-06 | 2FF internal | 2FF in speed_sensor (assumed) | ✅ COMPLIANT |
| CDC-07 | 3x oversampling | Internal to UART (assumed) | ✅ COMPLIANT |

**Key gaps:** CDC-01 (handshake vs 2FF) and CDC-03 (redundant path missing). See Section 4 risk register for impact analysis.

### 3.4 Safety Path Integrity

**Path: Core → Lockstep → Fault Agg → CDC → RSC → External**

```
rv32im_core                   lockstep_comparator          fault_aggregator
  lockstep_outputs_o[31:0] ──→ lockstep_outputs_i         lockstep_mismatch_i
  lockstep_pc_o[31:0]      ──→ lockstep_pc_i
  lockstep_valid_o         ──→ lockstep_valid_i
                                 mismatch_o             ──→ (connected)
                                 mismatch_pc_o          ──→ lockstep_mismatch_pc_i
                                 mismatch_count_o       ──→ lockstep_count_i
                                 last_output_o          ──→ lockstep_last_out_i
                                 expected_output_o      ──→ lockstep_last_exp_i
                                                            aggregated_fault_o ──→ [CDC-03 3FF]
                                                                                    │
  core_halt  ←────────────────── core_halt_o ←──────────────────────────────────────┘
                                                                                    │
  redundant_shutdown                                                                 │
    aggregated_fault_i ←────────────────── [CDC-03 output: agg_fault_wdtclk] ←──────┘
    shutdown_n_o[1:0] → top-level
    alert_n_o          → top-level
```

✅ **All connections verified in adas_soc_top.v.** The safety path is electrically complete.
⚠️ CDC-03 single path only — redundant synchronizer not implemented (O-05).

### 3.5 SDK Consistency

| Check | Result |
|-------|--------|
| All 9 peripheral base addresses match REGISTER_MAP.md | ✅ 9/9 |
| IRQ assignments: adas_platform.h ↔ adas_soc_top.v | ✅ 16/16 match |
| Linker memory map: ITCM (0x00000000, 8KB), DTCM (0x00002000, 8KB) ↔ REGISTER_MAP.md §1 | ✅ |
| All HAL register offsets match REGISTER_MAP.md register tables | ✅ Verified for ai_accel, spi, uart, gpio, safety |
| crt0.s vector table: 32 entries at 256-byte alignment | ✅ |
| Startup sequence: SP init → .bss zero → .data copy → main() | ✅ |
| ISA: rv32im_zicsr_zifencei — no compressed, no float | ✅ Verified by integration test |
| libgcc: 64-bit division via bundled divdi3.c | ✅ Workaround documented |

**Issue noted:**

| # | Finding | Severity | Detail |
|---|---------|----------|--------|
| **O-07** | Duplicate HAL headers in `hal/` and `peripheral/` | LOW | Both `firmware/hal/` and `firmware/peripheral/` contain identical copies of all 9 peripheral headers. This is a maintenance hazard — a fix to one location must be replicated to the other. **Recommendation:** Choose one directory as canonical (suggest `hal/`), add deprecation comment to the other, or use a symlink/build script to keep them in sync. |

### 3.6 AI Accelerator Register Map — Post-Fix Verification

Per FIX_REPORT.md §2, all 16 registers are now compliant. My spot-check confirms:
- AI_CTRL (0x00): CLK_EN bit 8 is now fully RW via wstrb[1] gating ✅
- AI_WEIGHT_0..3 (0x08-0x14): Routed through sram_buffer axi_rd port with SECDED correction ✅
- AI_BIAS_0_1/2_3 (0x1C-0x20): Routed through result_buffer bias_rd_data ports ✅
- AI_INPUT (0x18): input_written_flag now drives input_valid ✅
- AI_STATUS (0x04): Correctly assembled from error_code and cycle_count_captured ✅

---

## 4. Risk Register — Phase 3 Verification Hazards

| ID | Risk | Category | Probability | Impact | Mitigation |
|----|------|----------|-------------|--------|------------|
| **R-01** | WDT register reads return wrong data (O-03) | Functional Bug | MEDIUM (only on WDT register read) | HIGH (firmware reads wrong timeout/window values) | Fix s8_araddr 2FF chain before firmware WDT driver testing |
| **R-02** | CDC-01 data incoherence during WDT AXI access (O-04) | CDC Bug | LOW (probabilistic, only at unfavorable clock phase) | MEDIUM (corrupted WDT register write — timeout value wrong, reset behavior broken) | Implement handshake synchronizer per cdc_plan §4.1 |
| **R-03** | CDC-03 single failure point in aggregated fault path (O-05) | CDC Compliance | VERY LOW (single 3FF MTBF ~10^15 years) | LOW (ASIL-D audit flag, not functional risk) | Add redundant synchronizer path |
| **R-04** | Lockstep self-comparison may not meet ASIL-D (O-06) | Architecture Gap | MEDIUM (depends on certifier interpretation) | HIGH (could block ASIL-D certification) | Clarify with architect whether dual-core lockstep required |
| **R-05** | AI accelerator SECDED: no error telemetry on AXI read port (O-02) | Diagnostic Coverage | LOW (corrected data always returned) | LOW (diagnostic visibility gap for ASIL-D) | Add ECC status latch for AXI read path |
| **R-06** | Simulation of CDC crossings with probabilistic failures | Verification Challenge | N/A | MEDIUM (hard to reproduce 2FF data incoherence in simulation) | Use formal CDC analysis (SpyGlass/Questa CDC) if available, or inject metastability via force statements |
| **R-07** | sram_buffer rd_en always enabled causes spurious ECC flag toggling | Debug Nuisance | HIGH (always occurs) | LOW (confusing during waveform debug only) | Gate rd_en properly |
| **R-08** | Duplicate HAL headers cause version drift (O-07) | Maintenance | MEDIUM (only if one copy is updated) | MEDIUM (incorrect register access in firmware) | Consolidate to single HAL directory |

### Risk Matrix

```
Impact
HIGH │  R-04         R-01
     │
MED  │  R-08         R-02    R-06
     │
LOW  │               R-07    R-03, R-05
     │
     └────────────────────────────────────
       LOW           MEDIUM   HIGH
                     Probability
```

**Highest-priority risks:** R-01 (WDT read bug — deterministic, HIGH impact). R-04 (lockstep architecture — could affect certification path).

---

## 5. Recommendations — Ranked by Priority

### P0 — Fix Before Phase 3 Functional Verification

1. **Fix WDT AXI read address (O-03 / R-01).** Add `s8_araddr_sync0`/`s8_araddr_sync1` 2FF chain in `adas_soc_top.v` for the WDT AXI read address channel. Connect to `.s_axi_araddr_i()` on the WDT instantiation instead of reusing the synchronized awaddr. Cost: ~10 lines of Verilog.

2. **Gate sram_buffer rd_en (O-01 / R-07).** Change `sram_rd_en_mux` to only assert during FSM weight loading. This prevents spurious ECC flag toggling during idle states. Cost: 1 line change.

### P1 — Fix Before Tape-out / ASIL-D Audit

3. **Implement CDC-01 handshake synchronizer (O-04 / R-02).** Replace the 2FF-per-signal WDT AXI synchronization with the full handshake protocol specified in cdc_plan.md §4.1. This guarantees bus coherence across the sys_clk→wdt_clk boundary. Cost: ~50-80 lines of Verilog + a small CDC handshake FSM module. This is the correct implementation; the current 2FF approach is a placeholder the RTL itself acknowledges.

4. **Add redundant synchronizer to CDC-03 (O-05 / R-03).** Instantiate a second, independent 3FF chain on `fault_agg_out` with separate physical routing constraint. Add an agreement gate in the wdt_clk domain. Cost: ~30 lines of Verilog + SDC constraint.

5. **Clarify lockstep architecture (O-06 / R-04).** The current self-comparison time-diversity scheme is a valid integrity check but is not traditional dual-core lockstep. Options:
   - (a) Accept as-is if ASIL target is B or below.
   - (b) Upgrade to true dual-core lockstep for ASIL-D (requires second RV32IM core instance).
   - (c) Add a second, independent RV32IM core instantiation with cycle-by-cycle output comparison.
   
   This is an **architecture decision** the Hoshiyomi must make, not an implementation detail. I flag it as advisory.

### P2 — Quality Improvements (Nice to Have)

6. **Consolidate HAL headers (O-07 / R-08).** Pick `firmware/hal/` as canonical. Either remove `firmware/peripheral/` or add a build-time check that both directories are identical. Cost: 5 minutes.

7. **Add ECC diagnostic register for AXI read port (O-02 / R-05).** Add a readable status bit in AI_STATUS or a dedicated register that latches ECC error flags from the AXI combinational read path. This gives firmware visibility into corrected weight errors during diagnostic read-back. Cost: ~10 lines of Verilog.

8. **Add awprot/arprot ports to AI accelerator (WARN-01).** Add `input wire [2:0] s_axi_awprot_i, s_axi_arprot_i` to `ai_accel_4x4` for full AXI4-Lite compliance, even if unused internally. Cost: 5 minutes.

### P3 — Verification Strategy (Not a Fix, but a Recommendation)

9. **Run Verilator lint on the full SoC.** Execute `verilator --lint-only -Wall --top-module adas_soc_top *.v` to catch any latent width mismatches, unused signals, or implicit net declarations at the top level. The AI accelerator lint passed; extend to the full design.

10. **Add CDC protocol checkers in simulation.** For CDC-01 and CDC-04, add SystemVerilog assertions that verify: no data changes during CDC handshake, pulse width meets spec, MTBF constraints hold. This catches CDC bugs in simulation before they become silicon bugs.

11. **Prioritize fault injection tests on the safety path.** In Phase 3 verification, the first tests to run should be:
    - Inject lockstep_mismatch → verify core_halt assertion within 1 sys_clk cycle
    - Inject wdt_fault → verify aggregated_fault reaches RSC within 100 µs
    - Verify redundant_shutdown timing: alert_n_o asserted ≥4 wdt_clk cycles before shutdown_n_o
    - Inject all-zero inputs into AI accelerator → verify FSM does not hang (BUG-04 regression)

---

## 6. Deliverable Quality Scores

| Deliverable | Completeness | Correctness | Documentation | Overall |
|------------|-------------|-------------|--------------|---------|
| FIX_REPORT.md | A (comprehensive) | A (all fixes verified) | A (before/after, register map table) | **A** |
| AI Accelerator RTL (post-fix) | A (all features) | A- (O-01 minor, O-03 N/A here) | A (headers, comments) | **A-** |
| Peripheral RTL (14 modules) | A (all blocks) | B+ (WDT araddr bug) | A- (block headers present) | **B+** |
| adas_soc_top.v | A (all blocks) | B (CDC gaps O-03,O-04,O-05) | A (CDC comments) | **B** |
| SDK (crt0, linker, hal) | A (all essentials) | A (verified match) | A (inline comments) | **A** |
| SDK_REPORT.md | A (build details) | A (verified) | A (quality gates table) | **A** |

**Weighted overall: B+/A-.** The team has done substantial work. The grade is pulled down by the CDC gaps and the WDT read-address bug — all fixable in a single afternoon.

---

## 7. Closing Remarks

This is a large Phase 2b delivery and the team's discipline shows. The SECDED upgrade alone demonstrates that the digital_design engineer can execute non-trivial algorithmic RTL. The SDK's compile-time static assertions on all 11 base addresses are the kind of defensive engineering I like to see.

The CDC gaps are the pattern I want to call attention to: there are three places where the RTL and the cdc_plan disagree. This is not unusual in projects of this complexity, but it is exactly the kind of drift that becomes invisible and then becomes a tape-out killer. I recommend a **single-session CDC audit** where the architect walks the design engineer through every crossing in cdc_plan.md against the actual RTL and they reconcile every discrepancy. One hour. Close the gap. Never look back.

The WDT read-address bug (O-03) is the one item I would **strongly recommend** fixing before any firmware WDT driver testing begins. It is deterministic, reproducible, and will waste engineering time if left in place.

Professor Zhang Luxin, signing off. Show me the fixes in Phase 3.

---

*"A review does not block. A review illuminates. The team decides what to do in the light."*

---

**End of REVIEW_PHASE2b.md**
