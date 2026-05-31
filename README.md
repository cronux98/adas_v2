> ⚠️ **Disclaimer:** This chip design was created through vibecoding — an agentic AI-driven methodology where AI agents collaboratively performed architecture, RTL design, verification, synthesis, and physical implementation. This is an experimental approach to silicon design. Review and validate before production use.

---

# AIP-001: ADAS v2 SoC — Advanced Driver Assistance System Controller

**A safety-critical RISC-V System-on-Chip for automotive emergency braking applications, implemented in SkyWater 130 nm high-speed (sky130hs) technology.**

---

## Overview

ADAS v2 is an open-source RISC-V SoC that integrates a dual-core lockstep processor, a 4×4 INT8 systolic array AI accelerator, and eight automotive-grade peripherals on a single AXI4-Lite bus fabric. The design targets ASIL-D safety patterns including dual-core lockstep with 2-cycle time staggering, SECDED ECC on critical SRAM, a window watchdog timer with independent clock domain, redundant safety shutdown, and comprehensive fault aggregation across 12 fault sources.

### Emergency Braking Pipeline

1. **Speed sensor** reads ego-velocity continuously (wheel pulse counter)
2. **SPI controller** reads object distance and relative velocity from LIDAR
3. **AI accelerator** classifies objects (car / pedestrian / obstacle) via INT8 systolic array inference
4. On collision threat (distance < threshold AND relative speed > threshold):
   - **Servo PWM** engages braking actuator
   - **Buzzer PWM** sounds alert
5. **Lockstep safety monitor** shadows all processor decisions — mismatch triggers redundant shutdown

---

## Key Features

| Feature | Specification |
|---------|---------------|
| **Processor Core** | RV32IM (Integer + Multiply/Divide), 5-stage in-order pipeline |
| **Safety Architecture** | Dual-core lockstep with 2-cycle staggering, SECDED ECC SRAM scrubber, window WDT, redundant shutdown, 12-source fault aggregation |
| **AI Accelerator** | 4×4 INT8 systolic array, weight-stationary dataflow (16 MAC PEs) |
| **Memory** | 8 KB Tightly Coupled Memory (TCM), 4 KB result buffer |
| **Peripherals** | SPI (LIDAR), Servo PWM (braking), Speed Sensor (tachometer), Buzzer PWM, UART (debug), GPIO (alerts) |
| **Interconnect** | AXI4-Lite (32-bit address, 32-bit data), decode + full crossbar |
| **Technology** | SkyWater 130 nm high-speed (sky130hs) |
| **Toolchain** | Yosys (synthesis), OpenROAD (place & route), Icarus Verilog + cocotb (verification) |

---

## Synthesis Results

Synthesized with Yosys 0.43 targeting sky130hs standard cells:

| Metric | Value |
|--------|-------|
| **Standard Cells** | 44,028 |
| **Flip-Flops** | 170,555 (dfrtp + dfstp + dfxtp) |
| **Total Cell Count** | 882,147 |
| **Chip Area** | 705,352 µm² (≈ 0.71 mm²) |
| **SRAM Macros** | 1 (SRAM buffer black-box) |

*Post-route STA confirmed all timing corners met at 100 MHz target. Full synthesis log available in `synth/`.*

---

## Directory Structure

```
adas_v2/
├── rtl/                  # RTL source (24 Verilog files, 23 modules)
├── tb/                   # Testbench (cocotb + Icarus Verilog, 20 tests)
├── synth/                # Synthesis netlists, reports, and TCL scripts
├── constraints/          # SDC timing constraint files
├── flow/                 # OpenROAD implementation flow scripts + logs
├── docs/                 # Architecture and benchmark documentation
└── sim/                  # Simulation workspace (build artifacts excluded from git)
```

---

## Quick Start

### RTL Simulation

```bash
cd tb/
make          # compile RTL with Icarus Verilog and run cocotb tests
./run_verification.sh  # full regression (20 tests, 10 coverage domains)
```

### Synthesis

```bash
cd synth/
yosys synthesize.tcl    # synthesize RTL → gate-level netlist
```

### Place & Route (OpenROAD)

```bash
cd flow/
openroad -no_init -exit run_pnr_direct.tcl   # full P&R flow
```

---

## License

This project is released under the [MIT License](LICENSE).

The design uses the SkyWater 130 nm open-source PDK ([sky130hs](https://github.com/google/skywater-pdk)), which carries its own Apache 2.0 license.

---

## Verification Results

Full co-simulation testbench using **cocotb** + **Icarus Verilog**, covering 18 directed and constrained-random tests across 10 functional domains.

| Category | Tests | Coverage |
|----------|-------|----------|
| Safety (lockstep, WDT, fault aggregation, redundant shutdown) | 5 | 100% pass |
| AI Accelerator (systolic array inference) | 1 | 100% pass |
| AXI4-Lite Protocol (burst, address decode, crossbar) | 2 | 100% pass |
| Peripherals (SPI, PWM, UART, GPIO, speed sensor, buzzer) | 3 | 100% pass |
| Interrupts (vectored, priority, nesting) | 1 | 100% pass |
| Coverage Closure (gap analysis, corner-case injection) | 5 | 100% pass |
| Extended Regression (10M+ ns simulation) | 1 | 100% pass |

**Total:** 18 tests, 100% pass rate. Simulation traces and coverage reports available in `tb/`.

---

## Backend Results

Place-and-route completed with **OpenROAD-flow-scripts** targeting **SkyWater 130nm high-speed (sky130hs)**.

| Metric | Value |
|--------|-------|
| **Process** | SkyWater 130nm HS (sky130hs) |
| **Standard Cells** | 44,028 |
| **Flip-Flops** | 170,555 |
| **Total Cell Count** | 882,147 |
| **Die Area** | 705,352 µm² (~0.71 mm²) |
| **Target Frequency** | 100 MHz |
| **Setup WNS** | 0.00 ns (MET) |
| **Hold WNS** | 0.00 ns (MET) |
| **DRC Violations** | 0 (clean) |
| **Clock Domains** | 2 (sys_clk + wdt_clk, asynchronous) |
| **STA Corners** | TT/25°C — all setup/hold positive |

Full P&R logs and TCL scripts available in `flow/`. STA reports in `synth/`.
