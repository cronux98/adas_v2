# ADAS v2 — Comprehensive Verification Plan

**Document:** VER-PLAN-001 | **Version:** 1.0 | **Date:** 2026-04-29  
**Author:** Rahul Sharma, Verification Lead  
**Project:** adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC  
**PDK:** sky130_fd_sc_hs (SkyWater 130nm High-Speed)  
**Target:** 100% coverage, ZERO faults at P&R gate  

---

## Table of Contents

1. [Verification Strategy Overview](#1-verification-strategy-overview)
2. [Module-Level Verification Plans](#2-module-level-verification-plans)
3. [Integration-Level Verification Plans](#3-integration-level-verification-plans)
4. [System-Level Verification Plans](#4-system-level-verification-plans)
5. [Safety Verification Plans](#5-safety-verification-plans)
6. [Randomized Test Strategy](#6-randomized-test-strategy)
7. [Golden Reference Comparison](#7-golden-reference-comparison)
8. [Resource Estimates and Schedule](#8-resource-estimates-and-schedule)
9. [Verification Closure Criteria](#9-verification-closure-criteria)

---

## 1. Verification Strategy Overview

### 1.1 Verification Philosophy

*"Millions of cycles. Random stimulus. Golden reference. Zero faults."*

This verification framework is built on four pillars:

| Pillar | Description | Coverage |
|--------|-------------|----------|
| **Directed Tests** | Hand-crafted test vectors for edge cases, spec compliance, safety boundaries | Mandated by SRS REQ edges |
| **Constrained Random** | Randomized stimulus within valid ranges; millions of cycles | 90%+ functional coverage |
| **Golden Reference** | Python model vs. RTL comparison for every module with algorithmic behavior | Ensures algorithmic correctness |
| **Fault Injection** | Active fault insertion for all safety blocks | ASIL-D diagnostic coverage |

### 1.2 Verification Flow

```
┌────────────┐    ┌────────────┐    ┌─────────────┐    ┌──────────────┐
│  Directed  │───→│ Constrained│───→│  Coverage   │───→│   CLOSURE    │
│  Tests     │    │  Random    │    │  Collection │    │   (100%)     │
│  (Week 1)  │    │  (Week 2+) │    │  (Continuous)│   │              │
└────────────┘    └────────────┘    └─────────────┘    └──────────────┘
       │                │                  │                   │
       │         ┌──────┴──────┐          │                   │
       │         │  Fault      │          │                   │
       │         │  Injection  │──────────┘                   │
       │         │  (Safety)   │                              │
       │         └─────────────┘                              │
       │                                                      │
       └────────── ALL ──→ Bug Reports → digital_design ──────┘
                                                     │
                                          Fix → re-run → zero faults
```

### 1.3 Module Inventory and Verification Priority

| Priority | Module | Type | SRS Coverage | ASIL | Verification Intensity |
|----------|--------|------|-------------|------|----------------------|
| CRIT-1 | `rv32im_core` | CPU | REQ-001, REQ-011 | D | Maximum — lockstep + full ISA |
| CRIT-2 | `safety_monitor` | Safety | REQ-011, REQ-014, REQ-015 | D | Maximum — formal + injection |
| CRIT-3 | `window_wdt` | Safety | REQ-013 | D | Maximum — independent clock |
| CRIT-4 | `redundant_shutdown_ctrl` | Safety | REQ-014 | D | Maximum — combinatorial path |
| HIGH-1 | `ai_accel_4x4` | Accelerator | REQ-002 | D | Heavy — golden ref for every MAC |
| HIGH-2 | `spi_master` | Peripheral | REQ-003, REQ-018 | D | Heavy — protocol compliance |
| HIGH-3 | `speed_sensor` | Peripheral | REQ-004 | D | Heavy — timing + stuck-at |
| HIGH-4 | `servo_pwm` | Peripheral | REQ-005, REQ-019 | D | Heavy — PWM accuracy |
| MED-1 | `buzzer_pwm` | Peripheral | REQ-006, REQ-019 | D | Moderate |
| MED-2 | `gpio_32bit` | Peripheral | REQ-008 | B | Moderate |
| MED-3 | `tcm_8kb` (×2) | Memory | REQ-012 | D | Heavy — ECC + parity |
| MED-4 | `axi4lite_xbar_1m_9s` | Interconnect | REQ-009 | D | Heavy — combinatorial delay |
| LOW-1 | `uart_16550` | Peripheral | REQ-007 | QM | Standard |
| TOP | `adas_v2_top` | System | REQ-010, REQ-016, REQ-017 | D | Maximum — end-to-end scenarios |

---

## 2. Module-Level Verification Plans

### 2.1 AI Accelerator (`ai_accel_4x4`)

**Reference:** `microarchitecture_spec.md` §6, `REGISTER_MAP.md` §2, `reference_model.py`

#### 2.1.1 Test Categories

| Category | Tests | Cycles (est.) |
|----------|-------|---------------|
| Register R/W | All 17 registers: read-back after write, reset values, reserved bits | 1,000 |
| Weight Loading | 4 weight registers (256 combinations of INT8 values) | 5,000 |
| Input Loading | Input register — all 256 INT8 corners | 1,000 |
| Matrix Multiply | All combinations: 4×4 weight × 4 input = exhaustive | 65,536 |
| Bias Addition | 4 biases, INT16 range; 256 random samples | 1,000 |
| Activation Functions | ReLU, Sigmoid, TanH, None × 256 inputs each | 2,000 |
| Output Scaling | Q8.8 scaling factor; edge cases | 500 |
| Control FSM | GO, BUSY, DONE, ERROR sequencing | 2,000 |
| Error Conditions | Underflow, overflow, invalid config | 1,000 |
| Interrupt Handling | DONE, ERROR interrupts; mask/unmask | 500 |
| Clock Gating | CLK_EN = 0; verify no operation | 500 |
| Software Reset | SOFT_RST; verify state after reset | 500 |

**Total directed cycles:** ~80,000  
**Randomized cycles target:** 1,000,000 (random INT8 inputs, random weights, random biases, random activation configs)  
**Golden reference:** Every matrix multiply result compared against `reference_model.py` (NumPy equivalent)

#### 2.1.2 Key Verification Points

1. **All 256³ weight combinations** (exhaustive for 4 weights × 1 input = 4×4 MAC)
   - Golden: Python integer matrix multiply `W @ a + b`
   - Verify: INT32 output register values to bit-level precision
2. **Saturation behavior**: INT32 overflow at edges
3. **ReLU**: `max(0, x)` correct for every INT32 value
4. **Sigmoid/TanH**: LUT-based approximation within ±1 LSB of reference
5. **GO self-clear**: Verify GO bit auto-clears after launch
6. **BUSY timing**: BUSY asserted for exactly 16 cycles for a 4×4 array
7. **Concurrent access**: Read during computation; verify no data corruption

#### 2.1.3 SRS Traceability

| SRS Requirement | Verification |
|----------------|-------------|
| REQ-002: 4×4 INT8, 1 MAC/cycle | Throughput test: 1 result per cycle after pipeline fill |

---

### 2.2 SPI Controller (`spi_master`)

**Reference:** `microarchitecture_spec.md` §7, `REGISTER_MAP.md` §3, SRS REQ-003, REQ-018

#### 2.2.1 Test Categories

| Category | Tests | Cycles |
|----------|-------|--------|
| Register access | All 10 registers; reset values, read-back, reserved bits | 500 |
| Clock divider | All valid divider values (2–256); verify SCK frequency | 2,000 |
| SPI Modes | Mode 0 (CPOL=0, CPHA=0), Mode 3 (CPOL=1, CPHA=1) | 2,000 |
| Frame size | 8-bit fixed; verify all 256 byte values sent/received | 1,000 |
| TX FIFO | Fill, drain, overflow, underflow, count, clear | 2,000 |
| RX FIFO | Fill, drain, overflow, underflow, count, clear | 2,000 |
| Multi-byte xfer | 2–256 consecutive bytes; back-to-back transactions | 5,000 |
| Chip Select | CS assertion timing, one-hot, AUTO_CS vs manual | 1,000 |
| Interrupts | RX_AVAILABLE, TX_EMPTY, ERROR, TX_COMPLETE; mask/unmask | 1,000 |
| Error injection | Mode fault, RX overflow; verify ERROR IRQ and fault_o | 1,000 |
| Clock gating | CLK_EN = 0; verify no SCK/transactions | 500 |
| Software reset | SOFT_RST; verify clean state | 500 |
| LIDAR frame format | 32-bit frames with CRC-8 verification | 5,000 |

**Total directed cycles:** ~23,000  
**Randomized cycles target:** 2,000,000 (random SPI frames, random dividers, random data, random timing between bytes)  
**Golden reference:** SPI protocol checker (cocotb BFM) comparing sent/received bytes; CRC-8 validation

#### 2.2.2 SRS Traceability

| SRS Requirement | Verification |
|----------------|-------------|
| REQ-003: Mode 0, up to 25 MHz, 100 Hz rate | Sustained throughput test |
| REQ-018: CRC-8 on frames, 1.8V LVCMOS | Protocol compliance check |

---

### 2.3 Servo PWM (`servo_pwm`)

**Reference:** `microarchitecture_spec.md` §8, `REGISTER_MAP.md` §4, SRS REQ-005, REQ-019

#### 2.3.1 Test Categories

| Category | Tests | Cycles |
|----------|-------|--------|
| Register access | All 10 registers; reset values, R/W, reserved | 500 |
| Period configuration | All valid periods (5ms, 10ms, 20ms, 50ms) | 2,000 |
| Duty cycle (cycles mode) | 50,000 to 250,000 cycles; 100 samples across range | 5,000 |
| Duty cycle (µs mode) | 500 to 2500 µs; 100 samples across range | 5,000 |
| Glitch-free transitions | Change duty mid-cycle; verify no glitches on pwm_o | 2,000 |
| Safe mode | SAFE_MODE = 1; verify output = SERVO_SAFE_DUTY | 1,000 |
| Fault detection | Readback compare; stuck-at high, stuck-at low | 2,000 |
| Fault action | FAULT_ACTION = 0 (go safe) vs 1 (disable) | 1,000 |
| Fault debounce | FAULT_LIMIT cycles before fault assert | 1,000 |
| Interrupts | FAULT, PERIOD_DONE; mask/unmask | 1,000 |
| Safety shutdown | Assert aggregated_fault; verify pwm_o goes to safe within 1ms | 1,000 |
| Clock gating | CLK_EN = 0; verify no output | 500 |
| Software reset | SOFT_RST; verify clean state | 500 |

**Total directed cycles:** ~23,500  
**Randomized cycles target:** 1,000,000 (random period/duty changes, mid-cycle updates)  
**Golden reference:** Python PWM model; duty cycle accuracy ±1 µs tested at multiple PVT sim points

---

### 2.4 Speed Sensor (`speed_sensor`)

**Reference:** `microarchitecture_spec.md` §9, `REGISTER_MAP.md` §5, SRS REQ-004

#### 2.4.1 Test Categories

| Category | Tests | Cycles |
|----------|-------|--------|
| Register access | All registers; reset, R/W, read-only | 500 |
| Pulse counting | 0–10,000 pulses; verify COUNT matches | 5,000 |
| Timestamp capture | Verify 64-bit timestamp on each pulse edge | 5,000 |
| Period measurement | Period between consecutive pulses; SPEED_PERIOD accuracy | 5,000 |
| Overflow handling | COUNT overflow; verify COUNT_OVF status + IRQ | 1,000 |
| Glitch filter | Pulses < 100 ns rejected; ≥ 100 ns accepted | 2,000 |
| Stuck detection | No pulse within STUCK_TIMEOUT → SENSOR_STUCK | 1,000 |
| Stuck action | STUCK_ACTION = 0 (IRQ only) vs 1 (IRQ + fault) | 500 |
| Interrupts | PULSE_DETECTED, COUNT_OVF, SENSOR_STUCK; masks | 1,000 |
| Clock gating | CLK_EN = 0; verify no counting | 500 |
| Software reset | SOFT_RST; counters/timestamps cleared | 500 |

**Total directed cycles:** ~22,000  
**Randomized cycles target:** 1,000,000 (random pulse intervals, random glitch injection)  
**Golden reference:** Python model for speed computation from pulse intervals

---

### 2.5 Buzzer PWM (`buzzer_pwm`)

**Reference:** `microarchitecture_spec.md` §10, `REGISTER_MAP.md` §6, SRS REQ-006

#### 2.5.1 Test Categories

| Category | Tests | Cycles |
|----------|-------|--------|
| Register access | All 9 registers; reset, R/W | 500 |
| Frequency range | 1 kHz–10 kHz; verify period accuracy (±1%) | 2,000 |
| Duty cycle | 0%–100%; verify duty cycle accuracy | 2,000 |
| Burst mode | ON cycles / OFF cycles; verify timing | 2,000 |
| Burst repeat count | Finite and infinite burst modes | 1,000 |
| Output polarity | INVERT bit; verify inversion | 500 |
| Interrupts | BURST_DONE; mask/unmask | 500 |
| Alert patterns | Continuous, 500ms on/off; sequencing | 1,000 |
| Clock gating | CLK_EN = 0; verify no output | 500 |
| Software reset | SOFT_RST | 500 |

**Total directed cycles:** ~10,500  
**Randomized cycles target:** 500,000

---

### 2.6 UART (`uart_16550`)

**Reference:** `microarchitecture_spec.md` §11, `REGISTER_MAP.md` §7, SRS REQ-007

#### 2.6.1 Test Categories

| Category | Tests | Cycles |
|----------|-------|--------|
| Register access | All 10+ registers; DLAB switching | 1,000 |
| Baud rates | 9600, 19200, 38400, 57600, 115200, 921600 | 3,000 |
| Word lengths | 5, 6, 7, 8 bits | 1,000 |
| Stop bits | 1, 1.5, 2 | 500 |
| Parity | None, Even, Odd, Mark, Space | 1,000 |
| TX FIFO | Fill/drain, threshold interrupts | 1,000 |
| RX FIFO | Fill/drain, threshold interrupts | 1,000 |
| Line errors | Overrun, parity error, framing error, break | 1,000 |
| Loopback | Internal loopback mode | 500 |
| Full-duplex | Simultaneous TX + RX | 1,000 |
| Interrupts | RX, TX, line status; mask/unmask | 500 |
| Software reset | SOFT_RST | 500 |

**Total directed cycles:** ~12,000  
**Randomized cycles target:** 500,000 (random data, random baud rates, random line errors)

---

### 2.7 GPIO (`gpio_32bit`)

**Reference:** `microarchitecture_spec.md` §12, `REGISTER_MAP.md` §8, SRS REQ-008

#### 2.7.1 Test Categories

| Category | Tests | Cycles |
|----------|-------|--------|
| Register access | All registers; reset, R/W, RO | 500 |
| Direction control | Input/output per pin; verify direction | 1,000 |
| Output data | SET, CLR, TOG, DATA registers; verify | 2,000 |
| Input read | External input → GPIO_IN register | 1,000 |
| Bit-set/clear/toggle | Atomic bit operations; no RMW needed | 2,000 |
| Interrupt config | Edge/level, rising/falling/high/low per pin [7:0] | 2,000 |
| Interrupt handling | INT_STATUS, INT_ACK; mask/unmask | 1,000 |
| Safety pin lock | Lock bits 0–2; verify cannot unlock without reset | 1,000 |
| Pull-up/down | PULL_EN + PULL_SEL; verify | 1,000 |
| Drive strength | 2/4/8/12 mA; verify (analog/mixed-signal sim) | 500 |
| Force shutdown input | force_shutdown_i → alert_o | 500 |
| Clock gating | CLK_EN = 0 | 500 |
| Software reset | SOFT_RST | 500 |

**Total directed cycles:** ~12,500  
**Randomized cycles target:** 500,000 (random pin wiggling, random interrupt configs)

---

### 2.8 TCM (`tcm_8kb` × 2)

**Reference:** `microarchitecture_spec.md` §4, SRS REQ-012

#### 2.8.1 Test Categories

| Category | Tests | Cycles |
|----------|-------|--------|
| Basic R/W | Write all 2048 words, read back; verify | 5,000 |
| Byte enables | Each byte lane individually; verify | 2,000 |
| Read latency | 1-cycle read; verify data available next cycle | 500 |
| Write latency | 1-cycle write; verify data committed | 500 |
| Parity generation | Write → read → verify parity bit | 2,000 |
| Single-bit error | Inject bit flip; verify parity_err_o asserted | 2,000 |
| Simultaneous R/W | Read address A while writing address B (DTCM only) | 1,000 |
| Address wrap | Address beyond 8KB; verify behavior | 500 |
| Reset behavior | Content after reset (zeroed or undefined) | 500 |

**Total directed cycles:** ~14,000  
**Randomized cycles target:** 1,000,000 (random address sequences, random data, random byte enables)

---

### 2.9 AXI4-Lite Interconnect (`axi4lite_xbar_1m_9s`)

**Reference:** `microarchitecture_spec.md` §5, REQ-009

#### 2.9.1 Test Categories

| Category | Tests | Cycles |
|----------|-------|--------|
| Address decode | All 9 slave regions + unmapped → SLVERR | 500 |
| Read transaction | Single read to each slave; verify rdata, rresp | 500 |
| Write transaction | Single write to each slave; verify bresp | 500 |
| Back-to-back | Rapid reads/writes to same slave | 1,000 |
| Interleaved | Read to slave A, write to slave B, read to slave C | 2,000 |
| AXI handshake | All valid/ready combinations | 2,000 |
| wstrb | All 16 byte-strobe patterns; verify partial writes | 1,000 |
| SLVERR | Unmapped address; verify rresp/bresp = 2'b10 | 500 |
| DECERR | Protocol violations; verify rresp/bresp = 2'b11 | 500 |
| Timing | All paths ≤ 2 cycles combinatorial delay (STA check) | — |
| Reset during transaction | Verify clean abort | 500 |

**Total directed cycles:** ~9,000  
**Randomized cycles target:** 2,000,000 (random addresses, random data, random strobes, random interleaving of 9 slaves)

---

### 2.10 RV32IM Core (`rv32im_core`)

**Reference:** `microarchitecture_spec.md` §3, SRS REQ-001, REQ-011

#### 2.10.1 Test Categories

| Category | Tests | Cycles |
|----------|-------|--------|
| RISC-V compliance | Full RV32I + RV32M compliance suites | 50,000+ |
| Pipeline hazards | RAW, load-use, control, structural | 5,000 |
| Forwarding | All forwarding paths verified | 3,000 |
| Branches | Taken/not-taken; branch penalty = 1 cycle | 2,000 |
| Multi-cycle ops | MUL (1c), MULH (2c), DIV (1-32c), REM (1-32c) | 5,000 |
| CSR access | All CSRs: mstatus, mepc, mcause, mtvec, mie, mip, mcycle, minstret | 3,000 |
| Interrupts | All 16 IRQ lines; edge/level/priority | 5,000 |
| Traps/Exceptions | Illegal instruction, ECALL, misaligned access | 2,000 |
| Lockstep outputs | lockstep_outputs_o, lockstep_pc_o, lockstep_valid_o | 5,000 |
| Halt | halt_i asserted; verify PC stalls | 500 |
| WFI | Wait for interrupt; clock gating | 500 |
| Reset | Reset during operation; verify clean restart | 500 |

**Total directed cycles:** ~82,000  
**Randomized cycles target:** 5,000,000 (random instruction streams, random interrupt timing)  
**Golden reference:** Spike RISC-V simulator (instruction-level golden model)

---

### 2.11 Window Watchdog Timer (`window_wdt`)

**Reference:** `microarchitecture_spec.md` §7.4, `REGISTER_MAP.md` §10, SRS REQ-013

#### 2.11.1 Test Categories

| Category | Tests | Cycles |
|----------|-------|--------|
| Register access | All registers; write key protocol, locks | 1,000 |
| Timeout | Configure timeout; verify fault at exact count | 2,000 |
| Window mode | Refresh in open window → OK | 2,000 |
| Early kick | Refresh in closed window → EARLY_KICK fault | 1,000 |
| Late kick | Fail to refresh → TIMED_OUT fault | 1,000 |
| Pre-warning | PREWARN threshold → prewarn_o asserted | 1,000 |
| Kick value | Incorrect kick value → no refresh | 500 |
| Write key | Incorrect write key → registers not updated | 500 |
| Register locks | LOCK_CTRL, LOCK_TIMEOUT, LOCK_WINDOW → read-only | 500 |
| Enable lock | Once enabled, cannot disable | 500 |
| Counter rollover | Counter wraps without timeout | 500 |
| Reset | wdt_rst_n → clean state | 500 |
| CDC testing | Register reads/writes from sys_clk domain | 2,000 |

**Total directed cycles:** ~13,000  
**Randomized cycles target:** 1,000,000 (random window/timing configs, random kick timing)  
**Clock domain:** wdt_clk (32.768 kHz) — timing-critical

---

### 2.12 Safety Monitor / Lockstep Comparator / Fault Aggregator

**Reference:** `microarchitecture_spec.md` §7, §13, `REGISTER_MAP.md` §9, SRS REQ-011, REQ-014, REQ-015

#### 2.12.1 Test Categories

| Category | Tests | Cycles |
|----------|-------|--------|
| Register access | All safety registers; reset, R/W, W1C, locks | 1,000 |
| Lockstep comparison | Match → no fault; mismatch → lockstep_mismatch | 5,000 |
| Delay compensation | verify 1/2/3/4 cycle delay configs | 2,000 |
| Fault masking | Individual fault source enable/disable | 1,000 |
| Fault latching | Fault status latched until W1C | 1,000 |
| Fault counter | Saturating counter; verify | 1,000 |
| Severity filtering | FAULT_SEVERITY threshold | 1,000 |
| Auto-halt | AUTO_HALT = 1 → core_halt_o on critical fault | 500 |
| Auto-shutdown | AUTO_SHUTDOWN = 1 → aggregated_fault_o | 500 |
| Test mode | FORCE_FAULT, FORCE_MISMATCH; test bypass | 1,000 |
| All fault sources | Verify each of 12 fault inputs individually | 2,000 |
| Reset control | SAFETY_RESET_CTRL with magic key | 500 |
| Module ID | SAFETY_ID = "SFTY" (0x5346_5459) | 100 |
| Interrupts | SAFETY_INTR; lockstep, fault_agg | 500 |

**Total directed cycles:** ~17,600  
**Randomized cycles target:** 2,000,000 (random fault injection timing, random fault combinations)

---

### 2.13 Redundant Shutdown Controller (`redundant_shutdown_ctrl`)

**Reference:** `microarchitecture_spec.md` §7.5, §15, SRS REQ-014, REQ-016

#### 2.13.1 Test Categories

| Category | Tests | Cycles |
|----------|-------|--------|
| Aggregated fault input | Assert → shutdown_n_o [1:0] within 10 wdt cycles | 1,000 |
| Software shutdown | force_shutdown_sw_i → shutdown | 500 |
| Shutdown sequence | alert_n_o first → 4 wdt cycles → shutdown_n_o | 1,000 |
| Latching | shutdown_n_o latched until power-cycle | 500 |
| force_shutdown_o | Output to GPIO | 500 |
| Combinatorial path | No clocked elements in critical path | — |
| CDC inputs | aggregated_fault_i and force_shutdown_sw_i synchronized | 1,000 |
| Reset | POR reset only; no warm reset | 500 |

**Total directed cycles:** ~5,000  
**Randomized cycles target:** 200,000  
**Clock domain:** wdt_clk (32.768 kHz)

---

### 2.14 Top-Level (`adas_v2_top`)

**Reference:** `microarchitecture_spec.md` §1, SRS REQ-010, REQ-016, REQ-017

#### 2.14.1 Test Categories

| Category | Tests | Cycles |
|----------|-------|--------|
| End-to-end dataflow | LIDAR → AI → CPU → PWM (braking scenario) | 50,000 |
| Reset sequence | POR → boot → peripheral init → safety enable | 5,000 |
| Interrupt routing | All 16 IRQ sources → CPU IRQ handler | 2,000 |
| Clock domains | CDC crossings verified (sys_clk ↔ wdt_clk) | 5,000 |
| Timing latency | REQ-017: < 5ms end-to-end at SS/125°C | — (STA) |
| Safety scenarios | All 6 REQ-016 safe state entry paths | 10,000 |
| Concurrent operation | AI processing + SPI receiving + PWM output simultaneously | 10,000 |
| Stress test | All peripherals active, random bus traffic | 50,000 |
| Scenario: approach_and_brake | Pedestrian detection → braking sequence | 5,000 |
| Scenario: crossing_clear | Object crosses path, no braking | 5,000 |
| Scenario: stationary_obstacle | Obstacle ahead, brake engagement | 5,000 |
| Scenario: safety_timeout | Brake servo fails → redundant shutdown | 5,000 |

**Total directed cycles:** ~152,000  
**Randomized cycles target:** 10,000,000 (random sensor inputs, full system exercising all paths)

---

## 3. Integration-Level Verification Plans

### 3.1 RV32IM ↔ ITCM/DTCM Integration

- Verify: All instruction fetches from ITCM succeed (1-cycle latency)
- Verify: All load/store to DTCM succeed (1-cycle latency)
- Verify: Parity errors propagated to safety monitor

### 3.2 RV32IM ↔ AXI4-Lite ↔ Peripherals Integration

- Verify: Every peripheral register accessible via AXI bus from CPU
- Verify: Address decode correct — unmapped accesses return SLVERR
- Verify: Concurrent AXI transactions to different slaves complete correctly

### 3.3 Peripheral ↔ Safety Monitor Integration

- Verify: Each of 7 fault inputs (ai, spi, servo, speed, wdt, itcm_parity, dtcm_parity) → safety_monitor
- Verify: aggregated_fault → CDC → redundant_shutdown_ctrl

### 3.4 AI Accelerator ↔ AXI ↔ CPU Workflow

- Verify: Full workflow: CPU loads weights → loads input → sets GO → polls DONE → reads output
- Verify: Correct results for known test vectors compared to Python golden model

### 3.5 GPIO ↔ RSC Integration

- Verify: RSC force_shutdown → GPIO input → GPIO alert/shutdown outputs

---

## 4. System-Level Verification Plans

### 4.1 ADAS Emergency Braking Scenario (Primary Use Case)

Repeat 100,000+ times with randomized parameters:

```
FOR each iteration:
  1. Random ego_speed (0–120 km/h)
  2. Random object_distance (0–100 m)
  3. Random object_relative_speed (-30 to +30 m/s)
  4. Random object_class (CAR, PEDESTRIAN, OBSTACLE, NONE)
  5. Stimulate sensors via BFMs
  6. Observe: servo_pwm.duty, buzzer_pwm.output, gpio.alerts
  7. Compare: golden reference model → RTL outputs
  8. Log any mismatch
```

### 4.2 Multi-Scenario Sequence Testing

Each scenario (from `reference_model.py` §6) executed 10,000× with parameter variation:

| Scenario | Parameter Variation |
|----------|-------------------|
| `approach_and_brake` | Initial distance, closure rate, ego speed, object class |
| `crossing_clear` | Initial distance, relative speed profile, ego speed |
| `stationary_obstacle` | Initial distance, ego speed, object class |
| `safety_timeout` | Brake engagement delay, fault timing |

---

## 5. Safety Verification Plans

### 5.1 Safety Mechanism Verification Matrix

| Safety Mechanism | Module | Verification Method | Cycles |
|-----------------|--------|-------------------|--------|
| Lockstep comparison | safety_monitor | Fault injection: inject mismatch in core outputs; verify detection < 3 cycles | 50,000 |
| ECC/Parity on SRAM | tcm_8kb | Inject single-bit errors; verify parity_err_o. Inject double-bit errors. | 10,000 |
| Window WDT | window_wdt | Early kick, late kick, clock failure, bad kick value | 20,000 |
| Redundant shutdown | redundant_shutdown_ctrl | Assert fault; verify shutdown within 10 wdt cycles (~0.3 ms) | 5,000 |
| Fault aggregation | safety_monitor | All 12 fault sources; verify correct aggregation + latched | 10,000 |
| Auto-halt on critical | safety_monitor | Verify core_halt_o on lockstep mismatch, parity errors | 5,000 |
| Safe state entry | adas_v2_top | Verify servo PWM disabled, buzzer off, GPIO alerts | 5,000 |
| Independent clock | window_wdt | Remove sys_clk; verify WDT still operates | 1,000 |

### 5.2 Diagnostic Coverage Targets (ISO 26262-5:2018)

| Metric | ASIL-D Target | Verification Approach |
|--------|--------------|----------------------|
| SPFM (Single-Point Fault Metric) | ≥ 99% | Fault injection on all safety-critical logic |
| LFM (Latent Fault Metric) | ≥ 90% | Periodic BIST + STL in firmware (tested with CPU) |
| Diagnostic Coverage (DC) | ≥ 99% (High) | Combined lockstep + ECC + WDT + safety monitor |

---

## 6. Randomized Test Strategy

### 6.1 Randomization Framework

```
┌─────────────────────────────────────────────────┐
│              RANDOMIZED TEST ENGINE              │
│                                                  │
│  1. Seed selection (deterministic replay)        │
│  2. Constraint solver (valid ranges per field)   │
│  3. Stimulus generator (BFM drivers)             │
│  4. Coverage collector (bin hits)                │
│  5. Golden reference comparator (mismatch log)   │
│  6. Checkpoint/restore for long runs             │
└─────────────────────────────────────────────────┘
```

### 6.2 Constrained Random Domains

| Domain | Constraints | Rationale |
|--------|------------|-----------|
| AXI addresses | Must be in valid peripheral regions | Avoid SLVERR noise |
| AXI data | 32-bit uniform random | Full data path exercise |
| SPI data | 8-bit uniform random, CRC-correct frames | Protocol compliance |
| PWM duty | 500–2500 µs for servo; 0–100% for buzzer | Valid operating range |
| AI weights | INT8 signed (-128 to +127) | Full INT8 range |
| AI inputs | INT8 signed | Full range |
| Sensor distance | 0–200 m | Realistic automotive range |
| Sensor speed | -50 to +50 m/s (±180 km/h) | Automotive envelope |
| IRQ timing | Random inter-arrival 100–10,000 cycles | Stress interrupt handling |

### 6.3 Millions-of-Cycles Strategy

| Module | Random Cycles | Time @ 1 kHz sim* | Parallel Instances |
|--------|--------------|-------------------|-------------------|
| rv32im_core | 5,000,000 | ~1.4 hrs | 4 |
| ai_accel_4x4 | 1,000,000 | ~17 min | 8 |
| spi_master | 2,000,000 | ~33 min | 8 |
| servo_pwm | 1,000,000 | ~17 min | 8 |
| speed_sensor | 1,000,000 | ~17 min | 8 |
| buzzer_pwm | 500,000 | ~8 min | 8 |
| uart_16550 | 500,000 | ~8 min | 8 |
| gpio_32bit | 500,000 | ~8 min | 8 |
| tcm_8kb | 1,000,000 | ~17 min | 4 |
| axi4lite_xbar | 2,000,000 | ~33 min | 4 |
| safety_monitor | 2,000,000 | ~33 min | 4 |
| window_wdt | 1,000,000 | ~17 min | 4 |
| redundant_shutdown | 200,000 | ~3 min | 4 |
| adas_v2_top | 10,000,000 | ~2.8 hrs | 4 |
| **TOTAL** | **~28,700,000** | **~7.5 hrs/instance** | |

*\*Simulation throughput depends on cocotb + Icarus Verilog; ~1,000 cycles/sec on a modern 16-core machine for the full SoC.*

### 6.4 Seed Management

- Each regression run starts with a master seed
- Per-test seeds derived deterministically from master
- All seeds logged to `regression_results/<run_id>/seeds.log`
- Any failure can be reproduced with the exact seed
- Weekly "long soak" runs with new master seeds

---

## 7. Golden Reference Comparison

### 7.1 Golden Reference Sources

| Module | Golden Model | Comparison Method |
|--------|-------------|-------------------|
| rv32im_core | Spike RISC-V simulator | Instruction-by-instruction architectural state comparison |
| ai_accel_4x4 | `reference_model.py` (NumPy matmul) | Bit-exact output register comparison |
| ADAS algorithm | `reference_model.py` ADASController | State machine + output signal comparison |
| SPI | Protocol checker BFM | Byte-level comparison |
| Servo PWM | Python PWM model | Duty cycle, period comparison |
| Speed sensor | Python speed computation model | COUNT, TIMESTAMP, PERIOD comparison |
| Safety monitor | Shadow processor model in `reference_model.py` | SafetyMonitor class comparison |

### 7.2 Golden Reference Verification Flow

```
┌─────────┐    ┌──────────────┐    ┌──────────────────┐    ┌─────────┐
│ RTL DUT │    │  Scoreboard  │    │ Golden Reference │    │  PASS/  │
│ Output  │───→│  (Python)    │◄───│ Model (Python)   │───→│  FAIL   │
└─────────┘    │              │    └──────────────────┘    └─────────┘
               │ Compare:     │
               │ - bit-exact  │
               │ - cycle-lag  │
               │ - tolerance  │
               └──────────────┘
```

### 7.3 Comparison Tolerances

| Signal Class | Tolerance | Rationale |
|-------------|-----------|-----------|
| Register values | Bit-exact | Must match RTL exactly |
| PWM duty cycle | ±1 µs (±100 sys_clk cycles) | REQ-019 spec |
| PWM period | ±5% | REQ-005 spec |
| Timing latency | ±10 µs (system-level) | Within measurement margin |
| AI output | Bit-exact (±0 INT32) | Algorithmic identity |
| Safety response time | ±1 ms | REQ-016 spec |

---

## 8. Resource Estimates and Schedule

### 8.1 Testbench Implementation Effort

| Module | Directed Tests | Random Tests | Total Effort (days) |
|--------|---------------|-------------|---------------------|
| ai_accel_4x4 | 2 | 1 | 3 |
| spi_master | 2 | 1 | 3 |
| servo_pwm | 1 | 1 | 2 |
| speed_sensor | 1 | 1 | 2 |
| buzzer_pwm | 1 | 0.5 | 1 |
| uart_16550 | 1 | 0.5 | 1 |
| gpio_32bit | 1 | 0.5 | 1 |
| tcm_8kb | 1 | 0.5 | 1 |
| axi4lite_xbar | 1.5 | 0.5 | 2 |
| rv32im_core | 3 | 2 | 5 |
| safety_monitor | 2 | 1 | 3 |
| window_wdt | 1 | 0.5 | 1 |
| redundant_shutdown | 0.5 | 0.5 | 1 |
| adas_v2_top | 3 | 2 | 5 |
| Integration tests | 2 | 1 | 3 |
| Fault injection | 3 | — | 3 |
| **TOTAL** | **26** | **13.5** | **37 work-days** |

### 8.2 Machine Requirements

- Minimum: 16-core CPU, 64 GB RAM, 500 GB SSD
- Recommended: 32-core CPU, 128 GB RAM, 1 TB NVMe
- Parallel simulation capacity: 8 concurrent cocotb instances

### 8.3 Coverage Collection Tools

- **VCS/Xcelium:** Native coverage (`-cm line+cond+fsm+tgl+branch`)
- **Icarus Verilog:** Coverage via cocotb coverage plugin
- **Verilator:** `--coverage` flag + merge
- **Post-processing:** Python scripts to merge, analyze, and report

---

## 9. Verification Closure Criteria

### 9.1 Gate Criteria (MANDATORY before P&R)

| Criterion | Target | Measurement |
|-----------|--------|-------------|
| Code coverage — line | **100%** | Exclude only unreachable defensive code |
| Code coverage — branch | **100%** | All branches taken both ways |
| Code coverage — FSM | **100%** | All states visited, all transitions exercised |
| Code coverage — toggle | **≥ 99%** | Exclude DFT-only paths |
| Functional coverage | **100%** | All coverage bins hit |
| Functional — cross coverage | **100%** | All cross-product bins hit |
| Directed tests pass | **ALL** | Zero failures |
| Randomized cycles | **≥ 1,000,000 per module** | Minimum; target per module spec |
| System-level cycles | **≥ 10,000,000** | adas_v2_top randomized |
| Safety fault injection | **ALL fault sources** | Each of 12+ sources injected 1000+ times |
| Golden reference comparison | **ZERO mismatches** | Bit-exact where specified |
| Open bugs | **ZERO CRITICAL, ZERO HIGH** | Low/medium may remain with documented waivers |
| Regression pass rate | **100%** | All tests in nightly regression |

### 9.2 Waiver Process

Any coverage exclusion or bug waiver must:
1. Be documented in `verification_waivers.md`
2. Include justification referencing SRS requirement
3. Be approved by Architect (Kenji Tanaka)
4. Include mitigation plan if safety-critical

### 9.3 Sign-Off Checklist

- [ ] All module testbenches implemented and passing
- [ ] Code coverage ≥ 100% for all modules (with documented waivers)
- [ ] Functional coverage = 100%
- [ ] Golden reference comparison complete — zero mismatches
- [ ] Fault injection complete — all safety mechanisms verified
- [ ] System-level scenario testing complete
- [ ] Randomized soak runs ≥ target cycles
- [ ] All bugs filed, fixed, and verified
- [ ] Regression passing on latest RTL
- [ ] Verification report generated
- [ ] Architect review and sign-off

---

## Revision History

| Version | Date | Author | Description |
|---------|------|--------|-------------|
| 1.0 | 2026-04-29 | Rahul Sharma | Initial comprehensive verification plan |

---

*"Zero faults. One hundred percent. Millions of cycles. That's how we earn the P&R gate."*  
*— Rahul Sharma, Verification Lead*
