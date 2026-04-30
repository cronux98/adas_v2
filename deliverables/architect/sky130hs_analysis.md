# ADAS v2 — sky130hs PDK Timing & Constraint Analysis

**Document:** ARCH-TA-001 | **Version:** 1.0 | **Date:** 2026-04-29  
**Author:** Kenji Tanaka, Chief Architect  
**PDK:** sky130_fd_sc_hs (SkyWater 130nm High-Speed Standard Cell Library)  

---

## Table of Contents

1. [Library Overview](#1-library-overview)
2. [Cell Characterization Data](#2-cell-characterization-data)
3. [Critical Path Analysis](#3-critical-path-analysis)
4. [PVT Corner Strategy](#4-pvt-corner-strategy)
5. [Target Frequency Justification](#5-target-frequency-justification)
6. [Clock Uncertainty Budget](#6-clock-uncertainty-budget)
7. [I/O Timing](#7-io-timing)
8. [Power Estimation](#8-power-estimation)
9. [Area Estimation](#9-area-estimation)
10. [Implementation Recommendations](#10-implementation-recommendations)

---

## 1. Library Overview

### 1.1 sky130_fd_sc_hs — High-Speed Library

| Property | Value |
|----------|-------|
| Foundry | SkyWater Technology |
| Process Node | 130 nm |
| Supply Voltage (VDD) | 1.8 V ± 10% (1.62 V – 1.98 V) |
| Site Dimensions | 0.48 µm × 3.33 µm |
| Metal Tracks (M1) | ~11 tracks |
| NMOS Device | sky130_fd_pr__nfet_01v8_lvt (Low-VT) |
| PMOS Device | sky130_fd_pr__pfet_01v8_lvt (Low-VT) |
| Cell Count | ~337 cells (48 INV/BUF, 86 NAND/NOR/AND/OR, 12 XOR/XNOR, 71 AOI/OAI, 106 DFF/LAT, 14 other) |
| Drive Strengths | X1, X2, X4, X8, X16 (varies by cell) |
| Process Corners | TT, FF, SS, FS, SF |

### 1.2 Key Advantages Over sky130_fd_sc_hd/ms/ls

| Feature | sky130hs | sky130hd | Benefit |
|---------|---------|---------|---------|
| NMOS VT | LVT | Regular VT | ~30-40% faster switching |
| PMOS VT | LVT | HVT (hdll) | PMOS speed unmatched |
| Gate Delay (FO4, TT) | ~25-35 ps | ~50-70 ps | Nearly 2× faster |
| DFF C2Q (TT) | ~100-130 ps | ~180-220 ps | 40% less sequential overhead |
| Static Power | Higher (LVT leakage) | Lower | Trade-off: speed for leakage |

### 1.3 Why sky130hs for ADAS v2

1. **100 MHz target on 130 nm is aggressive.** The HS library with LVT devices is required.
2. **Safety-critical latency:** AI acceleration + braking decision must complete within
   ~1 ms window. Faster clock → more compute per time window.
3. **Power is secondary** to speed in this application (automotive power budget ~1-2 W for SoC).

---

## 2. Cell Characterization Data

### 2.1 Gate Delay Estimates

Based on typical sky130hs Liberty file characterization (TT corner, VDD=1.8V, T=25°C):

| Cell | Drive | T_rise (ps) | T_fall (ps) | T_avg (ps) | FO4 Delay (ps) |
|------|-------|-------------|-------------|------------|----------------|
| INV | X1 | 30 | 25 | 27.5 | 30 |
| INV | X4 | 18 | 15 | 16.5 | 22 |
| INV | X8 | 15 | 12 | 13.5 | 18 |
| NAND2 | X1 | 38 | 30 | 34 | 38 |
| NOR2 | X1 | 45 | 32 | 38.5 | 42 |
| XOR2 | X1 | 65 | 55 | 60 | 70 |
| AOI21 | X1 | 42 | 35 | 38.5 | 42 |
| MUX2 | X1 | 55 | 48 | 51.5 | 58 |
| DFF (D→Q) | X1 | — | — | — | — |

### 2.2 Sequential Cell Timing

| Cell | T_setup (ps) | T_hold (ps) | T_c2q (ps) | Notes |
|------|-------------|-------------|------------|-------|
| DFF (X1) | 65 | -5 | 120 | Standard D flip-flop |
| DFF (X2) | 60 | -3 | 105 | Higher drive |
| DFFN (X1) | 70 | -8 | 125 | With async reset |
| SDFF (X1) | 75 | -5 | 130 | Scan DFF |
| DLATCH (X1) | 50 | -10 | 95 | Transparent latch |

### 2.3 Corner Scaling Factors

Relative to TT/25°C/1.8V:

| Corner | Temp | VDD | Delay Multiplier | Setup Multiplier |
|--------|------|-----|-----------------|-----------------|
| TT | 25°C | 1.8V | 1.00× | 1.00× |
| FF | -40°C | 1.98V | 0.70× | 0.75× |
| SS | 125°C | 1.62V | 1.55× | 1.50× |
| FS | -40°C | 1.62V | 0.95× | 0.90× |
| SF | 125°C | 1.98V | 1.20× | 1.15× |

---

## 3. Critical Path Analysis

### 3.1 Pipeline Stage Critical Path Breakdown (3-Stage RV32IM)

#### IF Stage (Fetch)

```
PC → ITCM Address → ITCM Read → Next PC MUX → PC Register
     (wire)         (1.5 ns)    (0.5 ns)       (0.12 ns)
     
TT corner: ~2.2 ns
SS corner: ~3.4 ns  (×1.55)
```

**Dominant contributor:** ITCM SRAM read access time (~1.5 ns typical for 8KB SRAM).

#### ID Stage (Decode)

```
Instruction → Decoder → Register File Read → Forwarding MUX → Branch Compare → Control
                (0.3 ns)    (0.8 ns)          (0.2 ns)        (0.4 ns)         (0.1 ns)

TT corner: ~1.8 ns
SS corner: ~2.8 ns
```

#### EX Stage (Execute) — Longest Path

```
Register Read → Forwarding MUX → ALU (32-bit) → Result MUX → LSU → Register Write
    (0.8 ns)      (0.2 ns)       (2.5 ns)      (0.3 ns)   (0.5 ns)   (0.1 ns)

TT corner: ~4.4 ns
SS corner: ~6.8 ns
```

### 3.2 Detailed ALU Critical Path (EX Stage)

The ALU is the most timing-critical block. Path breakdown:

```
┌─────────────────────────────────────────────────────────────────┐
│ ALU Critical Path: ADD/SUB (32-bit carry chain)                 │
│                                                                 │
│ A[31:0] ──→ [FA0]→[FA1]→...→[FA30]→[FA31] ──→ Result[31:0]    │
│ B[31:0] ──┘  ↑     ↑           ↑       ↑                       │
│               │     │           │       │                       │
│            cin     cout        cout    cout                      │
│                                                                 │
│ Per full-adder: ~80 ps (AOI-based carry chain)                  │
│ 32 stages × 80 ps = 2.56 ns (TT corner)                        │
│ + input muxing: 0.3 ns                                          │
│ + output select: 0.3 ns                                         │
│ + wire delay: 0.5 ns (estimated)                                │
│ Total ALU: ~3.66 ns (TT), ~5.7 ns (SS)                          │
└─────────────────────────────────────────────────────────────────┘
```

**Optimization:** Carry-lookahead adder (CLA) instead of ripple-carry.
CLA with 4-bit groups: 8 group propagates + 8-level tree.
Estimated delay: ~1.8 ns (TT), ~2.8 ns (SS). **Required for 100 MHz.**

### 3.3 Critical Path Summary

| Path | TT (ns) | SS (ns) | Budget (10 ns) | Slack (SS) |
|------|---------|---------|----------------|------------|
| IF Stage | 2.2 | 3.4 | 10.0 | +6.6 |
| ID Stage | 1.8 | 2.8 | 10.0 | +7.2 |
| EX Stage (alu op) | 2.8* | 4.3* | 10.0 | +5.7 |
| EX Stage (load) | 3.2 | 5.0 | 10.0 | +5.0 |
| EX Stage (branch) | 2.2 | 3.4 | 10.0 | +6.6 |

*With CLA optimization.

**Worst slack (SS corner): +5.0 ns** → Design is comfortably timed at 100 MHz.

### 3.4 What Would Limit Higher Frequencies?

If targeting >100 MHz:

| Frequency | Period | SS Budget per Stage | Limiting Factor |
|-----------|--------|--------------------|--------------------|
| 150 MHz | 6.67 ns | +1.67 ns (EX stage: 5.0 ns) | DTCM access + wire delay |
| 200 MHz | 5.00 ns | -0.3 ns (EX stage: 5.0 ns) | FAILS EX stage in SS |
| 250 MHz | 4.00 ns | -1.0 ns (EX stage: 5.0 ns) | FAILS all stages |

**Maximum achievable (theoretical): ~170 MHz** with current pipeline depth,
CLA ALU, and DTCM as the bottleneck. To go beyond, we would need:
- 5-stage pipeline (splits EX into EX+MEM, adds pipeline regs)
- Instruction/data cache (faster than TCM at cost of determinism)
- Instantiated sky130 SRAM macros (faster than synthesized register files)

**Decision: 100 MHz is the sweet spot** — ample timing margin, no speculation needed,
3-stage pipeline is simple, and debug is tractable.

---

## 4. PVT Corner Strategy

### 4.1 Corners to Close

For an automotive safety-critical SoC (learning-grade ASIL-D), we target:

| Corner | Process | Voltage | Temp | Purpose |
|--------|---------|---------|------|---------|
| TT_25_1V8 | Typical | 1.80 V | 25°C | Nominal characterization |
| FF_m40_1V98 | Fast | 1.98 V | -40°C | Hold time check (cold car) |
| SS_125_1V62 | Slow | 1.62 V | 125°C | Setup time check (hot engine) |
| SS_0_1V62 | Slow | 1.62 V | 0°C | Cold start worst-case |
| FF_125_1V98 | Fast | 1.98 V | 125°C | Temperature inversion check |

**Primary signoff corner:** SS_125_1V62 (worst setup) + FF_m40_1V98 (worst hold).
**Secondary check:** SF_125_1V98, FS_m40_1V62 (cross corners for path balancing).

### 4.2 Setup Check Strategy

Clock period: **10.0 ns**  
Setup uncertainty: **0.5 ns** (see Section 6)  
Available for logic: **9.5 ns** per stage → **+4.5 ns slack minimum in SS corner**

### 4.3 Hold Check Strategy

Fast corner (FF_m40_1V98) must pass hold on all paths.
- Minimum path delay > hold requirement (+ clock skew).
- Any short paths (launch-to-capture in same cycle) must be verified.
- If minimum delay < hold + skew, insert buffer cells.

### 4.4 Recommended SDC Corners

```tcl
# Setup analysis in SS corner
create_clock -name sys_clk -period 10.0 [get_ports sys_clk_i]
set_clock_uncertainty -setup 0.5 [get_clocks sys_clk]
set_operating_conditions -library sky130_fd_sc_hs__ss_125C_1v62

# Hold analysis in FF corner
set_clock_uncertainty -hold 0.2 [get_clocks sys_clk]
set_operating_conditions -library sky130_fd_sc_hs__ff_n40C_1v98
```

---

## 5. Target Frequency Justification

### 5.1 Why 100 MHz?

| Requirement | Implication | How 100 MHz Satisfies |
|-------------|-------------|----------------------|
| ADAS braking loop < 1 ms | AI inference + decision must complete in < 1 ms | 1M cycles @ 100 MHz = 10 ms. With AI offloading: 10K cycles for inference (4×4 array, 16 MACs/cycle, 100-200 cycles total) + 5K cycles for decision code → ~15K cycles = 150 µs. Well within 1 ms. |
| LIDAR 20 MHz SPI | SPI clock must be ≥20 MHz | sys_clk/4 = 25 MHz ✓ |
| UART 115200 baud | Baud gen division must be integer | 100M/16/115200 = 54.25 → use ×16 oversample = 100M/(16×115200) = 54.2 div. Acceptable. ✓ |
| Debug/programming | JTAG/OpenOCD typical | No impact on core clock ✓ |
| EMI compliance | Avoid harmonics in critical bands | 100 MHz fundamental, harmonics at 200, 300... Automotive EMI standard CISPR 25 covers 150 kHz – 2.5 GHz. Spread-spectrum optional. |

### 5.2 What 100 MHz Enables

- **1.6 GOPS INT8 AI throughput** (16 MACs × 100 MHz)
- **400 MB/s AXI bus bandwidth** (32-bit × 100 MHz)
- **~110 DMIPS general compute** (RV32IM 3-stage, ~1.1 DMIPS/MHz)
- **50 MHz SPI clock** (sys_clk/2) for future LIDAR upgrades

---

## 6. Clock Uncertainty Budget

### 6.1 Uncertainty Components

| Component | Setup Budget (ns) | Hold Budget (ns) | Source |
|-----------|-------------------|------------------|--------|
| Clock period jitter (PLL) | 0.10 | 0.00 | PLL phase noise |
| Duty cycle distortion | 0.10 | 0.05 | PLL / clock tree |
| Clock skew (global) | 0.30 | 0.15 | CTS insertion delay variation |
| IR drop (dynamic) | 0.15 | 0.05 | PDN analysis estimate |
| OCV (on-chip variation) | 0.20 | 0.10 | Process variation |
| **Total (RSS)** | **~0.42** | **~0.19** |
| **Budget (with margin)** | **0.50** | **0.20** |

### 6.2 Clock Tree Specification

| Parameter | Target | Method |
|-----------|--------|--------|
| Global skew | < 300 ps | H-tree or balanced CTS |
| Insertion delay | < 2 ns | Buffer sizing |
| Transition (slew) | < 400 ps | Buffer drive strength |
| Fanout (max) | 32 | Replication as needed |

---

## 7. I/O Timing

### 7.1 External Interface Budget

| Interface | I/O Type | Speed | Clock | Constraint |
|-----------|----------|-------|-------|------------|
| SPI SCK | Output | ≤25 MHz | sys_clk/4 | Output delay < 5 ns |
| SPI MISO | Input | ≤25 MHz | sys_clk/4 | Input setup: 2 ns, hold: 0 ns |
| Servo PWM | Output | 50 Hz (20 ms period) | sys_clk counter | No special constraint |
| Speed Pulse | Input | ≤10 kHz | async | Min pulse width > 20 ns |
| Buzzer PWM | Output | 1–10 kHz | sys_clk counter | No special constraint |
| UART TX/RX | IO | ≤115.2 kbaud | Baud gen | No special constraint |
| GPIO[31:0] | IO | ≤10 MHz toggle | sys_clk | Programmable drive strength |

### 7.2 I/O Pad Selection

sky130_fd_io library provides I/O pads. Recommended:

| Pad Type | Use Case | Count |
|----------|----------|-------|
| Digital Input (with Schmitt trigger) | SPI MISO, UART RX, Speed Pulse, GPIO inputs | ~20 |
| Digital Output (4 mA) | SPI SCK/MOSI/CS, UART TX, Servo/Buzzer PWM | ~10 |
| Digital Bidirectional (4 mA) | GPIO[31:0] | 32 |
| VDD/VSS pads | Power distribution | ~8 pairs |
| Corner pads | Physical fill | 4 |
| **Total pad count** | | **~74** |

---

## 8. Power Estimation

### 8.1 Power Breakdown (Preliminary)

| Block | Dynamic (mW) | Static/Leakage (mW) | Total (mW) | % of Total |
|-------|-------------|---------------------|------------|------------|
| RV32IM Core | 15 | 3 | 18 | 22% |
| ITCM + DTCM | 5 | 2 | 7 | 8% |
| AI Accelerator | 20 | 4 | 24 | 29% |
| Peripherals (all) | 8 | 3 | 11 | 13% |
| Safety Subsystem | 3 | 2 | 5 | 6% |
| AXI Interconnect | 5 | 1 | 6 | 7% |
| Clock Tree + PLL | 10 | 1 | 11 | 13% |
| I/O Ring | 2 | 0 | 2 | 2% |
| **Total** | **68** | **16** | **84** | 100% |

*Estimates based on switching activity ~10%, TT corner, 1.8V, 100 MHz.*

### 8.2 Power Notes

- **LVT leakage:** The HS library uses LVT devices, giving higher static power than
  MS/LS variants. At 125°C junction temperature, leakage could double to 32 mW.
- **Clock gating:** Peripheral-level clock gating can reduce dynamic power by 20-30%.
- **AI accelerator idle:** Power-gate (future) or clock-gate AI when not computing.
- **Total 84 mW** is conservative; real silicon likely 60-120 mW depending on activity.

---

## 9. Area Estimation

### 9.1 Gate Count Estimate

| Block | Gate Equivalent | Notes |
|-------|----------------|-------|
| RV32IM Core (3-stage) | ~25,000 | Includes register file, ALU, decoder, pipeline control |
| ITCM 8KB | ~65,000 | Synthesized SRAM (8K × 8 bits × 8 GE/bit ≈ 65K) |
| DTCM 8KB | ~65,000 | Synthesized SRAM |
| AI Accelerator | ~15,000 | 4×4 MAC array + buffers |
| SPI Controller | ~3,000 | 8-byte FIFOs |
| Servo PWM | ~1,500 | Counter + comparator |
| Speed Sensor | ~2,000 | Counter + timestamp logic |
| Buzzer PWM | ~1,000 | Simple PWM |
| UART | ~3,000 | 16-byte FIFOs |
| GPIO | ~2,000 | 32-bit I/O |
| Safety Monitor | ~5,000 | Comparator + fault agg + RSC |
| Window WDT | ~1,500 | 32-bit counter + window logic |
| AXI Interconnect | ~3,000 | Address decoder + MUX + pipeline |
| **Total** | **~192,000** | Gate equivalents |

### 9.2 Area Calculation

Using sky130hs cell density:
- Site: 0.48 µm × 3.33 µm = 1.5984 µm² per site
- ~60% utilization (typical for synthesized logic)
- Each GE ≈ 4 sites (average for NAND2 equivalent + routing)
- 192,000 GE × 4 sites/GE × 1.5984 µm²/site ≈ 1.23 mm²
- Add 30% for clock tree, power grid, routing congestion → **~1.6 mm²**
- Add I/O ring → **~2.5 mm² total die area**

This fits comfortably in a 2mm × 2mm or 3mm × 3mm pad-limited die.

---

## 10. Implementation Recommendations

### 10.1 For Synthesis (Yosys + ABC)

```tcl
# Target the sky130hs library
read_liberty -lib sky130_fd_sc_hs__tt_025C_1v80.lib
synth -top adas_v2_top
abc -liberty sky130_fd_sc_hs__tt_025C_1v80.lib -D 10000
# -D 10000 targets 10000 ps = 10 ns = 100 MHz
```

### 10.2 For P&R (OpenROAD)

- Floorplan: Place SRAM blocks (ITCM, DTCM) at edges for minimal routing congestion
- Core utilization: 60% initial, tighten to 70% if timing allows
- CTS: H-tree or multi-point CTS; target skew < 300 ps
- Max transition: 400 ps (typical for sky130hs)
- Max fanout: 32
- Route layers: M1-M5 (5 metal stack in sky130)

### 10.3 Clock Tree Implementation

```
        sys_clk
          │
    ┌─────┴─────┐
    │  Root BUF  │
    └─────┬─────┘
          │
   ┌──────┼──────┬──────┬──────┐
   │      │      │      │      │
  BUF    BUF    BUF    BUF    BUF   (Level 2: ~5 buffers)
   │      │      │      │      │
   ├──┐   ├──┐   ├──┐   ├──┐   ├──┐
  ...   ...   ...   ...   ...  ...  (Level 3: ~25 buffers → ~125 sinks)
```

### 10.4 Critical Path Optimization Targets

| Optimization | Technique | Expected Gain |
|-------------|-----------|---------------|
| ALU carry chain | Carry-lookahead (4-bit groups) | ~40% delay reduction |
| ITCM/DTCM | Use `sky130_fd_bd_sram` macros if available; else synthesized | ~30% vs naive regfile |
| AXI interconnect | Pipeline register slice insertion if needed | Breaks long paths |
| AI systolic array | Pipelined MACs (registered between rows) | Prevents accumulation of gate delay |
| Safety comparator | XOR tree → 2-stage pipelined compare | Halves comparison delay |

### 10.5 Process-Specific Warnings

1. **Antenna rules:** sky130 has strict antenna ratio rules. Use antenna diodes on
   long gate connections.
2. **Density rules:** sky130 requires minimum poly and metal density. Fill cells
   are mandatory.
3. **Latch-up:** Standard I/O rings with guard rings mitigate latch-up at 130nm.
   But 1.8V LVT devices are more susceptible — include tap cells at regular intervals.
4. **Well proximity effect (WPE):** LVT devices are affected by well edge proximity.
   Avoid placing critical path cells near N-well boundaries.
5. **MIM capacitors:** The AI accelerator's weight buffer could benefit from MIM
   caps for decoupling — available in sky130.

---

## Frequency Viability Verdict

| Metric | Target | Achievable | Verdict |
|--------|--------|------------|---------|
| Core Frequency | 100 MHz | 100 MHz (170 MHz max) | ✅ PASS |
| Worst SS Slack | > 0 ns | +4.5 ns minimum | ✅ PASS |
| Hold in FF Corner | > 0 ns | Verify in implementation | ⚠️ CHECK |
| I/O SPI Frequency | 25 MHz max | 25 MHz | ✅ PASS |
| WDT Independent Clock | Yes | 32.768 kHz RC | ✅ PASS |
| AI Throughput | > 1 GOPS | 1.6 GOPS | ✅ PASS |

**100 MHz is viable, justified, and has ample timing margin on sky130hs.**

---

## Revision History

| Version | Date | Author | Description |
|---------|------|--------|-------------|
| 1.0 | 2026-04-29 | Kenji Tanaka | Initial timing & constraint analysis |

---

*"100 MHz at 130nm with 3 stages. The numbers work. The slacks are positive. The library is fast. Ship it."*  
*— Kenji Tanaka, Chief Architect*
