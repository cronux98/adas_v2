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

## 📊 Physical Implementation Views

Post-route layout images generated from the final 6_final.def using OpenROAD v2.0.

| View | Image |
|------|-------|
| **Full Layout** — Complete post-route chip view with all routing layers, nets, and cells | ![Full Layout](images/layout_full.png) |
| **Placement** — Cell placement density (routing hidden, cells only) | ![Placement](images/placement.png) |
| **Congestion** — Routing layer view showing signal and power distribution | ![Congestion](images/congestion.png) |
| **Clock Tree** — Clock net distribution across the die | ![Clock Tree](images/clock_tree.png) |
