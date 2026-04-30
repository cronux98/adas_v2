# ADAS v2 — Coverage Model Specification

**Document:** VER-COV-001 | **Version:** 1.0 | **Date:** 2026-04-29  
**Author:** Rahul Sharma, Verification Lead  
**Target:** 100% code + functional + cross coverage  

---

## Table of Contents

1. [Coverage Strategy Overview](#1-coverage-strategy-overview)
2. [Code Coverage Targets](#2-code-coverage-targets)
3. [Functional Coverage by Module](#3-functional-coverage-by-module)
4. [Cross-Coverage Specifications](#4-cross-coverage-specifications)
5. [Coverage Collection Infrastructure](#5-coverage-collection-infrastructure)
6. [Coverage Closure Plan](#6-coverage-closure-plan)

---

## 1. Coverage Strategy Overview

### 1.1 Three-Layer Coverage Model

```
┌──────────────────────────────────────────┐
│           CROSS COVERAGE                  │
│  (Interaction between coverage domains)   │
│  e.g., "AI GO asserted during SPI RX"    │
│         ┌──────────────────────┐          │
│         │ FUNCTIONAL COVERAGE   │         │
│         │ (Spec-driven bins)    │         │
│         │ e.g., "All 256 INT8   │         │
│         │  weight values seen"  │         │
│         │   ┌──────────────┐    │         │
│         │   │ CODE COVERAGE │    │         │
│         │   │ (Structural)  │    │         │
│         │   │ Line, Branch, │    │         │
│         │   │ FSM, Toggle   │    │         │
│         │   └──────────────┘    │         │
│         └──────────────────────┘          │
└──────────────────────────────────────────┘
```

### 1.2 Coverage Metrics Summary

| Metric | Target | Tool | Granularity |
|--------|--------|------|-------------|
| Line Coverage | 100% | Icarus/VCS/Verilator | Per-module, per-file |
| Branch Coverage | 100% | Icarus/VCS/Verilator | Per-condition |
| FSM Coverage | 100% states, 100% transitions | Icarus/VCS | Per-state-machine |
| Toggle Coverage | ≥ 99% | Icarus/VCS | Per-bit |
| Functional Coverage | 100% of bins | cocotb coverage lib | Per-covergroup |
| Cross Coverage | 100% of cross bins | cocotb coverage lib | Per-cross |
| Assertion Coverage | 100% triggered | cocotb assertions | Per-assertion |

---

## 2. Code Coverage Targets

### 2.1 Line Coverage Exclusion Policy

Lines that MAY be excluded (with documented waiver):
- **Defensive unreachable:** `default: $fatal(...)` in fully-defined case statements
- **Synthesis-only:** `// synthesis translate_off` sections
- **Simulation-only:** `$display`, `$monitor` (non-synthesizable)
- **DFT-only paths:** Scan chain insertion (test_mode_i = 1)

Lines that MUST be covered:
- All functional RTL (combinational + sequential logic)
- All assignment branches (if/else, case, ternary)
- All generate loop iterations
- All parameter/configurations

### 2.2 Branch Coverage

Every `if/else`, `case`, ternary `?:`, and logical operator branch must be taken both ways:
- `if (condition)`: condition=0, condition=1
- `if (a && b)`: all 4 combinations (00, 01, 10, 11)
- `if (a || b)`: all 4 combinations
- `case (sel)`: every case arm reached
- `a ? b : c`: both a=0 and a=1

### 2.3 FSM Coverage

Every state machine must demonstrate:
- **State coverage:** Every state visited at least once
- **Transition coverage:** Every defined arc traversed at least once
- **Illegal transitions:** Confirmed unreachable (or covered if reachable)

### 2.4 Toggle Coverage

Every bit of every register and wire must toggle 0→1 and 1→0.
Waivers allowed for:
- Tie-hi/tie-lo constants
- DFT-only signals (test_mode_i = 0 only)
- Reset values (may not toggle in normal operation)

---

## 3. Functional Coverage by Module

### 3.1 AI Accelerator (`ai_accel_4x4`)

#### 3.1.1 Coverage Groups

```
Covergroup: ai_ctrl_cg
  - ctrl.GO:          {0, 1}
  - ctrl.BUSY:        {0, 1}
  - ctrl.DONE:        {0, 1}
  - ctrl.ERROR:       {0, 1}
  - ctrl.RELU_EN:     {0, 1}
  - ctrl.QUANT_EN:    {0, 1}
  - ctrl.CLK_EN:      {0, 1}
  - ctrl.RST:         {0, 1}
  Target bins: 8

Covergroup: ai_weight_cg
  - weight_0:         bins = {-128, -64, -1, 0, 1, 63, 127}  // corner + range
  - weight_1:         bins = {-128, -64, -1, 0, 1, 63, 127}
  - weight_2:         bins = {-128, -64, -1, 0, 1, 63, 127}
  - weight_3:         bins = {-128, -64, -1, 0, 1, 63, 127}
  Target bins: 28

Covergroup: ai_input_cg
  - input_a[0]:       bins = {-128, -1, 0, 1, 127}
  - input_a[1]:       bins = {-128, -1, 0, 1, 127}
  - input_a[2]:       bins = {-128, -1, 0, 1, 127}
  - input_a[3]:       bins = {-128, -1, 0, 1, 127}
  Target bins: 20

Covergroup: ai_output_range_cg
  - output[0]:        bins = {INT32_MIN, -1, 0, 1, INT32_MAX, overflow}
  - output[1]:        bins = {INT32_MIN, -1, 0, 1, INT32_MAX, overflow}
  - output[2]:        bins = {INT32_MIN, -1, 0, 1, INT32_MAX, overflow}
  - output[3]:        bins = {INT32_MIN, -1, 0, 1, INT32_MAX, overflow}
  Target bins: 24

Covergroup: ai_activation_cg
  - activation:       bins = {NONE, RELU, SIGMOID, TANH}
  Target bins: 4

Covergroup: ai_bias_cg
  - bias[0]:          bins = {INT16_MIN, -1, 0, 1, INT16_MAX}
  - bias[1]:          bins = {INT16_MIN, -1, 0, 1, INT16_MAX}
  - bias[2]:          bins = {INT16_MIN, -1, 0, 1, INT16_MAX}
  - bias[3]:          bins = {INT16_MIN, -1, 0, 1, INT16_MAX}
  Target bins: 20

Covergroup: ai_err_code_cg
  - error_code:       bins = {NO_ERROR, UNDERFLOW, OVERFLOW, INVALID_CFG, HW_FAULT}
  Target bins: 5

Covergroup: ai_intr_cg
  - done_irq:         bins = {triggered, masked}
  - error_irq:        bins = {triggered, masked}
  Target bins: 4

Covergroup: ai_scale_cg
  - scale_factor:     bins = {0, 0x0100 (1.0), 0xFFFF (max), other}
  Target bins: 4

Covergroup: ai_state_seq_cg
  - state_seq:        bins = {
      IDLE→GO→BUSY→DONE→IDLE,         // normal
      IDLE→GO→BUSY→ERROR,             // error
      IDLE→RST→IDLE,                  // reset
      GO during BUSY (ignored),       // concurrent GO
      Read during BUSY,               // concurrent access
      GO with incomplete weights      // error condition
    }
  Target bins: 6

Total AI functional bins: 123
```

### 3.2 SPI Controller (`spi_master`)

#### 3.2.1 Coverage Groups

```
Covergroup: spi_mode_cg
  - CPOL:             bins = {0, 1}
  - CPHA:             bins = {0, 1}
  - MSTEN:            bins = {0, 1}  // always 1 in this design
  - LSBFE:            bins = {0, 1}
  Target bins: 6

Covergroup: spi_clkdiv_cg
  - divider:          bins = {2, 4, 5, 10, 25, 50, 100, 200, 255, 256}
  Target bins: 10

Covergroup: spi_fifo_cg
  - tx_fifo_level:    bins = {0, 1, 4, 7, 8}  // empty, partial, almost-full, full
  - rx_fifo_level:    bins = {0, 1, 4, 7, 8}
  Target bins: 10

Covergroup: spi_data_cg
  - tx_data:          bins = {0x00, 0xFF, 0x55, 0xAA, other}
  - rx_data:          bins = {0x00, 0xFF, 0x55, 0xAA, other}
  Target bins: 10

Covergroup: spi_cs_cg
  - cs_active:        bins = {0 (none), 1 (CS0), 8 (CS3), other}
  Target bins: 4

Covergroup: spi_xfer_size_cg
  - bytes_per_xfer:   bins = {1, 2, 4, 8, 16, 32, 64, 128, 256}
  Target bins: 9

Covergroup: spi_status_cg
  - tx_busy:          bins = {0, 1}
  - tx_empty:         bins = {0, 1}
  - rx_not_empty:     bins = {0, 1}
  Target bins: 6

Covergroup: spi_intr_cg
  - intr_source:      bins = {RX, TX, ERROR, TX_COMPLETE, RX_FULL}
  - each source:      bins = {triggered, masked, cleared}
  Target bins: 15 (5 sources × 3 states)

Covergroup: spi_err_cg
  - error_type:       bins = {MODE_FAULT, RX_OVERFLOW, TX_UNDERFLOW}
  Target bins: 3

Covergroup: spi_full_frame_cg
  - frame_valid:      bins = {CRC_OK, CRC_FAIL}
  - distance_val:     bins = {0, 0xFFFF (max), mid}
  - rel_vel_val:      bins = {INT16_MIN, 0, INT16_MAX, mid}
  Target bins: 8

Total SPI functional bins: 81
```

### 3.3 Servo PWM (`servo_pwm`)

#### 3.3.1 Coverage Groups

```
Covergroup: servo_ctrl_cg
  - enable:           bins = {0, 1}
  - safe_mode:        bins = {0, 1}
  - us_mode:          bins = {0, 1}
  - fault_en:         bins = {0, 1}
  - fault_action:     bins = {0 (safe), 1 (disable)}
  Target bins: 10

Covergroup: servo_period_cg
  - period_ms:        bins = {5, 10, 20, 50}
  Target bins: 4

Covergroup: servo_duty_cg
  - pulse_us:         bins = {500, 750, 1000, 1250, 1500, 1750, 2000, 2250, 2500}
  Target bins: 9

Covergroup: servo_duty_transition_cg
  - prev_pulse:       bins = {500, 1500, 2500}
  - new_pulse:        bins = {500, 1500, 2500}
  - transition_type:  cross prev_pulse × new_pulse
  Target cross bins: 9

Covergroup: servo_fault_cg
  - fault_type:       bins = {STUCK_HIGH, STUCK_LOW, NO_FAULT}
  - fault_response:   bins = {SAFE, DISABLED, NONE}
  Target bins: 6

Covergroup: servo_status_cg
  - running:          bins = {0, 1}
  - at_safe:          bins = {0, 1}
  - fault_latched:    bins = {0, 1}
  Target bins: 6

Covergroup: servo_intr_cg
  - fault_intr:       bins = {triggered, masked}
  - period_done_intr: bins = {triggered, masked}
  Target bins: 4

Covergroup: servo_shutdown_cg
  - shutdown_src:     bins = {safety_monitor, software, external}
  - pwm_after_shdn:   bins = {disabled, safe_position}
  Target bins: 5

Total Servo PWM functional bins: 53
```

### 3.4 Speed Sensor (`speed_sensor`)

#### 3.4.1 Coverage Groups

```
Covergroup: speed_ctrl_cg
  - enable:           bins = {0, 1}
  - stuck_det_en:     bins = {0, 1}
  - stuck_action:     bins = {0 (irq_only), 1 (irq_fault)}
  Target bins: 5

Covergroup: speed_count_cg
  - count_range:      bins = {0, 1, 100, 1000, 10000, overflow}
  Target bins: 6

Covergroup: speed_timestamp_cg
  - ts_low_rollover:  bins = {no_rollover, rollover_once, rollover_multiple}
  - ts_high_inc:      bins = {0, 1, >1}
  Target bins: 6

Covergroup: speed_period_cg
  - period_range:     bins = {<1000 cycles, 1000-10000, 10000-100000, >100000}
  Target bins: 4

Covergroup: speed_pulse_rate_cg
  - rate_range:       bins = {0, 1-10 Hz, 10-100 Hz, 100-1000 Hz, >1000 Hz}
  Target bins: 5

Covergroup: speed_glitch_cg
  - pulse_width:      bins = {<100ns, 100ns-1us, >1us}
  - glitch_rejected:  bins = {rejected, accepted}
  Target bins: 5

Covergroup: speed_stuck_cg
  - stuck_event:      bins = {no_stuck, stuck_detected, stuck_cleared}
  Target bins: 3

Covergroup: speed_intr_cg
  - pulse_intr:       bins = {triggered, masked}
  - ovf_intr:         bins = {triggered, masked}
  - stuck_intr:       bins = {triggered, masked}
  Target bins: 6

Covergroup: speed_compute_cg
  - speed_kmh:        bins = {0, 0-30, 30-60, 60-90, 90-120, >120}
  Target bins: 6

Total Speed Sensor functional bins: 46
```

### 3.5 Buzzer PWM (`buzzer_pwm`)

#### 3.5.1 Coverage Groups

```
Covergroup: buzzer_ctrl_cg
  - enable:           bins = {0, 1}
  - burst_en:         bins = {0, 1}
  - invert:           bins = {0, 1}
  Target bins: 6

Covergroup: buzzer_freq_cg
  - frequency_hz:     bins = {1000, 2000, 4000, 6000, 8000, 10000}
  Target bins: 6

Covergroup: buzzer_duty_cg
  - duty_pct:         bins = {0, 25, 50, 75, 100}
  Target bins: 5

Covergroup: buzzer_burst_cg
  - burst_on_cycles:  bins = {0, 100, 1000, 10000}
  - burst_off_cycles: bins = {0, 100, 1000, 10000}
  Target bins: 8

Covergroup: buzzer_burst_count_cg
  - burst_repeat:     bins = {1, 5, 10, infinite}
  Target bins: 4

Covergroup: buzzer_pattern_cg
  - pattern:          bins = {CONTINUOUS, INTERMITTENT_500MS, OFF}
  Target bins: 3

Covergroup: buzzer_intr_cg
  - burst_done:       bins = {triggered, masked}
  Target bins: 2

Total Buzzer PWM functional bins: 34
```

### 3.6 UART (`uart_16550`)

#### 3.6.1 Coverage Groups

```
Covergroup: uart_cfg_cg
  - baud_rate:        bins = {9600, 19200, 38400, 57600, 115200, 921600}
  - word_length:      bins = {5, 6, 7, 8}
  - stop_bits:        bins = {1, 1.5, 2}
  - parity:           bins = {NONE, EVEN, ODD, MARK, SPACE}
  Target bins: 18

Covergroup: uart_tx_cg
  - tx_data:          bins = {0x00, 0xFF, 0x55, 0xAA, 0x20 (space), 0x0A (LF)}
  - fifo_level:       bins = {0, 1, 8, 15, 16}
  Target bins: 11

Covergroup: uart_rx_cg
  - rx_data:          bins = {0x00, 0xFF, 0x55, 0xAA, 0x30 ('0'), 0x41 ('A')}
  - fifo_level:       bins = {0, 1, 8, 15, 16}
  Target bins: 11

Covergroup: uart_err_cg
  - error_type:       bins = {OVERRUN, PARITY_ERR, FRAMING_ERR, BREAK, NO_ERROR}
  Target bins: 5

Covergroup: uart_lsr_cg
  - DR:               bins = {0, 1}
  - THRE:             bins = {0, 1}
  - TEMT:             bins = {0, 1}
  Target bins: 6

Covergroup: uart_intr_cg
  - rx_intr:          bins = {triggered, masked, cleared}
  - tx_intr:          bins = {triggered, masked, cleared}
  - line_intr:        bins = {triggered, masked, cleared}
  Target bins: 9

Covergroup: uart_loopback_cg
  - loopback_active:  bins = {0, 1}
  Target bins: 2

Total UART functional bins: 62
```

### 3.7 GPIO (`gpio_32bit`)

#### 3.7.1 Coverage Groups

```
Covergroup: gpio_dir_cg
  - dir_per_pin[31:0]: bins per pin = {input, output}
  - safety_pins[2:0]:  bins = {locked_input, locked_output, unlocked}
  Target bins: 67

Covergroup: gpio_out_cg
  - output_level_per_pin: per-pin = {0, 1}
  Target bins: 64

Covergroup: gpio_in_cg
  - input_level_per_pin: per-pin = {0, 1}
  Target bins: 64

Covergroup: gpio_atomic_cg
  - operation:           bins = {SET, CLR, TOG, DATA_RMW}
  Target bins: 4

Covergroup: gpio_intr_cg
  - pin[7:0]:            per-pin coverage
  - intr_type:           bins = {LEVEL, EDGE}
  - intr_polarity:       bins = {LOW_FALL, HIGH_RISE}
  - intr_triggered:      bins = {triggered, acked}
  Target bins: 40

Covergroup: gpio_pull_cg
  - pull_en:             bins = {per_pin}
  - pull_sel:            bins = {PULLDOWN, PULLUP}
  Target bins: 4

Covergroup: gpio_drive_cg
  - drive_strength:      bins = {2mA, 4mA, 8mA, 12mA}
  Target bins: 4

Covergroup: gpio_safety_cg
  - lock_status:         bins = {unlocked, partially_locked, fully_locked}
  - unlock_attempted:    bins = {attempted, not_attempted}
  Target bins: 5

Covergroup: gpio_shutdown_cg
  - force_shdn:          bins = {active, inactive}
  - alert_o:             bins = {active, inactive}
  Target bins: 4

Total GPIO functional bins: 256
```

### 3.8 TCM (`tcm_8kb`)

#### 3.8.1 Coverage Groups

```
Covergroup: tcm_addr_cg
  - addr_range:       bins = {0, 1, 512, 1023, 1024, 2047, 2048+}
  Target bins: 7

Covergroup: tcm_we_cg
  - byte_enable:      bins = {0x0 (none), 0x1, 0x2, 0x4, 0x8, 0x3, 0xC, 0xF (all)}
  Target bins: 8

Covergroup: tcm_data_cg
  - wdata_pattern:    bins = {ALL_ZERO, ALL_ONE, CHECKER (0xAA..55), INVERSE, RANDOM}
  Target bins: 5

Covergroup: tcm_back2back_cg
  - access_type:      bins = {READ_READ, READ_WRITE, WRITE_READ, WRITE_WRITE}
  Target bins: 4

Covergroup: tcm_parity_cg
  - parity_err:       bins = {no_error, single_bit, double_bit, multi_bit}
  - addr_affected:    bins = {data, parity_bit}
  Target bins: 6

Covergroup: tcm_latency_cg
  - rd_latency:       bins = {1, >1}
  - wr_latency:       bins = {1, >1}
  Target bins: 4

Total TCM functional bins: 34 (×2 for ITCM + DTCM = 68)
```

### 3.9 AXI4-Lite Interconnect (`axi4lite_xbar_1m_9s`)

#### 3.9.1 Coverage Groups

```
Covergroup: axi_addr_decode_cg
  - slave_select:     bins = {SLAVE_0..SLAVE_8, UNMAPPED}
  Target bins: 10

Covergroup: axi_rd_handshake_cg
  - arvalid_before_arready:  bins = {0, 1}
  - rvalid_before_rready:    bins = {0, 1}
  - backpressure:            bins = {none, ar, r, both}
  Target bins: 6

Covergroup: axi_wr_handshake_cg
  - awvalid_before_awready:  bins = {0, 1}
  - wvalid_before_wready:    bins = {0, 1}
  - bvalid_before_bready:    bins = {0, 1}
  - backpressure:            bins = {none, aw, w, b, combination}
  Target bins: 8

Covergroup: axi_wstrb_cg
  - wstrb_pattern:    bins = {0x1, 0x2, 0x4, 0x8, 0x3, 0xC, 0xF, other}
  Target bins: 8

Covergroup: axi_response_cg
  - rresp:            bins = {OKAY, SLVERR, DECERR}
  - bresp:            bins = {OKAY, SLVERR, DECERR}
  Target bins: 6

Covergroup: axi_concurrent_cg
  - active_reads:     bins = {0, 1, 2}  // AXI4-Lite: 1 outstanding max, but pipeline
  - active_writes:    bins = {0, 1, 2}
  Target bins: 6

Covergroup: axi_data_integrity_cg
  - data_pattern:     bins = {0x00000000, 0xFFFFFFFF, 0xAAAAAAAA, 0x55555555, RANDOM}
  Target bins: 5

Covergroup: axi_timing_cg
  - comb_delay:       bins = {0_cycles, 1_cycle, 2_cycles}
  Target bins: 3

Total AXI functional bins: 52
```

### 3.10 RV32IM Core (`rv32im_core`)

#### 3.10.1 Coverage Groups

```
Covergroup: rv32i_isa_cg
  - instruction:      bins per RV32I opcode (38 base instructions)
  Target bins: 38

Covergroup: rv32m_isa_cg
  - instruction:      bins per RV32M opcode (8 multiply/divide)
  Target bins: 8

Covergroup: rv32_hazard_cg
  - hazard_type:      bins = {
      RAW_forwarded,           // data hazard resolved by forwarding
      RAW_stalled,             // load-use hazard requires stall
      WAW,                     // write-after-write
      CONTROL_TAKEN,           // branch taken (flush IF)
      CONTROL_NOT_TAKEN,       // branch not taken
      STRUCTURAL_MUL,          // multi-cycle MUL stall
      STRUCTURAL_DIV           // multi-cycle DIV stall
    }
  Target bins: 7

Covergroup: rv32_branch_cg
  - branch_type:      bins = {BEQ, BNE, BLT, BGE, BLTU, BGEU, JAL, JALR}
  - outcome:          bins = {taken, not_taken}
  Target bins: 16

Covergroup: rv32_alu_cg
  - alu_op:           bins = {ADD, SUB, SLT, SLTU, XOR, OR, AND, SLL, SRL, SRA}
  - operand_sign:     bins = {both_pos, both_neg, mixed, zero}
  Target bins: 14

Covergroup: rv32_load_store_cg
  - mem_op:           bins = {LB, LH, LW, LBU, LHU, SB, SH, SW}
  - alignment:        bins = {aligned, misaligned}
  Target bins: 12

Covergroup: rv32_csr_cg
  - csr_accessed:     bins = {mstatus, mepc, mcause, mtvec, mie, mip, mcycle, minstret, mhartid}
  Target bins: 9

Covergroup: rv32_trap_cg
  - trap_type:        bins = {ECALL, EBREAK, ILLEGAL_INST, MISALIGNED_LOAD, MISALIGNED_STORE}
  Target bins: 5

Covergroup: rv32_intr_cg
  - irq_source:       bins per IRQ[0..15] = {triggered, masked, pending, serviced}
  Target bins: 64 (16 sources × 4 states)

Covergroup: rv32_lockstep_cg
  - lockstep_valid:   bins = {0, 1}
  - lockstep_output:  bins = {STABLE, CHANGING}
  Target bins: 4

Covergroup: rv32_halt_cg
  - halt_asserted:    bins = {during_FETCH, during_DECODE, during_EXECUTE, during_STALL}
  Target bins: 4

Covergroup: rv32_pipeline_cg
  - IF_stage:         bins = {active, stalled, flushed}
  - ID_stage:         bins = {active, stalled, flushed}
  - EX_stage:         bins = {active, multi_cycle}
  Target bins: 8

Total RV32IM functional bins: 189
```

### 3.11 Window WDT (`window_wdt`)

#### 3.11.1 Coverage Groups

```
Covergroup: wdt_ctrl_cg
  - enable:           bins = {0, 1}
  - window_en:        bins = {0, 1}
  - prewarn_en:       bins = {0, 1}
  - reset_en:         bins = {0, 1}
  - write_key_correct: bins = {correct, incorrect, missing}
  Target bins: 9

Covergroup: wdt_timeout_cg
  - timeout_ticks:    bins = {1, 10, 100, 3277 (100ms), 32768 (1s), MAX (36h)}
  Target bins: 6

Covergroup: wdt_window_cg
  - window_start_pct: bins = {25%, 50%, 75%, 90%}
  Target bins: 4

Covergroup: wdt_kick_cg
  - kick_timing:      bins = {before_window, in_window, after_timeout}
  - kick_value:       bins = {correct (0xAC53_CAFE), incorrect}
  Target bins: 6

Covergroup: wdt_status_cg
  - running:          bins = {0, 1}
  - in_window:        bins = {0, 1}
  - prewarned:        bins = {0, 1}
  - timed_out:        bins = {0, 1}
  - early_kick:       bins = {0, 1}
  Target bins: 10

Covergroup: wdt_lock_cg
  - lock_state:       bins = {unlocked, ctrl_locked, timeout_locked, window_locked, all_locked}
  - lock_write_attempt: bins = {attempted_on_locked, not_attempted}
  Target bins: 6

Covergroup: wdt_sequence_cg
  - sequence:         bins = {
      enable→count→window_open→kick→count_reset,
      enable→count→timeout→fault,
      enable→count→early_kick→fault,
      enable→disable_attempt→rejected,
      prewarn→(kick|timeout)
    }
  Target bins: 5

Covergroup: wdt_intr_cg
  - prewarn_intr:     bins = {triggered, masked}
  Target bins: 2

Covergroup: wdt_fault_cg
  - fault_source:     bins = {TIMEOUT, EARLY_KICK}
  Target bins: 2

Covergroup: wdt_cdc_cg
  - sys_clk_read:     bins = {stable, changing}
  - sys_clk_write:    bins = {during_count, during_idle}
  Target bins: 4

Total WDT functional bins: 54
```

### 3.12 Safety Monitor / Fault Aggregator

#### 3.12.1 Coverage Groups

```
Covergroup: safety_fault_src_cg
  - fault_source[11:0]: per-source = {triggered, masked, latched, cleared}
  Target bins: 48

Covergroup: safety_lockstep_cg
  - match:            bins = {match, mismatch}
  - delay_cycles:     bins = {1, 2, 3, 4}
  - threshold:        bins = {0, 1, 2, 4}
  Target bins: 10

Covergroup: safety_severity_cg
  - severity_config:  bins = {0 (any), 1 (HIGH+), 2 (CRITICAL only)}
  - fault_severity:   bins = {LOW, MEDIUM, HIGH, CRITICAL}
  Target bins: 7

Covergroup: safety_response_cg
  - auto_halt:        bins = {enabled_halted, enabled_not_halted, disabled}
  - auto_shutdown:    bins = {enabled_shutdown, enabled_no_shutdown, disabled}
  Target bins: 6

Covergroup: safety_test_cg
  - force_fault:      bins = {active, inactive}
  - force_mismatch:   bins = {active, inactive}
  - test_mode:        bins = {active, inactive}
  Target bins: 6

Covergroup: safety_reset_cg
  - reset_target:     bins = {CPU, PERIPH, AI, NONE}
  - magic_key:        bins = {correct, incorrect, missing}
  Target bins: 7

Covergroup: safety_counter_cg
  - fault_count:      bins = {0, 1, 5, 255, saturated}
  Target bins: 5

Covergroup: safety_aggregated_cg
  - agg_fault_asserted: bins = {0, 1}
  - fault_clear_attempt: bins = {clear_while_active, clear_after_deassert}
  Target bins: 4

Total Safety Monitor functional bins: 93
```

### 3.13 Redundant Shutdown Controller

#### 3.13.1 Coverage Groups

```
Covergroup: rsc_input_cg
  - aggregated_fault: bins = {0, 1}
  - force_shutdown_sw: bins = {0, 1}
  - both_asserted:    bins = {neither, fault_only, sw_only, both}
  Target bins: 6

Covergroup: rsc_shutdown_seq_cg
  - alert_timing:     bins = {immediate, within_4_cycles, delayed}
  - shutdown_timing:  bins = {within_4_cycles, within_10_cycles, delayed}
  Target bins: 6

Covergroup: rsc_latch_cg
  - latched_state:    bins = {not_triggered, triggered_and_latched}
  - reset_attempt:    bins = {warm_reset_attempted, por_only_clears}
  Target bins: 4

Covergroup: rsc_output_cg
  - shutdown_n:       bins = {00 (both_active), 01, 10, 11 (inactive)}
  - alert_n:          bins = {0 (active), 1 (inactive)}
  - force_shdn_o:     bins = {0, 1}
  Target bins: 7

Covergroup: rsc_clock_independent_cg
  - sys_clk_present:  bins = {yes, no}
  - shutdown_still_works: bins = {yes, no}
  Target bins: 3

Total RSC functional bins: 26
```

### 3.14 Top-Level System (`adas_v2_top`)

#### 3.14.1 Coverage Groups

```
Covergroup: system_state_cg
  - system_state:     bins = {BOOT, OPERATIONAL, FAULT_DETECTED, SAFE_STATE, SHUTDOWN}
  Target bins: 5

Covergroup: system_scenario_cg
  - scenario:         bins = {
      APPROACH_AND_BRAKE, CROSSING_CLEAR,
      STATIONARY_OBSTACLE, SAFETY_TIMEOUT,
      SENSOR_FAULT, WDT_TIMEOUT,
      LOCKSTEP_MISMATCH
    }
  Target bins: 7

Covergroup: system_safety_entry_cg
  - entry_trigger:    bins = {
      lockstep_mismatch, wdt_timeout, wdt_early_kick,
      servo_fault, ai_fault, spi_fault,
      speed_stuck, itcm_parity, dtcm_parity,
      ecc_double_bit, ext_shutdown, sw_fault
    }
  Target bins: 12

Covergroup: system_timing_cg
  - e2e_latency_us:   bins = {<1000, 1000-2000, 2000-3000, 3000-4000, 4000-5000, >5000}
  Target bins: 6

Covergroup: system_concurrent_cg
  - active_peripherals: bins = {0, 1, 2, 3, 4, 5, 6, all}
  Target bins: 8

Covergroup: system_power_cg
  - clock_gated:      bins per peripheral = {gated, not_gated}
  - core_gated:       bins = {WFI_gated, running}
  Target bins: 12

Covergroup: system_reset_seq_cg
  - reset_type:       bins = {POR, SOFT_RESET, SAFETY_RESET, WDT_RESET}
  - reset_recovery:   bins = {normal, stuck}
  Target bins: 8

Covergroup: system_interrupt_cg
  - simultaneous_irqs: bins = {0, 1, 2, 3, 4, >4}
  Target bins: 6

Covergroup: system_cdc_cg
  - cdc_path:         bins = {WDT_REGS, RSC_INPUTS, FAULT_SIGNALS, PULSE_SYNC}
  - cdc_stable:       bins = {metastable_resolved, error}
  Target bins: 8

Total System functional bins: 72
```

---

## 4. Cross-Coverage Specifications

### 4.1 Cross-Coverage Groups

Cross-coverage captures interactions between coverage domains that are critical
for safety or functional correctness.

#### 4.1.1 AI Accelerator Cross Coverage

```
Cross: ai_activation × ai_output_sign
  - activation: {NONE, RELU, SIGMOID, TANH}
  - output_sign: {ALL_POS, ALL_NEG, MIXED, ZERO}
  Rationale: Verify all activations handle all sign patterns.
  Target bins: 16

Cross: ai_weight_sign × ai_input_sign × ai_output_sign
  - weight_sign: {POS, NEG, ZERO}
  - input_sign: {POS, NEG, ZERO}
  - output_sign: {POS, NEG, ZERO}
  Rationale: INT8 arithmetic sign handling at all layers.
  Target bins: 27

Cross: ai_ctrl_go × ai_ctrl_busy
  - GO asserted when BUSY: {go_during_busy, go_when_idle}
  - BUSY assertion timing: {immediate, delayed}
  Rationale: Verify GO is ignored during BUSY.
  Target bins: 4

Cross: ai_weight_loaded × ai_go
  - weights_complete: {all_loaded, partial, none}
  - go_attempt: {attempted, not_attempted}
  - result: {launched, error, ignored}
  Rationale: Verify launch only with complete weights.
  Target bins: 6
```

#### 4.1.2 SPI Cross Coverage

```
Cross: spi_clkdiv × spi_cs
  - divider: {2, 10, 100, 256}
  - cs_duration: {1_byte, 4_bytes, 8_bytes, 256_bytes}
  Rationale: Verify CS timing holds across all clock rates.
  Target bins: 16

Cross: spi_mode × spi_fifo_level
  - mode: {MODE_0, MODE_3}
  - fifo_full: {tx_full, rx_full, both_full, neither}
  Rationale: Verify FIFO behavior across SPI modes.
  Target bins: 8

Cross: spi_error × spi_state
  - error: {CRC_FAIL, MODE_FAULT, RX_OVF}
  - peripheral_state: {IDLE, ACTIVE, FAULT}
  Rationale: Verify error handling in all states.
  Target bins: 9
```

#### 4.1.3 Servo PWM Cross Coverage

```
Cross: servo_duty × servo_safe_mode
  - duty: {MIN, MID, MAX}
  - safe_mode: {active, inactive}
  - actual_output: {min, mid, max, safe}
  Rationale: Verify safe mode overrides duty cycle.
  Target bins: 9

Cross: servo_fault × servo_fault_action
  - fault_type: {STUCK_HIGH, STUCK_LOW}
  - fault_action: {SAFE, DISABLE}
  - pwm_result: {safe, disabled, unchanged}
  Rationale: Verify both fault actions work correctly.
  Target bins: 6
```

#### 4.1.4 Safety Cross Coverage

```
Cross: fault_source × fault_severity × system_response
  - source: {all 12 sources}
  - severity: {LOW, MEDIUM, HIGH, CRITICAL}
  - response: {none, irq_only, halt, shutdown}
  Rationale: Verify correct response per source×severity.
  Target bins: 48

Cross: lockstep_mismatch × delay_config
  - mismatch: {match, mismatch}
  - delay: {1, 2, 3, 4}
  - detection: {within_1_cycle, within_2_cycles, within_3_cycles, missed}
  Rationale: Verify lockstep works at all delay settings.
  Target bins: 16

Cross: wdt_window × kick_timing × wdt_response
  - window_pct: {25%, 50%, 75%}
  - kick_timing: {before_window, in_window, after_timeout}
  - response: {ok, early_fault, timeout_fault}
  Rationale: Verify WDT window behavior comprehensively.
  Target bins: 18
```

#### 4.1.5 System Cross Coverage

```
Cross: scenario × ego_speed × ttc × brake_decision
  - scenario: {APPROACH, CROSSING, OBSTACLE}
  - ego_speed: {0, LOW, MED, HIGH}
  - ttc: {<THRESH, =THRESH, >THRESH, INF}
  - brake: {yes, no}
  Rationale: Verify ADAS algorithm across the full input space.
  Target bins: 72

Cross: cpu_instruction × peripheral_active
  - instruction_type: {LOAD, STORE, BRANCH, ALU, MULDIV, CSR}
  - peripheral: {SPI_TX, SPI_RX, AI_COMPUTE, PWM_CHANGE, NONE}
  Rationale: Verify concurrent CPU + peripheral operation.
  Target bins: 30

Cross: clock_domain × data_transfer
  - crossing: {SYSCLK→WDTCLK, WDTCLK→SYSCLK}
  - data_stable: {stable, changing}
  - transfer_correct: {correct, incorrect}
  Rationale: Verify CDC correctness.
  Target bins: 8

Cross: fault_active × peripheral_state
  - fault: {LOCKSTEP, WDT, SERVO, PARITY}
  - spi_state: {IDLE, TX, RX}
  - ai_state: {IDLE, BUSY, DONE}
  - servo_state: {OFF, RUNNING, SAFE}
  Rationale: Verify fault response while peripherals active.
  Target bins: 36
```

---

## 5. Coverage Collection Infrastructure

### 5.1 Tool Configuration

```
# Icarus Verilog coverage
iverilog -g2012 -Wall -coverage all -o sim.vvp tb.v

# Verilator coverage (where applicable)
verilator --cc --coverage --coverage-line --coverage-toggle top.v

# VCS coverage (if available)
vcs -cm line+cond+fsm+tgl+branch -cm_dir cov_data/

# Coverage merge and report
urg -dir cov_data/* -report cov_report/
```

### 5.2 Cocotb Coverage Integration

```python
# cocotb coverage collection skeleton (per testbench)
from cocotb_coverage.coverage import *

# Define coverage groups (see Section 3 for per-module spec)
# Merge across test runs
# Export to URG-compatible format
```

### 5.3 Coverage Dashboard

```
┌─────────────────────────────────────────────┐
│          COVERAGE DASHBOARD                 │
│                                              │
│  Module          Line   Branch  FSM   Func  │
│  ─────           ────   ──────  ───   ────  │
│  ai_accel         ████   ████   ████  ████  │
│  spi_master       ▄▄▄▄   ▄▄▄▄   ▄▄▄▄  ▄▄▄▄  │
│  ...                                        │
│                                              │
│  Overall:   ████ 98%   ████ 97%  ...        │
│                                              │
│  Gaps:                                       │
│    - spi_master: branch 0x2C4 (MODE_FAULT)  │
│    - safety_monitor: FSM transition B→C     │
└─────────────────────────────────────────────┘
```

---

## 6. Coverage Closure Plan

### 6.1 Closure Methodology

```
FOR each module:
  WHILE coverage < 100%:
    1. Identify uncovered bins
    2. Classify: "needs more random" vs "needs directed test"
    3. For random: increase cycles or adjust constraints
    4. For directed: write new test case targeting specific bin
    5. Re-run, re-collect, re-assess
```

### 6.2 Unreachable Coverage Waiver Process

1. Identify unreachable code/functional state
2. Document in `coverage_waivers.md` with:
   - Module, file, line number
   - Coverage type (line/branch/FSM/functional)
   - Reason unreachable
   - SRS reference (if safety-related)
   - Reviewer sign-off
3. Architect (Kenji Tanaka) must approve all safety-critical waivers

### 6.3 Coverage Review Gates

| Gate | When | Criteria |
|------|------|----------|
| Unit Lint | After RTL delivery | N/A |
| Directed Tests Complete | After directed test phase | ≥ 60% functional coverage |
| Random Soak Gate | After 500K random cycles | ≥ 90% functional coverage |
| Coverage Sign-Off | Before P&R | 100% functional, 100% code |
| Regression Gate | Nightly | No coverage degradation |

---

## Revision History

| Version | Date | Author | Description |
|---------|------|--------|-------------|
| 1.0 | 2026-04-29 | Rahul Sharma | Initial comprehensive coverage model |

---

*"You can't fix what you can't measure. 100% coverage is not a goal — it's the floor."*  
*— Rahul Sharma, Verification Lead*
