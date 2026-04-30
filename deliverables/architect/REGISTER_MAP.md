# ADAS v2 — Memory-Mapped Register Map

**Document:** ARCH-RM-001 | **Version:** 1.0 | **Date:** 2026-04-29  
**Author:** Kenji Tanaka, Chief Architect  
**Address Range:** 0x0000_0000 – 0x0000_FFFF (64 KB peripherals + 16 KB TCM)  

---

## Table of Contents

1. [Address Map Overview](#1-address-map-overview)
2. [AI Accelerator Registers (0x1000–0x1FFF)](#2-ai-accelerator-registers-0x10000x1fff)
3. [SPI Controller Registers (0x2000–0x2FFF)](#3-spi-controller-registers-0x20000x2fff)
4. [Servo PWM Registers (0x3000–0x3FFF)](#4-servo-pwm-registers-0x30000x3fff)
5. [Speed Sensor Registers (0x4000–0x4FFF)](#5-speed-sensor-registers-0x40000x4fff)
6. [Buzzer PWM Registers (0x5000–0x5FFF)](#6-buzzer-pwm-registers-0x50000x5fff)
7. [UART Registers (0x6000–0x6FFF)](#7-uart-registers-0x60000x6fff)
8. [GPIO Registers (0x7000–0x7FFF)](#8-gpio-registers-0x70000x7fff)
9. [Safety Control Registers (0xF000–0xF0FF)](#9-safety-control-registers-0xf0000xf0ff)
10. [Window WDT Registers (0xF100–0xF1FF)](#10-window-wdt-registers-0xf1000xf1ff)
11. [Register Access Conventions](#11-register-access-conventions)

---

## 1. Address Map Overview

```
0x0000_0000 ┌──────────────────────────┐
            │     ITCM (8 KB)          │  CPU Instruction Memory
            │                          │  Read-only from CPU bus master
0x0000_2000 ├──────────────────────────┤
            │     DTCM (8 KB)          │  CPU Data Memory
            │                          │  Read/Write from CPU
0x0000_4000 ├──────────────────────────┤
            │     RESERVED             │  (0x1000–0x0FFF reserved for
            │      (48 KB)             │   TCM expansion)
0x0000_1000 ├──────────────────────────┤
            │  AI ACCELERATOR (4 KB)   │  0x1000 – 0x1FFF
0x0000_2000 ├──────────────────────────┤
            │  SPI CONTROLLER (4 KB)   │  0x2000 – 0x2FFF
0x0000_3000 ├──────────────────────────┤
            │  SERVO PWM (4 KB)        │  0x3000 – 0x3FFF
0x0000_4000 ├──────────────────────────┤
            │  SPEED SENSOR (4 KB)     │  0x4000 – 0x4FFF
0x0000_5000 ├──────────────────────────┤
            │  BUZZER PWM (4 KB)       │  0x5000 – 0x5FFF
0x0000_6000 ├──────────────────────────┤
            │  UART (4 KB)             │  0x6000 – 0x6FFF
0x0000_7000 ├──────────────────────────┤
            │  GPIO (4 KB)             │  0x7000 – 0x7FFF
0x0000_8000 ├──────────────────────────┤
            │     RESERVED             │  (0x8000 – 0xEFFF for future
            │      (28 KB)             │   peripherals)
0x0000_F000 ├──────────────────────────┤
            │  SAFETY CONTROL (256 B)  │  0xF000 – 0xF0FF
0x0000_F100 ├──────────────────────────┤
            │  WINDOW WDT (256 B)      │  0xF100 – 0xF1FF
0x0000_F200 ├──────────────────────────┤
            │     RESERVED             │  Future expansion
0x0000_FFFF └──────────────────────────┘
```

**Note:** Address space 0x0000_4000–0x0000_0FFF is reserved for future TCM expansion
(up to 64 KB total). ITCM at 0x00000000, DTCM at 0x00002000 is the standard RISC-V
layout. Peripherals begin at 0x00001000.

---

## 2. AI Accelerator Registers (0x1000–0x1FFF)

**Base:** `0x0000_1000`  
**Block:** 4×4 INT8 systolic array, weight-stationary dataflow

### Register Map

| Offset | Name | Width | Access | Reset | Description |
|--------|------|-------|--------|-------|-------------|
| 0x00 | AI_CTRL | 32 | RW | 0x0000_0000 | Control and status register |
| 0x04 | AI_STATUS | 32 | RO | 0x0000_0000 | Status register |
| 0x08 | AI_WEIGHT_0 | 32 | RW | 0x0000_0000 | Weights row 0: w00[7:0], w01[15:8], w02[23:16], w03[31:24] |
| 0x0C | AI_WEIGHT_1 | 32 | RW | 0x0000_0000 | Weights row 1: w10[7:0], w11[15:8], w12[23:16], w13[31:24] |
| 0x10 | AI_WEIGHT_2 | 32 | RW | 0x0000_0000 | Weights row 2: w20[7:0], w21[15:8], w22[23:16], w23[31:24] |
| 0x14 | AI_WEIGHT_3 | 32 | RW | 0x0000_0000 | Weights row 3: w30[7:0], w31[15:8], w32[23:16], w33[31:24] |
| 0x18 | AI_INPUT | 32 | RW | 0x0000_0000 | Input activations: a0[7:0], a1[15:8], a2[23:16], a3[31:24] |
| 0x1C | AI_BIAS_0_1 | 32 | RW | 0x0000_0000 | Biases: bias0[15:0], bias1[31:16] (INT16) |
| 0x20 | AI_BIAS_2_3 | 32 | RW | 0x0000_0000 | Biases: bias2[15:0], bias3[31:16] (INT16) |
| 0x24 | AI_OUTPUT_0 | 32 | RO | 0x0000_0000 | Output 0 (INT32 accumulated) |
| 0x28 | AI_OUTPUT_1 | 32 | RO | 0x0000_0000 | Output 1 (INT32 accumulated) |
| 0x2C | AI_OUTPUT_2 | 32 | RO | 0x0000_0000 | Output 2 (INT32 accumulated) |
| 0x30 | AI_OUTPUT_3 | 32 | RO | 0x0000_0000 | Output 3 (INT32 accumulated) |
| 0x34 | AI_ACTIVATION | 32 | RW | 0x0000_0000 | Activation function control |
| 0x38 | AI_SCALE | 32 | RW | 0x0000_1000 | Output scaling factor (fixed-point Q8.8) |
| 0x3C | AI_INTR_MASK | 32 | RW | 0x0000_0000 | Interrupt mask |
| 0x40–0xFF | — | — | — | — | Reserved |

### AI_CTRL (0x00)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | GO | RW (auto-clear) | Write '1' to start computation. Self-clears after launch. |
| 1 | BUSY | RO | '1' when computation in progress |
| 2 | DONE | RO (W1C) | '1' when computation complete. Write '1' to clear. |
| 3 | ERROR | RO (W1C) | '1' on error condition. Write '1' to clear. |
| 4 | RELU_EN | RW | Enable ReLU activation on output |
| 5 | QUANT_EN | RW | Enable output quantization |
| 7:6 | — | — | Reserved |
| 8 | CLK_EN | RW | Clock enable (1 = running, 0 = gated) |
| 9 | RST | RW | Software reset (self-clearing) |
| 31:10 | — | — | Reserved |

### AI_STATUS (0x04)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 3:0 | CYCLE_COUNT | RO | Computation cycle count (latency: 16 cycles for 4×4) |
| 7:4 | — | — | Reserved |
| 15:8 | ERROR_CODE | RO | Error code (see below) |
| 31:16 | — | — | Reserved |

**Error codes:**
| Code | Meaning |
|------|---------|
| 0x00 | No error |
| 0x01 | Weight buffer underflow (weights not fully loaded) |
| 0x02 | Output overflow (INT32 saturated) |
| 0x03 | Invalid activation function configuration |
| 0xFF | Internal hardware fault |

### AI_ACTIVATION (0x34)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | ACT_NONE | RW | No activation (raw output) |
| 1 | ACT_RELU | RW | ReLU (max(0, x)) |
| 2 | ACT_SIGMOID | RW | Sigmoid approximation (LUT-based) |
| 3 | ACT_TANH | RW | TanH approximation (LUT-based) |
| 31:4 | — | — | Reserved |

### AI_INTR_MASK (0x3C)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | DONE_IE | RW | Interrupt enable on computation done |
| 1 | ERROR_IE | RW | Interrupt enable on error |
| 31:2 | — | — | Reserved |

---

## 3. SPI Controller Registers (0x2000–0x2FFF)

**Base:** `0x0000_2000`  
**Block:** SPI Master controller for LIDAR sensor

### Register Map

| Offset | Name | Width | Access | Reset | Description |
|--------|------|-------|--------|-------|-------------|
| 0x00 | SPI_CTRL | 32 | RW | 0x0000_0000 | Control register |
| 0x04 | SPI_STATUS | 32 | RO | 0x0000_0005 | Status register |
| 0x08 | SPI_CLKDIV | 32 | RW | 0x0000_0004 | Clock divider (SCK = sys_clk / (2 × DIV)) |
| 0x0C | SPI_TXDATA | 32 | WO | — | Transmit data register |
| 0x10 | SPI_RXDATA | 32 | RO | 0x0000_0000 | Receive data register |
| 0x14 | SPI_CS | 32 | RW | 0x0000_000F | Chip select control |
| 0x18 | SPI_INTR_MASK | 32 | RW | 0x0000_0000 | Interrupt mask |
| 0x1C | SPI_INTR_STATUS | 32 | RO | 0x0000_0000 | Interrupt status |
| 0x20–0xFF | — | — | — | — | Reserved |

### SPI_CTRL (0x00)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | ENABLE | RW | SPI enable |
| 1 | CPOL | RW | Clock polarity (0=idle low, 1=idle high) |
| 2 | CPHA | RW | Clock phase (0=first edge, 1=second edge) |
| 3 | MSTEN | RW | Master enable (always 1) |
| 4 | LSBFE | RW | LSB first (0=MSB first, 1=LSB first) |
| 5 | AUTOCS | RW | Automatic chip select assertion |
| 7:6 | — | — | Reserved |
| 8 | TX_FIFO_CLR | WO | Clear TX FIFO |
| 9 | RX_FIFO_CLR | WO | Clear RX FIFO |
| 10 | CLK_EN | RW | Clock enable |
| 11 | SOFT_RST | RW | Software reset (self-clearing) |
| 31:12 | — | — | Reserved |

### SPI_STATUS (0x04)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | TX_FIFO_EMPTY | RO | TX FIFO empty |
| 1 | TX_FIFO_FULL | RO | TX FIFO full (8 bytes) |
| 2 | RX_FIFO_EMPTY | RO | RX FIFO empty |
| 3 | RX_FIFO_FULL | RO | RX FIFO full |
| 4 | TX_BUSY | RO | Transmission in progress |
| 7:5 | — | — | Reserved |
| 11:8 | TX_FIFO_COUNT | RO | TX FIFO level (0-8) |
| 15:12 | RX_FIFO_COUNT | RO | RX FIFO level (0-8) |
| 31:16 | — | — | Reserved |

### SPI_CLKDIV (0x08)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 15:0 | DIVIDER | RW | Clock divider: SCK = sys_clk / (2 × DIVIDER) |
| 31:16 | — | — | Reserved |

**Common divider values @ 100 MHz:**
| DIVIDER | SCK Freq |
|---------|----------|
| 2 | 25.0 MHz |
| 4 | 12.5 MHz |
| 5 | 10.0 MHz |
| 10 | 5.0 MHz |
| 100 | 500 kHz |

### SPI_TXDATA (0x0C)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 7:0 | DATA | WO | Transmit data byte (written to TX FIFO) |
| 31:8 | — | — | Reserved |

### SPI_RXDATA (0x10)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 7:0 | DATA | RO | Received data byte (read from RX FIFO) |
| 31:8 | — | — | Reserved |

### SPI_CS (0x14)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 3:0 | CS_MASK | RW | CS active mask (bit 0 = CS0, active low) |
| 31:4 | — | — | Reserved |

### SPI_INTR_MASK (0x18) / SPI_INTR_STATUS (0x1C)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | RX_AVAILABLE | RW/RO | RX FIFO not empty |
| 1 | TX_EMPTY | RW/RO | TX FIFO empty |
| 2 | ERROR | RW/RO | Mode fault / overflow |
| 3 | RX_FULL | RW/RO | RX FIFO full |
| 4 | TX_COMPLETE | RW/RO | All bytes transmitted |
| 31:5 | — | — | Reserved |

---

## 4. Servo PWM Registers (0x3000–0x3FFF)

**Base:** `0x0000_3000`  
**Block:** Servo PWM controller (braking actuator)

### Register Map

| Offset | Name | Width | Access | Reset | Description |
|--------|------|-------|--------|-------|-------------|
| 0x00 | SERVO_CTRL | 32 | RW | 0x0000_0000 | Control register |
| 0x04 | SERVO_PERIOD | 32 | RW | 0x001E_8480 | PWM period in sys_clk cycles (default: 20ms @ 100MHz = 2,000,000) |
| 0x08 | SERVO_DUTY | 32 | RW | 0x0002_49F0 | Duty cycle in sys_clk cycles (default: 1500µs = 150,000) |
| 0x0C | SERVO_SAFE_DUTY | 32 | RW | 0x0002_49F0 | Safe/neutral position duty (1500µs = 150,000 cycles) |
| 0x10 | SERVO_STATUS | 32 | RO | 0x0000_0000 | Status register |
| 0x14 | SERVO_FAULT_LIMIT | 32 | RW | 0x0000_03E8 | Fault debounce cycles |
| 0x18 | SERVO_INTR_MASK | 32 | RW | 0x0000_0000 | Interrupt mask |
| 0x1C | SERVO_INTR_STATUS | 32 | RO | 0x0000_0000 | Interrupt status |
| 0x20 | SERVO_DUTY_US | 32 | RW | 0x0000_05DC | Duty cycle in µs (alternative: 1500) |
| 0x24–0xFF | — | — | — | — | Reserved |

### SERVO_CTRL (0x00)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | ENABLE | RW | PWM output enable |
| 1 | SAFE_MODE | RW | Force safe (neutral) duty cycle |
| 2 | US_MODE | RW | Use SERVO_DUTY_US register (µs) instead of SERVO_DUTY (cycles) |
| 3 | FAULT_EN | RW | Enable fault detection (readback compare) |
| 4 | FAULT_ACTION | RW | 0=goto safe, 1=disable on fault |
| 7:5 | — | — | Reserved |
| 8 | CLK_EN | RW | Clock enable |
| 9 | SOFT_RST | RW | Software reset (self-clearing) |
| 31:10 | — | — | Reserved |

### SERVO_PERIOD (0x04)

PWM period in system clock cycles. Default: 2,000,000 (20 ms @ 100 MHz).

| Period (ms) | sys_clk Cycles |
|-------------|----------------|
| 20 (standard) | 2,000,000 |
| 10 | 1,000,000 |
| 5 | 500,000 |

### SERVO_DUTY (0x08)

Duty cycle / high time in system clock cycles.

| Position | Pulse Width | Cycles @ 100 MHz |
|----------|-------------|------------------|
| 0° (min) | 500 µs | 50,000 |
| 90° (neutral) | 1500 µs | 150,000 |
| 180° (max) | 2500 µs | 250,000 |

### SERVO_DUTY_US (0x20)

Duty cycle in microseconds (used when US_MODE = 1).
Value range: 500 – 2500.

### SERVO_STATUS (0x10)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | RUNNING | RO | PWM output active |
| 1 | AT_SAFE | RO | Currently at safe position |
| 2 | FAULT | RO | Fault detected (stuck-at) |
| 3 | FAULT_LATCHED | RO (W1C) | Fault latched (write 1 to clear) |
| 31:4 | — | — | Reserved |

### SERVO_INTR_MASK (0x18) / SERVO_INTR_STATUS (0x1C)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | FAULT_IE/IS | RW/RO | Fault interrupt |
| 1 | PERIOD_DONE_IE/IS | RW/RO | PWM period complete |
| 31:2 | — | — | Reserved |

---

## 5. Speed Sensor Registers (0x4000–0x4FFF)

**Base:** `0x0000_4000`  
**Block:** Wheel speed sensor pulse counter with timestamps

### Register Map

| Offset | Name | Width | Access | Reset | Description |
|--------|------|-------|--------|-------|-------------|
| 0x00 | SPEED_CTRL | 32 | RW | 0x0000_0000 | Control register |
| 0x04 | SPEED_STATUS | 32 | RO | 0x0000_0000 | Status register |
| 0x08 | SPEED_COUNT | 32 | RO | 0x0000_0000 | Pulse count (32-bit, rollover) |
| 0x0C | SPEED_TIMESTAMP_L | 32 | RO | 0x0000_0000 | Last pulse timestamp [31:0] (sys_clk cycles) |
| 0x10 | SPEED_TIMESTAMP_H | 32 | RO | 0x0000_0000 | Last pulse timestamp [63:32] |
| 0x14 | SPEED_PERIOD_L | 32 | RO | 0x0000_0000 | Period between last 2 pulses [31:0] |
| 0x18 | SPEED_PERIOD_H | 32 | RO | 0x0000_0000 | Period between last 2 pulses [63:32] |
| 0x1C | SPEED_STUCK_TIMEOUT | 32 | RW | 0x0000_FFFF | Stuck sensor timeout (sys_clk cycles) |
| 0x20 | SPEED_CAPTURE_COUNT | 32 | RO | 0x0000_0000 | Last captured count (latched on read of PERIOD_L) |
| 0x24 | SPEED_INTR_MASK | 32 | RW | 0x0000_0000 | Interrupt mask |
| 0x28 | SPEED_INTR_STATUS | 32 | RO | 0x0000_0000 | Interrupt status |
| 0x2C | SPEED_COUNT_MAX | 32 | RW | 0xFFFF_FFFF | Counter overflow threshold |
| 0x30–0xFF | — | — | — | — | Reserved |

### SPEED_CTRL (0x00)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | ENABLE | RW | Sensor interface enable |
| 1 | CLR_COUNT | WO | Clear pulse counter (self-clearing) |
| 2 | CLR_TIMESTAMP | WO | Clear timestamp (self-clearing) |
| 3 | STUCK_DET_EN | RW | Enable stuck sensor detection |
| 4 | STUCK_ACTION | RW | 0=IRQ only, 1=IRQ + fault on stuck |
| 7:5 | — | — | Reserved |
| 8 | CLK_EN | RW | Clock enable |
| 9 | SOFT_RST | RW | Software reset (self-clearing) |
| 31:10 | — | — | Reserved |

### SPEED_STATUS (0x04)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | PULSE_DETECTED | RO (W1C) | Pulse detected since last clear |
| 1 | SENSOR_STUCK | RO | No pulse within STUCK_TIMEOUT period |
| 2 | COUNT_OVF | RO (W1C) | Counter overflow |
| 15:3 | — | — | Reserved |
| 31:16 | PULSE_RATE | RO | Estimated pulse rate (pulses/sec), updated each pulse |

### Speed Calculation (Firmware)

```
period = (SPEED_PERIOD_H << 32) | SPEED_PERIOD_L   // in sys_clk cycles
if (period > 0) {
    frequency = 100_000_000.0 / period;              // pulses/sec
    speed_mps = frequency * wheel_circumference_m;   // meters/sec
    speed_kmh = speed_mps * 3.6;                     // km/h
}
```

---

## 6. Buzzer PWM Registers (0x5000–0x5FFF)

**Base:** `0x0000_5000`  
**Block:** Audible alert buzzer PWM

### Register Map

| Offset | Name | Width | Access | Reset | Description |
|--------|------|-------|--------|-------|-------------|
| 0x00 | BUZZER_CTRL | 32 | RW | 0x0000_0000 | Control register |
| 0x04 | BUZZER_PERIOD | 32 | RW | 0x0000_2710 | PWM period (sys_clk cycles); default 100µs (10kHz) |
| 0x08 | BUZZER_DUTY | 32 | RW | 0x0000_1388 | Duty cycle (50% default = 50µs) |
| 0x0C | BUZZER_BURST_ON | 32 | RW | 0x0000_0000 | Burst ON cycles (0=continuous) |
| 0x10 | BUZZER_BURST_OFF | 32 | RW | 0x0000_0000 | Burst OFF cycles |
| 0x14 | BUZZER_BURST_COUNT | 32 | RW | 0x0000_0000 | Burst repeat count (0=infinite) |
| 0x18 | BUZZER_STATUS | 32 | RO | 0x0000_0000 | Status register |
| 0x1C | BUZZER_INTR_MASK | 32 | RW | 0x0000_0000 | Interrupt mask |
| 0x20 | BUZZER_INTR_STATUS | 32 | RO | 0x0000_0000 | Interrupt status |
| 0x24–0xFF | — | — | — | — | Reserved |

### BUZZER_CTRL (0x00)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | ENABLE | RW | PWM output enable |
| 1 | BURST_EN | RW | Enable burst mode |
| 2 | INVERT | RW | Invert output polarity |
| 7:3 | — | — | Reserved |
| 8 | CLK_EN | RW | Clock enable |
| 9 | SOFT_RST | RW | Software reset (self-clearing) |
| 31:10 | — | — | Reserved |

### Tone Reference

| Frequency | BUZZER_PERIOD @ 100 MHz | Sound |
|-----------|--------------------------|-------|
| 1 kHz | 100,000 | Low tone |
| 2 kHz | 50,000 | Mid tone |
| 4 kHz | 25,000 | High tone |
| 8 kHz | 12,500 | Very high (annoying) |

---

## 7. UART Registers (0x6000–0x6FFF)

**Base:** `0x0000_6000`  
**Block:** 16550-compatible UART (debug console)

### Register Map

| Offset | Name | Width | Access | Reset | Description |
|--------|------|-------|--------|-------|-------------|
| 0x00 | UART_RBR | 32 | RO | 0x0000_0000 | Receiver Buffer Register (DLAB=0) |
| 0x00 | UART_THR | 32 | WO | — | Transmitter Holding Register (DLAB=0) |
| 0x00 | UART_DLL | 32 | RW | 0x0000_0001 | Divisor Latch LSB (DLAB=1) |
| 0x04 | UART_DLM | 32 | RW | 0x0000_0000 | Divisor Latch MSB (DLAB=1) |
| 0x04 | UART_IER | 32 | RW | 0x0000_0000 | Interrupt Enable Register (DLAB=0) |
| 0x08 | UART_IIR | 32 | RO | 0x0000_0001 | Interrupt Identification Register |
| 0x08 | UART_FCR | 32 | WO | — | FIFO Control Register |
| 0x0C | UART_LCR | 32 | RW | 0x0000_0000 | Line Control Register |
| 0x10 | UART_MCR | 32 | RW | 0x0000_0000 | Modem Control Register |
| 0x14 | UART_LSR | 32 | RO | 0x0000_0060 | Line Status Register |
| 0x18 | UART_MSR | 32 | RO | 0x0000_0000 | Modem Status Register |
| 0x1C | UART_SCR | 32 | RW | 0x0000_0000 | Scratch Register |
| 0x20–0xFF | — | — | — | — | Reserved |

### UART_LCR (0x0C) — Line Control Register

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 1:0 | WLS | RW | Word length: 00=5, 01=6, 10=7, 11=8 bits |
| 2 | STB | RW | Stop bits: 0=1, 1=1.5/2 |
| 5:3 | PEN | RW | Parity: 000=None, 001=Odd, 011=Even, 101=Mark, 111=Space |
| 6 | BRK | RW | Break control |
| 7 | DLAB | RW | Divisor Latch Access Bit |

### UART_LSR (0x14) — Line Status Register

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | DR | RO | Data Ready (RX FIFO not empty) |
| 1 | OE | RO | Overrun Error |
| 2 | PE | RO | Parity Error |
| 3 | FE | RO | Framing Error |
| 4 | BI | RO | Break Interrupt |
| 5 | THRE | RO | THR Empty (TX FIFO can accept data) |
| 6 | TEMT | RO | TX FIFO + Shift Register Empty |
| 7 | RXFIFOERR | RO | RX FIFO error |

### Baud Rate Configuration

| Baud Rate | Divisor (sys_clk = 100 MHz) | DLL | DLM |
|-----------|------------------------------|-----|-----|
| 9600 | 651 | 0x8B | 0x02 |
| 19200 | 326 | 0x46 | 0x01 |
| 38400 | 163 | 0xA3 | 0x00 |
| 57600 | 108 | 0x6C | 0x00 |
| 115200 | 54 | 0x36 | 0x00 |
| 921600 | 7 | 0x07 | 0x00 |

Formula: Divisor = sys_clk / (16 × baud_rate)

---

## 8. GPIO Registers (0x7000–0x7FFF)

**Base:** `0x0000_7000`  
**Block:** 32-bit General Purpose I/O with interrupt capability

### Register Map

| Offset | Name | Width | Access | Reset | Description |
|--------|------|-------|--------|-------|-------------|
| 0x00 | GPIO_DATA | 32 | RW | 0x0000_0000 | GPIO data value |
| 0x04 | GPIO_DIR | 32 | RW | 0x0000_FFFF | Direction: 0=input, 1=output |
| 0x08 | GPIO_OUT | 32 | RW | 0x0000_0000 | Output data set |
| 0x0C | GPIO_IN | 32 | RO | — | Input data read |
| 0x10 | GPIO_SET | 32 | WO | — | Bit-set register (write 1 to set) |
| 0x14 | GPIO_CLR | 32 | WO | — | Bit-clear register (write 1 to clear) |
| 0x18 | GPIO_TOG | 32 | WO | — | Bit-toggle register |
| 0x1C | GPIO_INT_EN | 32 | RW | 0x0000_0000 | Interrupt enable per pin [7:0] |
| 0x20 | GPIO_INT_TYPE | 32 | RW | 0x0000_0000 | Interrupt type: 0=level, 1=edge [7:0] |
| 0x24 | GPIO_INT_POLARITY | 32 | RW | 0x0000_0000 | Interrupt polarity: 0=low/falling, 1=high/rising [7:0] |
| 0x28 | GPIO_INT_STATUS | 32 | RO (W1C) | 0x0000_0000 | Interrupt status (write 1 to clear) |
| 0x2C | GPIO_INT_ACK | 32 | WO | — | Interrupt acknowledge (write 1 to clear) |
| 0x30 | GPIO_PULL_EN | 32 | RW | 0x0000_0000 | Pull-up/down enable |
| 0x34 | GPIO_PULL_SEL | 32 | RW | 0x0000_0000 | Pull select: 0=pull-down, 1=pull-up |
| 0x38 | GPIO_DRIVE | 32 | RW | 0x0000_0000 | Drive strength: 0=2mA, 1=4mA, 2=8mA, 3=12mA |
| 0x3C | GPIO_SAFETY | 32 | RW | 0x0000_0007 | Safety pin lock (pins 2:0 locked after write) |
| 0x40 | GPIO_CTRL | 32 | RW | 0x0000_0000 | Control register |
| 0x44–0xFF | — | — | — | — | Reserved |

### GPIO_DATA / GPIO_OUT / GPIO_SET / GPIO_CLR / GPIO_TOG

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 31:0 | DATA | varies | One bit per GPIO pin |

**Note on SET/CLR/TOG:** Writing a '1' to a bit in these registers performs the
corresponding action on that pin. Writing '0' has no effect. This enables atomic
bit manipulation without read-modify-write.

### GPIO_SAFETY (0x3C)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | LOCK_ALERT | RW (lock) | Lock GPIO[0] (ALERT_OUT) direction/output |
| 1 | LOCK_SHDN_A | RW (lock) | Lock GPIO[1] (SHUTDOWN_A) direction/output |
| 2 | LOCK_SHDN_B | RW (lock) | Lock GPIO[2] (SHUTDOWN_B) direction/output |
| 3 | LOCKED | RO | All safety pins locked (write-once) |
| 31:4 | — | — | Reserved |

Once a safety lock bit is set to '1', it cannot be cleared except by hard reset.
The LOCKED bit becomes '1' when all three lock bits are set.

### GPIO_CTRL (0x40)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | CLK_EN | RW | GPIO module clock enable |
| 1 | SOFT_RST | RW | Software reset (self-clearing) |
| 31:2 | — | — | Reserved |

---

## 9. Safety Control Registers (0xF000–0xF0FF)

**Base:** `0x0000_F000`  
**Block:** Safety monitor — lockstep comparator, fault aggregator configuration

### Register Map

| Offset | Name | Width | Access | Reset | Description |
|--------|------|-------|--------|-------|-------------|
| 0x00 | SAFETY_CTRL | 32 | RW | 0x0000_0000 | Safety control register |
| 0x04 | SAFETY_STATUS | 32 | RO | 0x0000_0000 | Safety status register |
| 0x08 | SAFETY_FAULT_MASK | 32 | RW | 0x0000_FFFF | Fault source mask |
| 0x0C | SAFETY_FAULT_STATUS | 32 | RO (W1C) | 0x0000_0000 | Latched fault status |
| 0x10 | SAFETY_FAULT_COUNT | 32 | RO | 0x0000_0000 | Total fault count (saturating) |
| 0x14 | SAFETY_LOCKSTEP_CTRL | 32 | RW | 0x0000_0000 | Lockstep comparator control |
| 0x18 | SAFETY_LOCKSTEP_MASK | 32 | RW | 0xFFFF_FFFF | Lockstep signal mask |
| 0x1C | SAFETY_LOCKSTEP_MISMATCH | 32 | RO | 0x0000_0000 | Lockstep mismatch counter (legacy — see 0x20) |
| 0x20 | SAFETY_LOCKSTEP_MISMATCH_COUNT | 32 | RO | 0x0000_0000 | Dual-core lockstep mismatch counter (saturating) |
| 0x24 | SAFETY_LOCKSTEP_MASK | 32 | RW | 0x0000_0000 | Lockstep comparison bit mask (0=ignore, 1=compare) |
| 0x28 | SAFETY_LOCKSTEP_LAST_PC | 32 | RO | 0x0000_0000 | PC at last lockstep mismatch |
| 0x2C | SAFETY_LOCKSTEP_LAST_MASTER | 32 | RO | 0x0000_0000 | Master core masked output at last mismatch |
| 0x30 | SAFETY_LOCKSTEP_LAST_CHECKER | 32 | RO | 0x0000_0000 | Checker core masked output at last mismatch |
| 0x34 | SAFETY_SCRATCH | 32 | RW | 0x0000_0000 | Scratch/test register |
| 0x38 | SAFETY_INTR_MASK | 32 | RW | 0x0000_0000 | Safety interrupt mask |
| 0x3C | SAFETY_INTR_STATUS | 32 | RO | 0x0000_0000 | Safety interrupt status |
| 0x40 | SAFETY_RESET_CTRL | 32 | RW | 0x0000_0000 | Software-initiated reset control |
| 0x44 | SAFETY_ID | 32 | RO | 0x5346_5459 | Safety module ID ("SFTY") |
| 0x48–0xFF | — | — | — | — | Reserved |

### SAFETY_CTRL (0x00)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | ENABLE | RW | Safety monitor enable |
| 1 | LOCKSTEP_EN | RW | Lockstep comparison enable |
| 2 | FAULT_AGG_EN | RW | Fault aggregation enable |
| 3 | AUTO_HALT | RW | Auto-halt CPU on critical fault |
| 4 | AUTO_SHUTDOWN | RW | Auto-shutdown on aggregated fault |
| 7:5 | — | — | Reserved |
| 8 | FORCE_FAULT | RW | Test: force fault condition |
| 9 | FORCE_MISMATCH | RW | Test: force lockstep mismatch |
| 10 | TEST_MODE | RW | Safety test mode (bypasses auto-shutdown) |
| 15:11 | — | — | Reserved |
| 23:16 | FAULT_SEVERITY | RW | Minimum severity for aggregated_fault output (0=any) |
| 31:24 | — | — | Reserved |

### SAFETY_STATUS (0x04)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | ENABLED | RO | Safety monitor active |
| 1 | LOCKSTEP_ACTIVE | RO | Lockstep comparison active |
| 2 | ANY_FAULT | RO | Any fault currently asserted |
| 3 | CRITICAL_FAULT | RO | Critical fault asserted |
| 4 | HALTED | RO | CPU halted by safety monitor |
| 5 | SHUTDOWN | RO | Shutdown sequence initiated |
| 7:6 | — | — | Reserved |
| 31:8 | FAULT_STATE | RO | Per-source fault state (see SAFETY_FAULT_MASK) |

### SAFETY_FAULT_MASK (0x08) / SAFETY_FAULT_STATUS (0x0C)

| Bit(s) | Source | Severity | Description |
|--------|--------|----------|-------------|
| 0 | LOCKSTEP_MISMATCH | CRITICAL | Lockstep comparison mismatch |
| 1 | WDT_TIMEOUT | CRITICAL | Watchdog timer timeout |
| 2 | WDT_EARLY | HIGH | WDT refreshed outside open window |
| 3 | SERVO_FAULT | HIGH | Servo PWM fault |
| 4 | AI_FAULT | HIGH | AI accelerator fault |
| 5 | SPI_FAULT | MEDIUM | SPI communication error |
| 6 | SPEED_STUCK | MEDIUM | Speed sensor stuck |
| 7 | ITCM_PARITY | CRITICAL | ITCM parity error |
| 8 | DTCM_PARITY | CRITICAL | DTCM parity error |
| 9 | GPIO_SHUTDOWN_ACK | HIGH | External shutdown acknowledge |
| 10 | AXI_DECODE_ERR | MEDIUM | AXI decode error (unmapped access) |
| 11 | SOFTWARE_FAULT | HIGH | Software-triggered fault |
| 31:12 | — | — | Reserved |

**FAULT_MASK:** Write '1' to enable fault propagation.  
**FAULT_STATUS:** Read '1' = fault latched. Write '1' to clear (if source de-asserted).

### SAFETY_LOCKSTEP_CTRL (0x14)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | ENABLE | RW | Lockstep comparator enable |
| 1 | DELAY_EN | RW | Enable 2-cycle delay compensation |
| 3:2 | DELAY_CYCLES | RW | Delay cycles: 00=1, 01=2, 10=3, 11=4 |
| 7:4 | THRESHOLD | RW | Mismatch threshold before fault (0=any) |
| 31:8 | — | — | Reserved |

### SAFETY_LOCKSTEP_MISMATCH_COUNT (0x20)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 31:0 | COUNT | RO | Dual-core lockstep mismatch counter. Increments on each lockstep mismatch event. Saturates at 0xFFFF_FFFF. Reset to 0 on system reset. Read-only from firmware; hardware-auto-incremented by lockstep comparator. |

### SAFETY_LOCKSTEP_MASK (0x24)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 31:0 | MASK | RW | Lockstep comparison bit mask. Each bit: 0 = ignore this bit in lockstep comparison, 1 = compare this bit. Default: 0x0000_0000 (lockstep comparison disabled until configured). Firmware should write 0xFFFF_FFFF to enable full comparison, or a selective mask to exclude known-safe divergences (e.g., performance counters). |

### SAFETY_LOCKSTEP_LAST_PC (0x28)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 31:0 | LAST_PC | RO | Program counter of the master core at the most recent lockstep mismatch. Latched on mismatch event. |

### SAFETY_LOCKSTEP_LAST_MASTER (0x2C)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 31:0 | LAST_MASTER | RO | Masked output of the master core at the most recent lockstep mismatch. Latched on mismatch event for diagnostic use. |

### SAFETY_LOCKSTEP_LAST_CHECKER (0x30)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 31:0 | LAST_CHECKER | RO | Masked output of the checker core at the most recent lockstep mismatch. Latched on mismatch event for diagnostic use. |

### SAFETY_RESET_CTRL (0x40)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | CPU_RESET | RW | Assert CPU reset (self-clearing) |
| 1 | PERIPH_RESET | RW | Assert peripheral reset (self-clearing) |
| 2 | AI_RESET | RW | Assert AI accelerator reset (self-clearing) |
| 31:3 | — | — | Reserved |

**Security:** Writing to SAFETY_RESET_CTRL requires writing magic key 0xA5 to
SAFETY_SCRATCH first. This prevents accidental reset from stray writes.

---

## 10. Window WDT Registers (0xF100–0xF1FF)

**Base:** `0x0000_F100`  
**Block:** Window Watchdog Timer (wdt_clk domain)

### Register Map

| Offset | Name | Width | Access | Reset | Description |
|--------|------|-------|--------|-------|-------------|
| 0x00 | WDT_CTRL | 32 | RW | 0x0000_0000 | Control register |
| 0x04 | WDT_TIMEOUT | 32 | RW | 0x0000_0CCD | Timeout period (default: 3277 = ~100ms @ 32.768kHz) |
| 0x08 | WDT_WINDOW | 32 | RW | 0x0000_0998 | Open window start (default: 75% of timeout = 2458) |
| 0x0C | WDT_COUNT | 32 | RO | 0x0000_0000 | Current counter value |
| 0x10 | WDT_KICK | 32 | WO | — | Watchdog refresh (write 0xAC53_CAFE to kick) |
| 0x14 | WDT_STATUS | 32 | RO | 0x0000_0000 | Status register |
| 0x18 | WDT_PREWARN | 32 | RW | 0x0000_0A00 | Pre-warning threshold |
| 0x1C | WDT_INTR_MASK | 32 | RW | 0x0000_0000 | Interrupt mask |
| 0x20 | WDT_INTR_STATUS | 32 | RO | 0x0000_0000 | Interrupt status |
| 0x24 | WDT_LOCK | 32 | RW | 0x0000_0000 | Configuration lock register |
| 0x28 | WDT_ID | 32 | RO | 0x5744_5400 | WDT module ID ("WDT\0") |
| 0x2C–0xFF | — | — | — | — | Reserved |

### WDT_CTRL (0x00)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | ENABLE | RW (lockable) | WDT enable (once set, cannot clear except reset) |
| 1 | WINDOW_EN | RW (lockable) | Enable window mode |
| 2 | PREWARN_EN | RW | Enable pre-warning interrupt |
| 3 | RESET_EN | RW (lockable) | Enable WDT-triggered system reset |
| 7:4 | — | — | Reserved |
| 15:8 | KEY | WO | Write key: 0x5A required to modify bits [3:0] |
| 31:16 | — | — | Reserved |

**WRITE PROTOCOL:** To write CTRL[3:0], write upper byte as 0x5A simultaneously.
Example: to enable WDT with window mode and reset: write `0x0000_5A0D`.

### WDT_TIMEOUT (0x04)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 31:0 | TIMEOUT | RW (lockable) | Timeout in wdt_clk ticks (32.768 kHz) |
|  | | | **Min:** 1 tick (~30.5 µs) |
|  | | | **Max:** 2^32-1 ticks (~36.4 hours) |
|  | | | **Default:** 3277 ticks (~100 ms) |

### WDT_WINDOW (0x08)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 31:0 | WINDOW | RW (lockable) | Open window start (counter value where refresh becomes valid) |

Window behavior:
```
Count: 0 ───────────────→ WINDOW ──────────────→ TIMEOUT ──→ FAULT
        [ CLOSED WINDOW ]         [ OPEN WINDOW ]
        Refresh → FAULT          Refresh → OK
```

### WDT_KICK (0x10)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 31:0 | KICK_VALUE | WO | Write `0xAC53_CAFE` to refresh watchdog |

**Refresh sequence:**
1. Wait until WDT_COUNT > WDT_WINDOW (open window)
2. Write `0xAC53_CAFE` to WDT_KICK
3. WDT counter resets to 0
4. Window closes, reopens at WINDOW threshold

### WDT_STATUS (0x14)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | RUNNING | RO | WDT counting |
| 1 | IN_WINDOW | RO | Open window (refresh valid) |
| 2 | PREWARNED | RO | Pre-warning threshold reached |
| 3 | TIMED_OUT | RO (W1C) | Timeout occurred (latched) |
| 4 | EARLY_KICK | RO (W1C) | Refresh during closed window |
| 31:5 | — | — | Reserved |

### WDT_LOCK (0x24)

| Bit(s) | Name | Access | Description |
|--------|------|--------|-------------|
| 0 | LOCK_CTRL | RW (one-time) | Lock CTRL register |
| 1 | LOCK_TIMEOUT | RW (one-time) | Lock TIMEOUT register |
| 2 | LOCK_WINDOW | RW (one-time) | Lock WINDOW register |
| 3 | ALL_LOCKED | RO | All registers locked |
| 31:4 | — | — | Reserved |

Once a lock bit is set, the corresponding register becomes read-only until POR reset.

---

## 11. Register Access Conventions

### 11.1 Access Types

| Type | Meaning | Behavior |
|------|---------|----------|
| RO | Read Only | Write ignored |
| RW | Read/Write | Normal read/write |
| WO | Write Only | Read returns 0 |
| RW (lockable) | Read/Write with lock | Write locked after WDT_LOCK set |
| RW (one-time) | Write once, then RO | After first write of '1', becomes RO |
| RO (W1C) | Read, Write-1-to-Clear | Write '1' to clear latched bits |
| WO (self-clearing) | Write triggers action | Bit auto-clears after action completes |
| RW (auto-clear) | Read/Write, auto-clear | Bit self-clears after operation |

### 11.2 Register Addressing Rules

1. All registers are 32-bit aligned (address [1:0] = 00).
2. Unused address space within a peripheral block returns `0x00000000` on read,
   writes are ignored.
3. Reserved bits must be written as '0' and ignored on read.
4. Full-word writes recommended; byte/halfword writes supported via AXI4-Lite wstrb.
5. A write to the WDT register block goes through CDC-01 (handshake). See `cdc_plan.md`.

### 11.3 Reset Values

Reset values apply after:
- Power-on reset (sys_rst_n de-assertion)
- Software reset via per-block SOFT_RST bit
- System reset via SAFETY_RESET_CTRL

WDT registers are reset only by wdt_rst_n (POR).

### 11.4 Interrupt Handling Flow

```
1. Peripheral asserts IRQ line
2. CPU reads peripheral INTR_STATUS register
3. CPU services the interrupt
4. CPU writes to INTR_ACK or W1C to clear the status bit
5. Peripheral deasserts IRQ line
6. CPU returns from interrupt handler
```

### 11.5 Atomic Access

For registers that require atomic read-modify-write (e.g., GPIO_SET/CLR/TOG),
the hardware supports direct bit-set/clear/toggle without RMV:
- Write `1` to GPIO_SET bit N → sets GPIO output bit N
- Write `1` to GPIO_CLR bit N → clears GPIO output bit N
- Write `1` to GPIO_TOG bit N → toggles GPIO output bit N
- Writing `0` to any bit has no effect

---

## Register Quick Reference

| Peripheral | Base Address | Key Registers |
|------------|-------------|---------------|
| AI Accelerator | 0x0000_1000 | CTRL(0x00), WEIGHT(0x08-0x14), INPUT(0x18), OUTPUT(0x24-0x30) |
| SPI Controller | 0x0000_2000 | CTRL(0x00), STATUS(0x04), CLKDIV(0x08), TXDATA(0x0C), RXDATA(0x10) |
| Servo PWM | 0x0000_3000 | CTRL(0x00), PERIOD(0x04), DUTY(0x08), DUTY_US(0x20) |
| Speed Sensor | 0x0000_4000 | CTRL(0x00), COUNT(0x08), TIMESTAMP(0x0C-0x10), PERIOD(0x14-0x18) |
| Buzzer PWM | 0x0000_5000 | CTRL(0x00), PERIOD(0x04), DUTY(0x08), BURST(0x0C-0x14) |
| UART | 0x0000_6000 | RBR/THR(0x00), LCR(0x0C), LSR(0x14) |
| GPIO | 0x0000_7000 | DATA(0x00), DIR(0x04), SET(0x10), CLR(0x14), TOG(0x18) |
| Safety Control | 0x0000_F000 | CTRL(0x00), STATUS(0x04), FAULT_MASK(0x08), FAULT_STATUS(0x0C) |
| Window WDT | 0x0000_F100 | CTRL(0x00), TIMEOUT(0x04), WINDOW(0x08), KICK(0x10) |

---

## Revision History

| Version | Date | Author | Description |
|---------|------|--------|-------------|
| 1.0 | 2026-04-29 | Kenji Tanaka | Initial register map |

---

*"Every register numbered. Every bit named. Every address unique. The programmer's contract begins here."*  
*— Kenji Tanaka, Chief Architect*
