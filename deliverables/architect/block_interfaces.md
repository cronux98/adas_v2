# ADAS v2 — Block-Level Interface Definitions

**Document:** ARCH-IF-001 | **Version:** 1.0 | **Date:** 2026-04-29  
**Author:** Kenji Tanaka, Chief Architect  
**Reference:** `microarchitecture_spec.md` ARCH-SPEC-001  

---

## Table of Contents

1. [Conventions](#1-conventions)
2. [Top-Level Port Map](#2-top-level-port-map)
3. [RV32IM Core Interface](#3-rv32im-core-interface)
4. [ITCM/DTCM Interface](#4-itcmdtcm-interface)
5. [AXI4-Lite Interconnect Interface](#5-axi4-lite-interconnect-interface)
6. [AI Accelerator Interface](#6-ai-accelerator-interface)
7. [SPI Controller Interface](#7-spi-controller-interface)
8. [Servo PWM Controller Interface](#8-servo-pwm-controller-interface)
9. [Speed Sensor Interface](#9-speed-sensor-interface)
10. [Buzzer PWM Interface](#10-buzzer-pwm-interface)
11. [UART Interface](#11-uart-interface)
12. [GPIO Interface](#12-gpio-interface)
13. [Safety Monitor Interface](#13-safety-monitor-interface)
14. [Window Watchdog Timer Interface](#14-window-watchdog-timer-interface)
15. [Redundant Shutdown Controller Interface](#15-redundant-shutdown-controller-interface)
16. [Clock and Reset Interface](#16-clock-and-reset-interface)

---

## 1. Conventions

### 1.1 Naming

- `_n` suffix: Active-low signal
- `_i` suffix: Input to block
- `_o` suffix: Output from block
- `_io` suffix: Bidirectional
- Bus notation: `name[MSB:LSB]`

### 1.2 Timing

Unless otherwise stated:
- All signals are synchronous to their respective clock domain.
- Outputs change after rising clock edge (clk-to-Q delay).
- Inputs must be stable at setup time before rising clock edge.
- AXI4-Lite signals follow ARM IHI 0022E specification.

### 1.3 Signal Types

| Type | Description |
|------|-------------|
| I | Standard input |
| O | Standard output (registered) |
| IO | Bidirectional (with output enable) |
| PWR | Power/ground |
| CLK | Clock |

---

## 2. Top-Level Port Map

The top-level module `adas_v2_top` presents the following external ports:

| Port Name | Width | Dir | Domain | Description |
|-----------|-------|-----|--------|-------------|
| `sys_clk_i` | 1 | I | — | System clock (100 MHz) |
| `wdt_clk_i` | 1 | I | — | Watchdog clock (32.768 kHz) |
| `sys_rst_n_i` | 1 | I | async | System reset, active low |
| `wdt_rst_n_i` | 1 | I | async | Watchdog reset, active low |
| `spi_sck_o` | 1 | O | sys_clk | SPI serial clock |
| `spi_mosi_o` | 1 | O | sys_clk | SPI master-out-slave-in |
| `spi_miso_i` | 1 | I | sys_clk | SPI master-in-slave-out |
| `spi_cs_n_o` | 4 | O | sys_clk | SPI chip select (one-hot, 4 slaves max) |
| `servo_pwm_o` | 1 | O | sys_clk | Servo PWM output |
| `speed_pulse_i` | 1 | I | async | Speed sensor pulse input (synchronized internally) |
| `buzzer_pwm_o` | 1 | O | sys_clk | Buzzer PWM output |
| `uart_tx_o` | 1 | O | sys_clk | UART transmit |
| `uart_rx_i` | 1 | I | async | UART receive (synchronized internally) |
| `gpio_io` | 32 | IO | sys_clk | General-purpose I/O |
| `alert_n_o` | 1 | O | wdt_clk | Alert output (active low) |
| `shutdown_n_o` | 2 | O | wdt_clk | Redundant shutdown (active low) |
| `test_mode_i` | 1 | I | async | DFT test mode enable |

*Total top-level I/O: 48 pins (excluding power/ground)*

---

## 3. RV32IM Core Interface

### 3.1 Module: `rv32im_core`

```
┌─────────────────────────────────────────────┐
│                rv32im_core                   │
│                                              │
│  clk_i, rst_n_i                             │
│                                              │
│  ── ITCM Master ──→ itcm_*                  │
│  ── DTCM Master ──→ dtcm_*                  │
│  ── AXI4-Lite M  ──→ axi_*                  │
│                                              │
│  irq_i[15:0]                                 │
│  lockstep_outputs_o[31:0]                    │
│  lockstep_pc_o[31:0]                         │
│  lockstep_valid_o                            │
│  halt_i (from safety monitor)                │
│                                              │
│  debug_req_i (JTAG/debug)                    │
└─────────────────────────────────────────────┘
```

### 3.2 Port List

#### Clock and Reset

| Port | Width | Dir | Description |
|------|-------|-----|-------------|
| `clk_i` | 1 | I | sys_clk (100 MHz) |
| `rst_n_i` | 1 | I | Synchronous reset (active low) |

#### ITCM Interface (Local Memory Bus)

| Port | Width | Dir | Description |
|------|-------|-----|-------------|
| `itcm_addr_o` | 13 | O | ITCM byte address (bits [14:2], word-aligned) |
| `itcm_rdata_i` | 32 | I | Instruction read data |
| `itcm_req_o` | 1 | O | Request valid |
| `itcm_ack_i` | 1 | I | Acknowledge (1 cycle after request) |

#### DTCM Interface (Local Memory Bus)

| Port | Width | Dir | Description |
|------|-------|-----|-------------|
| `dtcm_addr_o` | 13 | O | DTCM byte address (bits [14:2]) |
| `dtcm_wdata_o` | 32 | O | Write data |
| `dtcm_rdata_i` | 32 | I | Read data |
| `dtcm_we_o` | 4 | O | Byte write enable |
| `dtcm_req_o` | 1 | O | Request valid |
| `dtcm_ack_i` | 1 | I | Acknowledge |

#### AXI4-Lite Master Interface

| Port | Width | Dir | Description |
|------|-------|-----|-------------|
| `m_axi_awaddr_o` | 32 | O | Write address |
| `m_axi_awprot_o` | 3 | O | Write protection type |
| `m_axi_awvalid_o` | 1 | O | Write address valid |
| `m_axi_awready_i` | 1 | I | Write address ready |
| `m_axi_wdata_o` | 32 | O | Write data |
| `m_axi_wstrb_o` | 4 | O | Write strobe |
| `m_axi_wvalid_o` | 1 | O | Write data valid |
| `m_axi_wready_i` | 1 | I | Write data ready |
| `m_axi_bresp_i` | 2 | I | Write response |
| `m_axi_bvalid_i` | 1 | I | Write response valid |
| `m_axi_bready_o` | 1 | O | Write response ready |
| `m_axi_araddr_o` | 32 | O | Read address |
| `m_axi_arprot_o` | 3 | O | Read protection type |
| `m_axi_arvalid_o` | 1 | O | Read address valid |
| `m_axi_arready_i` | 1 | I | Read address ready |
| `m_axi_rdata_i` | 32 | I | Read data |
| `m_axi_rresp_i` | 2 | I | Read response |
| `m_axi_rvalid_i` | 1 | I | Read data valid |
| `m_axi_rready_o` | 1 | O | Read data ready |

#### Interrupts

| Port | Width | Dir | Description |
|------|-------|-----|-------------|
| `irq_i` | 16 | I | External interrupt lines |
| `timer_irq_i` | 1 | I | Machine timer interrupt (from mtime) |

#### Safety Monitor Interface

| Port | Width | Dir | Description |
|------|-------|-----|-------------|
| `lockstep_outputs_o` | 32 | O | Key core outputs for lockstep comparison |
| `lockstep_pc_o` | 32 | O | Program counter value |
| `lockstep_valid_o` | 1 | O | Strobe: lockstep outputs are valid this cycle |
| `halt_i` | 1 | I | Halt core (from safety monitor on fault) |

#### Debug

| Port | Width | Dir | Description |
|------|-------|-----|-------------|
| `debug_req_i` | 1 | I | Debug request (enter debug mode) |

---

## 4. ITCM/DTCM Interface

### 4.1 Module: `tcm_8kb`

Identical interface for ITCM and DTCM.

```
┌──────────────────────┐
│      tcm_8kb         │
│                      │
│  clk_i               │
│  addr_i[12:0]        │
│  wdata_i[31:0]       │
│  we_i[3:0]           │
│  req_i               │
│                      │
│  rdata_o[31:0]       │
│  ack_o               │
│  parity_err_o        │
└──────────────────────┘
```

| Port | Width | Dir | Description |
|------|-------|-----|-------------|
| `clk_i` | 1 | I | sys_clk |
| `addr_i` | 13 | I | Byte address [14:2] |
| `wdata_i` | 32 | I | Write data |
| `we_i` | 4 | I | Byte-lane write enables |
| `req_i` | 1 | I | Access request |
| `rdata_o` | 32 | O | Read data (1 cycle after req) |
| `ack_o` | 1 | O | Access complete |
| `parity_err_o` | 1 | O | Parity error on read (to fault aggregator) |

**Timing:** Read data available 1 cycle after `req_i`. Write committed 1 cycle after `req_i` with `we_i` asserted.

---

## 5. AXI4-Lite Interconnect Interface

### 5.1 Module: `axi4lite_xbar_1m_9s`

```
┌──────────────────────────────────────────────────┐
│           axi4lite_xbar_1m_9s                     │
│                                                   │
│  clk_i, rst_n_i                                  │
│                                                   │
│  ── Master Port ──→ s_axi_* (from RV32IM)        │
│                                                   │
│  ── Slave Port 0 ──→ m_axi_0_* (AI Accel)        │
│  ── Slave Port 1 ──→ m_axi_1_* (SPI)             │
│  ── Slave Port 2 ──→ m_axi_2_* (Servo PWM)       │
│  ── Slave Port 3 ──→ m_axi_3_* (Speed Sensor)    │
│  ── Slave Port 4 ──→ m_axi_4_* (Buzzer PWM)      │
│  ── Slave Port 5 ──→ m_axi_5_* (UART)            │
│  ── Slave Port 6 ──→ m_axi_6_* (GPIO)            │
│  ── Slave Port 7 ──→ m_axi_7_* (Safety Ctrl)     │
│  ── Slave Port 8 ──→ m_axi_8_* (Window WDT)      │
└──────────────────────────────────────────────────┘
```

### 5.2 Master Port (to RV32IM)

Mirrors the AXI4-Lite Master signals from Section 3, direction reversed.

### 5.3 Slave Ports (to each peripheral)

Each slave port has the same AXI4-Lite slave signals. Peripherals implement
a subset based on their needs:

| Port | Width | Dir | Required by |
|------|-------|-----|-------------|
| `s_axi_awaddr` | 32 | I | All peripherals with writable registers |
| `s_axi_awvalid` | 1 | I | All peripherals with writable registers |
| `s_axi_awready` | 1 | O | All peripherals with writable registers |
| `s_axi_wdata` | 32 | I | All peripherals with writable registers |
| `s_axi_wstrb` | 4 | I | All peripherals with writable registers |
| `s_axi_wvalid` | 1 | I | All peripherals with writable registers |
| `s_axi_wready` | 1 | O | All peripherals with writable registers |
| `s_axi_bresp` | 2 | O | All peripherals with writable registers |
| `s_axi_bvalid` | 1 | O | All peripherals with writable registers |
| `s_axi_bready` | 1 | I | All peripherals with writable registers |
| `s_axi_araddr` | 32 | I | All peripherals with readable registers |
| `s_axi_arvalid` | 1 | I | All peripherals with readable registers |
| `s_axi_arready` | 1 | O | All peripherals with readable registers |
| `s_axi_rdata` | 32 | O | All peripherals with readable registers |
| `s_axi_rresp` | 2 | O | All peripherals with readable registers |
| `s_axi_rvalid` | 1 | O | All peripherals with readable registers |
| `s_axi_rready` | 1 | I | All peripherals with readable registers |

**AXI4-Lite Signal Definitions:**

| Signal | Width | Description |
|--------|-------|-------------|
| `awaddr` | 32 | Write address (byte address) |
| `awprot` | 3 | Protection type [2:0] = {inst/data, privileged/unpriv, secure/nonsecure} |
| `wdata` | 32 | Write data |
| `wstrb` | 4 | Write byte strobe (bit i asserted → byte i valid) |
| `bresp` | 2 | Write response: 00=OKAY, 10=SLVERR, 11=DECERR |
| `araddr` | 32 | Read address (byte address) |
| `arprot` | 3 | Same as awprot |
| `rdata` | 32 | Read data |
| `rresp` | 2 | Read response: same encoding as bresp |
| Valid/Ready | 1 | Standard AXI handshake |

### 5.4 Address Decode Map

| Slave | Base Address | Size | Address Match [31:12] |
|-------|-------------|------|----------------------|
| 0 | 0x0000_1000 | 4 KB | 0x00001 |
| 1 | 0x0000_2000 | 4 KB | 0x00002 |
| 2 | 0x0000_3000 | 4 KB | 0x00003 |
| 3 | 0x0000_4000 | 4 KB | 0x00004 |
| 4 | 0x0000_5000 | 4 KB | 0x00005 |
| 5 | 0x0000_6000 | 4 KB | 0x00006 |
| 6 | 0x0000_7000 | 4 KB | 0x00007 |
| 7 | 0x0000_F000 | 4 KB | 0x0000F |
| 8 | 0x0000_F100 | 256 B | 0x0000F1 |

**Default slave:** Returns SLVERR on any unmapped address.

---

## 6. AI Accelerator Interface

### 6.1 Module: `ai_accel_4x4`

```
┌──────────────────────────────────────────┐
│            ai_accel_4x4                   │
│                                          │
│  clk_i, rst_n_i                          │
│                                          │
│  ── AXI4-Lite Slave ── s_axi_*          │
│                                          │
│  irq_done_o                              │
│  irq_error_o                             │
│  fault_o (to fault aggregator)           │
└──────────────────────────────────────────┘
```

### 6.2 Port List

| Port | Width | Dir | Domain | Description |
|------|-------|-----|--------|-------------|
| `clk_i` | 1 | I | sys_clk | System clock |
| `rst_n_i` | 1 | I | sys_clk | Reset (active low) |
| `s_axi_*` | * | * | sys_clk | AXI4-Lite slave (section 5.3) |
| `irq_done_o` | 1 | O | sys_clk | Computation complete (to IRQ controller) |
| `irq_error_o` | 1 | O | sys_clk | Error condition (overflow, invalid config) |
| `fault_o` | 1 | O | sys_clk | Hard fault (to fault aggregator) |

### 6.3 Internal Buffers (not exposed at top level)

Internal SRAM buffers managed through register interface:
- **Weight Buffer:** 16 × 8-bit = 128 bits (4×4 INT8 weights)
- **Input Buffer:** 4 × 8-bit = 32 bits (input activations)
- **Output Buffer:** 4 × 32-bit = 128 bits (accumulated results)

---

## 7. SPI Controller Interface

### 7.1 Module: `spi_master`

```
┌──────────────────────────────────────────┐
│              spi_master                   │
│                                          │
│  clk_i, rst_n_i                          │
│                                          │
│  ── AXI4-Lite Slave ── s_axi_*          │
│                                          │
│  sck_o                                   │
│  mosi_o                                  │
│  miso_i                                  │
│  cs_n_o[3:0]                             │
│                                          │
│  irq_rx_o                                │
│  irq_tx_o                                │
│  irq_err_o                               │
│  fault_o (spi_error → fault aggregator)  │
└──────────────────────────────────────────┘
```

### 7.2 Port List

| Port | Width | Dir | Domain | Description |
|------|-------|-----|--------|-------------|
| `clk_i` | 1 | I | sys_clk | System clock |
| `rst_n_i` | 1 | I | sys_clk | Reset |
| `s_axi_*` | * | * | sys_clk | AXI4-Lite slave (section 5.3) |
| `sck_o` | 1 | O | sys_clk | SPI serial clock (sys_clk / divider) |
| `mosi_o` | 1 | O | sys_clk | Master Out Slave In |
| `miso_i` | 1 | I | sys_clk | Master In Slave Out |
| `cs_n_o` | 4 | O | sys_clk | Chip select (active low, one-hot) |
| `irq_rx_o` | 1 | O | sys_clk | RX FIFO not empty |
| `irq_tx_o` | 1 | O | sys_clk | TX FIFO not full |
| `irq_err_o` | 1 | O | sys_clk | SPI error (mode fault, overflow) |
| `fault_o` | 1 | O | sys_clk | Hard fault (to fault aggregator) |

**SPI Configuration via registers:**
- Clock divider: sys_clk / [2, 4, 8, ..., 256] → 50 MHz to 390 kHz
- Mode: CPOL=0/1, CPHA=0/1 (supporting Mode 0 and Mode 3)
- Frame size: 8-bit (fixed)
- FIFO depth: 8 bytes TX, 8 bytes RX
- MSB-first only

---

## 8. Servo PWM Controller Interface

### 8.1 Module: `servo_pwm`

```
┌──────────────────────────────────────────┐
│              servo_pwm                    │
│                                          │
│  clk_i, rst_n_i                          │
│                                          │
│  ── AXI4-Lite Slave ── s_axi_*          │
│                                          │
│  pwm_o                                   │
│                                          │
│  irq_fault_o                             │
│  fault_o (servo_fault → fault aggreg.)   │
└──────────────────────────────────────────┘
```

### 8.2 Port List

| Port | Width | Dir | Domain | Description |
|------|-------|-----|--------|-------------|
| `clk_i` | 1 | I | sys_clk | System clock |
| `rst_n_i` | 1 | I | sys_clk | Reset |
| `s_axi_*` | * | * | sys_clk | AXI4-Lite slave |
| `pwm_o` | 1 | O | sys_clk | PWM output to servo actuator |
| `irq_fault_o` | 1 | O | sys_clk | Servo fault IRQ (to CPU) |
| `fault_o` | 1 | O | sys_clk | Servo fault (to fault aggregator) |

**PWM Parameters (configurable):**
- Period: 20 ms (standard servo) = 2,000,000 sys_clk cycles @ 100 MHz
- Pulse width: 500 µs (0°) to 2500 µs (180°)
- Default (safe): 1500 µs (90°, neutral position)
- Resolution: 1 µs step (100 sys_clk cycles)
- Fault detection: PWM output stuck-at monitoring (readback compare)

---

## 9. Speed Sensor Interface

### 9.1 Module: `speed_sensor`

```
┌──────────────────────────────────────────┐
│             speed_sensor                  │
│                                          │
│  clk_i, rst_n_i                          │
│                                          │
│  ── AXI4-Lite Slave ── s_axi_*          │
│                                          │
│  pulse_i (async, synchronized internally)│
│                                          │
│  irq_pulse_o                             │
│  irq_ovf_o                               │
│  fault_o (sensor_stuck → fault agg.)     │
└──────────────────────────────────────────┘
```

### 9.2 Port List

| Port | Width | Dir | Domain | Description |
|------|-------|-----|--------|-------------|
| `clk_i` | 1 | I | sys_clk | System clock |
| `rst_n_i` | 1 | I | sys_clk | Reset |
| `s_axi_*` | * | * | sys_clk | AXI4-Lite slave |
| `pulse_i` | 1 | I | async | Wheel speed sensor pulse (external) |
| `irq_pulse_o` | 1 | O | sys_clk | Pulse detected IRQ |
| `irq_ovf_o` | 1 | O | sys_clk | Counter overflow IRQ |
| `fault_o` | 1 | O | sys_clk | Sensor stuck fault (to fault agg.) |

**Internal architecture:**
- 2-stage synchronizer on `pulse_i` (async → sys_clk)
- Edge detector (rising edge)
- 32-bit pulse counter (readable via register)
- 64-bit timestamp counter (capture on each pulse)
- Stuck-at detector: if no pulse detected within configurable timeout → `fault_o`

---

## 10. Buzzer PWM Interface

### 10.1 Module: `buzzer_pwm`

```
┌──────────────────────────────────────────┐
│              buzzer_pwm                   │
│                                          │
│  clk_i, rst_n_i                          │
│                                          │
│  ── AXI4-Lite Slave ── s_axi_*          │
│                                          │
│  pwm_o                                   │
│  irq_done_o                              │
└──────────────────────────────────────────┘
```

### 10.2 Port List

| Port | Width | Dir | Domain | Description |
|------|-------|-----|--------|-------------|
| `clk_i` | 1 | I | sys_clk | System clock |
| `rst_n_i` | 1 | I | sys_clk | Reset |
| `s_axi_*` | * | * | sys_clk | AXI4-Lite slave |
| `pwm_o` | 1 | O | sys_clk | Buzzer PWM output |
| `irq_done_o` | 1 | O | sys_clk | Burst complete IRQ |

**PWM Parameters (configurable):**
- Frequency: 1 kHz to 10 kHz (audible range)
- Duty cycle: 0-100% (50% recommended)
- Burst mode: N cycles on, M cycles off (configurable)
- Enable: Control register bit 0

---

## 11. UART Interface

### 11.1 Module: `uart_16550`

```
┌──────────────────────────────────────────┐
│              uart_16550                   │
│                                          │
│  clk_i, rst_n_i                          │
│                                          │
│  ── AXI4-Lite Slave ── s_axi_*          │
│                                          │
│  tx_o                                    │
│  rx_i (async, synchronized internally)   │
│                                          │
│  irq_rx_o                                │
│  irq_tx_o                                │
└──────────────────────────────────────────┘
```

### 11.2 Port List

| Port | Width | Dir | Domain | Description |
|------|-------|-----|--------|-------------|
| `clk_i` | 1 | I | sys_clk | System clock |
| `rst_n_i` | 1 | I | sys_clk | Reset |
| `s_axi_*` | * | * | sys_clk | AXI4-Lite slave |
| `tx_o` | 1 | O | sys_clk | UART TX (serial output) |
| `rx_i` | 1 | I | async | UART RX (serial input) |
| `irq_rx_o` | 1 | O | sys_clk | RX data available |
| `irq_tx_o` | 1 | O | sys_clk | TX holding register empty |

**Configuration (16550 subset):**
- Baud rate: sys_clk / divisor (e.g., 100M / 868 = 115200)
- Data bits: 5, 6, 7, 8
- Stop bits: 1, 1.5, 2
- Parity: None, Even, Odd
- FIFO: 16-byte TX, 16-byte RX

---

## 12. GPIO Interface

### 12.1 Module: `gpio_32bit`

```
┌──────────────────────────────────────────┐
│               gpio_32bit                  │
│                                          │
│  clk_i, rst_n_i                          │
│                                          │
│  ── AXI4-Lite Slave ── s_axi_*          │
│                                          │
│  gpio_io[31:0] (bidirectional)           │
│  irq_o[7:0]                              │
│                                          │
│  force_shutdown_i (from RSC)             │
│  alert_o (redundant alert output)        │
└──────────────────────────────────────────┘
```

### 12.2 Port List

| Port | Width | Dir | Domain | Description |
|------|-------|-----|--------|-------------|
| `clk_i` | 1 | I | sys_clk | System clock |
| `rst_n_i` | 1 | I | sys_clk | Reset |
| `s_axi_*` | * | * | sys_clk | AXI4-Lite slave |
| `gpio_io` | 32 | IO | sys_clk | Bidirectional GPIO |
| `irq_o` | 8 | O | sys_clk | Configurable edge/level interrupts (lower 8 pins) |
| `force_shutdown_i` | 1 | I | async | Force shutdown request from RSC (redundant path) |
| `alert_o` | 1 | O | sys_clk | Alert output (from CPU-controlled alert register) |

**GPIO Pin Assignment:**

| Pin | Function | Direction | Safety |
|-----|----------|-----------|--------|
| 0 | ALERT_OUT | O | Yes — alerts external systems |
| 1 | SHUTDOWN_OUT_A | O | Yes — redundant shutdown path A |
| 2 | SHUTDOWN_OUT_B | O | Yes — redundant shutdown path B |
| 3 | SHUTDOWN_ACK | I | Yes — external shutdown acknowledged |
| 4-7 | INTERRUPT_IN | I | Configurable edge/level IRQ |
| 8-15 | GENERAL_IN | I | General-purpose input |
| 16-23 | GENERAL_OUT | O | General-purpose output |
| 24-31 | RESERVED | IO | Reserved for future use |

---

## 13. Safety Monitor Interface

### 13.1 Module: `safety_monitor`

The safety monitor comprises three sub-blocks: lockstep comparator, fault aggregator,
and safety control register block.

```
┌──────────────────────────────────────────────────────┐
│                  safety_monitor                       │
│                                                      │
│  clk_i, rst_n_i                                      │
│                                                      │
│  ── AXI4-Lite Slave ── s_axi_* (Safety Ctrl)        │
│                                                      │
│  ── Lockstep Inputs ──                                    │
│  lockstep_outputs_i[31:0]                             │
│  lockstep_pc_i[31:0]                                  │
│  lockstep_valid_i                                     │
│                                                      │
│  ── Fault Inputs from Peripherals ──                 │
│  ai_fault_i                                           │
│  spi_fault_i                                          │
│  servo_fault_i                                        │
│  speed_fault_i                                        │
│  wdt_fault_i                          (CDC)          │
│  itcm_parity_err_i                                    │
│  dtcm_parity_err_i                                    │
│                                                      │
│  ── Outputs ──                                       │
│  aggregated_fault_o                     (CDC → RSC)  │
│  core_halt_o                                          │
│  irq_lockstep_o                                       │
│  irq_fault_agg_o                                      │
└──────────────────────────────────────────────────────┘
```

### 13.2 Port List

| Port | Width | Dir | Domain | Description |
|------|-------|-----|--------|-------------|
| `clk_i` | 1 | I | sys_clk | System clock |
| `rst_n_i` | 1 | I | sys_clk | Reset |
| `s_axi_*` | * | * | sys_clk | AXI4-Lite slave (safety control registers) |
| `lockstep_outputs_i` | 32 | I | sys_clk | Core outputs for comparison |
| `lockstep_pc_i` | 32 | I | sys_clk | Program counter |
| `lockstep_valid_i` | 1 | I | sys_clk | Valid strobe |
| `ai_fault_i` | 1 | I | sys_clk | AI accelerator fault |
| `spi_fault_i` | 1 | I | sys_clk | SPI controller fault |
| `servo_fault_i` | 1 | I | sys_clk | Servo PWM fault |
| `speed_fault_i` | 1 | I | sys_clk | Speed sensor fault |
| `wdt_fault_i` | 1 | I | *CDC* | WDT timeout → synchronized internally |
| `itcm_parity_err_i` | 1 | I | sys_clk | ITCM parity error |
| `dtcm_parity_err_i` | 1 | I | sys_clk | DTCM parity error |
| `aggregated_fault_o` | 1 | O | sys_clk | Aggregated fault → CDC → RSC |
| `core_halt_o` | 1 | O | sys_clk | Halt CPU on critical fault |
| `irq_lockstep_o` | 1 | O | sys_clk | Lockstep mismatch IRQ |
| `irq_fault_agg_o` | 1 | O | sys_clk | Fault aggregator alert IRQ |

### 13.3 Fault Aggregator Truth Table

| Inputs (any asserted) | aggregated_fault_o | core_halt_o | Latched? |
|-----------------------|-------------------|-------------|----------|
| lockstep_mismatch | 1 | 1 | Yes |
| wdt_fault | 1 | 0 | Yes (until WDT refresh) |
| servo_fault | 1 | 0 | Yes |
| ai_fault | 1 | 0 | No (cleared on read) |
| spi_fault | 0 | 0 | No (cleared on read) |
| speed_fault | 0 | 0 | No (cleared on read) |
| itcm_parity_err | 1 | 1 | Yes (non-maskable) |
| dtcm_parity_err | 1 | 1 | Yes (non-maskable) |

---

## 14. Window Watchdog Timer Interface

### 14.1 Module: `window_wdt`

```
┌──────────────────────────────────────────┐
│              window_wdt                   │
│                                          │
│  clk_i (wdt_clk, 32.768 kHz)             │
│  rst_n_i (wdt_rst_n)                     │
│                                          │
│  ── AXI4-Lite Slave (CDC) ── s_axi_*    │
│                                          │
│  fault_o (→ fault aggregator, CDC)       │
│  prewarn_o (→ IRQ controller, CDC)       │
└──────────────────────────────────────────┘
```

### 14.2 Port List

| Port | Width | Dir | Domain | Description |
|------|-------|-----|--------|-------------|
| `clk_i` | 1 | I | wdt_clk | Watchdog clock (32.768 kHz) |
| `rst_n_i` | 1 | I | wdt_clk | Watchdog reset |
| `s_axi_awaddr_i` | 32 | I | wdt_clk | AXI write address (CDC'd) |
| `s_axi_awvalid_i` | 1 | I | wdt_clk | AXI write address valid (CDC'd) |
| `s_axi_awready_o` | 1 | O | wdt_clk | AXI write address ready |
| `s_axi_wdata_i` | 32 | I | wdt_clk | AXI write data (CDC'd) |
| `s_axi_wstrb_i` | 4 | I | wdt_clk | AXI write strobe (CDC'd) |
| `s_axi_wvalid_i` | 1 | I | wdt_clk | AXI write data valid (CDC'd) |
| `s_axi_wready_o` | 1 | O | wdt_clk | AXI write data ready |
| `s_axi_bresp_o` | 2 | O | wdt_clk | AXI write response |
| `s_axi_bvalid_o` | 1 | O | wdt_clk | AXI write response valid |
| `s_axi_bready_i` | 1 | I | wdt_clk | AXI write response ready (CDC'd) |
| `s_axi_araddr_i` | 32 | I | wdt_clk | AXI read address (CDC'd) |
| `s_axi_arvalid_i` | 1 | I | wdt_clk | AXI read address valid (CDC'd) |
| `s_axi_arready_o` | 1 | O | wdt_clk | AXI read address ready |
| `s_axi_rdata_o` | 32 | O | wdt_clk | AXI read data |
| `s_axi_rresp_o` | 2 | O | wdt_clk | AXI read response |
| `s_axi_rvalid_o` | 1 | O | wdt_clk | AXI read data valid |
| `s_axi_rready_i` | 1 | I | wdt_clk | AXI read data ready (CDC'd) |
| `fault_o` | 1 | O | wdt_clk | WDT timeout fault |
| `prewarn_o` | 1 | O | wdt_clk | Pre-warning (75% of timeout) |

**Note:** All AXI inputs from sys_clk domain are synchronized using 2FF synchronizers
internally. See `cdc_plan.md` for details.

---

## 15. Redundant Shutdown Controller Interface

### 15.1 Module: `redundant_shutdown_ctrl`

```
┌──────────────────────────────────────────┐
│        redundant_shutdown_ctrl            │
│                                          │
│  clk_i (wdt_clk, 32.768 kHz)             │
│  rst_n_i (wdt_rst_n)                     │
│                                          │
│  aggregated_fault_i (CDC from sys_clk)   │
│  force_shutdown_sw_i (CDC from GPIO)     │
│                                          │
│  shutdown_n_o[1:0]                       │
│  alert_n_o                               │
│  force_shutdown_o (CDC → GPIO)           │
└──────────────────────────────────────────┘
```

### 15.2 Port List

| Port | Width | Dir | Domain | Description |
|------|-------|-----|--------|-------------|
| `clk_i` | 1 | I | wdt_clk | Watchdog clock |
| `rst_n_i` | 1 | I | wdt_clk | Watchdog reset |
| `aggregated_fault_i` | 1 | I | wdt_clk | Aggregated fault (synchronized) |
| `force_shutdown_sw_i` | 1 | I | wdt_clk | Software shutdown request (sync'd from GPIO) |
| `shutdown_n_o` | 2 | O | wdt_clk | Redundant shutdown outputs (active low) |
| `alert_n_o` | 1 | O | wdt_clk | Alert output (active low) |
| `force_shutdown_o` | 1 | O | wdt_clk | Shutdown override to GPIO block (CDC) |

**Timing:**
- `shutdown_n_o` asserted within 10 wdt_clk cycles (~0.3 ms) of fault detection.
- Outputs latched until external power-cycle reset.
- Shutdown sequence: `alert_n_o` asserted first → 4 wdt_clk cycles → `shutdown_n_o` asserted.

---

## 16. Clock and Reset Interface

### 16.1 Module: `clk_rst_gen`

```
┌──────────────────────────────────────────┐
│              clk_rst_gen                  │
│                                          │
│  sys_osc_i (external oscillator)         │
│  wdt_osc_i (external RC/crystal)         │
│  por_n_i   (power-on reset)              │
│                                          │
│  sys_clk_o                               │
│  wdt_clk_o                               │
│  sys_rst_n_o                             │
│  wdt_rst_n_o                             │
│  pll_lock_o                              │
└──────────────────────────────────────────┘
```

| Port | Width | Dir | Domain | Description |
|------|-------|-----|--------|-------------|
| `sys_osc_i` | 1 | I | analog | External system oscillator (e.g., 25 MHz) |
| `wdt_osc_i` | 1 | I | analog | External watchdog oscillator (32.768 kHz) |
| `por_n_i` | 1 | I | async | Power-on reset (active low) |
| `sys_clk_o` | 1 | O | — | System clock output (100 MHz from PLL) |
| `wdt_clk_o` | 1 | O | — | Buffered watchdog clock |
| `sys_rst_n_o` | 1 | O | sys_clk | System reset (sync de-asserted) |
| `wdt_rst_n_o` | 1 | O | wdt_clk | Watchdog reset (sync de-asserted) |
| `pll_lock_o` | 1 | O | async | PLL lock indicator |

---

## Interface Summary Matrix

| Block | AXI | Clock | Reset | IRQ Out | Fault In | Fault Out | External I/O |
|-------|-----|-------|-------|---------|----------|-----------|-------------|
| RV32IM Core | M | sys | sys | — | — | — | — |
| ITCM | — | sys | sys | — | — | parity_err | — |
| DTCM | — | sys | sys | — | — | parity_err | — |
| AXI Xbar | — | sys | sys | — | — | — | — |
| AI Accel | S | sys | sys | done, err | — | fault | — |
| SPI | S | sys | sys | rx, tx, err | — | fault | sck, mosi, miso, cs_n |
| Servo PWM | S | sys | sys | fault | — | fault | pwm |
| Speed Sensor | S | sys | sys | pulse, ovf | — | fault | pulse (in) |
| Buzzer PWM | S | sys | sys | done | — | — | pwm |
| UART | S | sys | sys | rx, tx | — | — | tx, rx |
| GPIO | S | sys | sys | [7:0] | force_shdn | — | gpio[31:0] |
| Safety Monitor | S | sys | sys | lockstep, agg | wdt, parity, etc | agg_fault | — |
| Window WDT | S (CDC) | wdt | wdt | prewarn | — | fault | — |
| RSC | — | wdt | wdt | — | agg_fault | — | shutdown_n, alert_n |

---

## Revision History

| Version | Date | Author | Description |
|---------|------|--------|-------------|
| 1.0 | 2026-04-29 | Kenji Tanaka | Initial block interface definitions |

---

*"Every signal named. Every direction specified. Every bit accounted for."*  
*— Kenji Tanaka, Chief Architect*
