# ADAS RISC-V v2 — High-Performance Safety-Critical SoC

**Project ID:** ADAS-V2-001
**Start Date:** 2026-04-29
**PDK:** sky130hs (high-speed variant)
**Target:** GDS with max achievable frequency
**Safety:** ASIL-D architectural patterns (learning)
**Orchestrator:** Hoshimachi Suisei 💙

## Architecture

- **Core:** RV32IM single-cycle / pipelined (target 100+ MHz)
- **AI Accelerator:** 4×4 INT8 systolic array (weight-stationary)
- **Peripherals:** SPI (LIDAR), Servo PWM (braking), Speed Sensor (tachometer), Buzzer PWM, UART (debug), GPIO (alerts)
- **Safety:** Lockstep core, ECC on critical SRAM, window watchdog, redundant shutdown path, fault detection
- **Interconnect:** AXI4-Lite

## ADAS Braking Algorithm

1. Speed sensor reads ego velocity continuously (wheel pulse counter)
2. SPI reads object distance + relative velocity from LIDAR
3. AI accelerator classifies object type (car/pedestrian/obstacle)
4. If collision threat detected (distance < threshold AND relative speed > threshold):
   - Servo PWM engages braking actuator
   - Buzzer sounds alert
5. Safety monitor shadows processor decisions — triggers redundant shutdown on mismatch

## Structure

```
adas_v2/
├── rtl/                  # RTL source files
├── tb/                   # Testbenches
├── sim/                  # Simulation results
├── scripts/              # Build scripts
├── synth/                # Synthesis results
├── firmware/             # Bare-metal firmware + SDK
├── constraints/          # SDC files
├── docs/                 # Architecture + reports
├── deliverables/         # Agent deliverables by role
└── README.md
```

## Status

| Phase | Owner | Task | Status |
|-------|-------|------|--------|
| 1 | system_engineer | SRS with ASIL-D safety requirements | ⏳ Dispatched |
| 1 | architect | Microarchitecture + block interfaces + CDC | ⏳ Dispatched |
| 1 | firmware_engineer | ADAS braking algorithm reference model | ⏳ Dispatched |
| 2 | architect + digital_design + professor | AI accelerator RTL (collaborative) | ⬜ Pending |
| 2 | digital_design | Remaining RTL blocks + top integration | ⬜ Pending |
| 2 | compiler_engineer | SDK + toolchain for RV32IM | ⬜ Pending |
| 3 | verif_lead | Comprehensive UVM/cocotb testbench — millions of cycles, 100% coverage, randomized inputs | ⬜ Pending |
| 4 | backend_lead | Synthesis + STA (pre-P&R gate) | ⬜ Pending |
| 4 | sta_engineer | Multi-corner STA signoff | ⬜ Pending |
| All | professor | Advisory review on all deliverables | ⬜ Pending |

## PRE-P&R QUALITY GATES (HOSHIYOMI DIRECTIVE)

The following must ALL pass before backend_lead starts place & route:

| # | Gate | Criterion |
|---|------|-----------|
| 1 | **Timing Slack** | Positive slack after synthesis — highest achievable without going negative |
| 2 | **Verification** | Millions of cycles with randomized inputs + UVM, ZERO faults |
| 3 | **Coverage** | 100% coverage on ALL modules |
| 4 | **Functional Equivalence** | Functionality between synthesis netlist and RTL is co-sim verified |
| 5 | **Lint** | Zero lint errors (best-effort on Verilator 4.038) |
| 6 | **Firmware** | Firmware compiles successfully and passes verification |

## COLLABORATION RULES

- **AI Accelerator:** architect, digital_design, and professor work TOGETHER
- **Bug Loop:** verif_lead → digital_design (bugs) → verif_lead (re-verify) — closed loop until zero faults
- **Professor:** advisory review on every module — recommendations only, never blocks

---

*"Safety at speed. That's the performance."* 💙
