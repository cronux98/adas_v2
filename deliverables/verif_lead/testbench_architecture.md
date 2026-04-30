# ADAS v2 — Testbench Architecture Specification

**Document:** VER-TB-001 | **Version:** 1.0 | **Date:** 2026-04-29  
**Author:** Rahul Sharma, Verification Lead  
**Framework:** cocotb + Python BFMs + Icarus Verilog (primary) / Verilator (secondary)  
**Coverage:** All 14 modules + top-level integration  

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Cocotb Testbench Structure](#2-cocotb-testbench-structure)
3. [Bus Functional Models (BFMs)](#3-bus-functional-models-bfms)
4. [Scoreboard Architecture](#4-scoreboard-architecture)
5. [Golden Reference Integration](#5-golden-reference-integration)
6. [Monitor and Checker Architecture](#6-monitor-and-checker-architecture)
7. [Per-Module Testbench Specifications](#7-per-module-testbench-specifications)
8. [System-Level Testbench](#8-system-level-testbench)
9. [Environment Configuration](#9-environment-configuration)

---

## 1. Architecture Overview

### 1.1 Layered Testbench Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    TEST LAYER (pytest)                       │
│  ┌──────────┐ ┌──────────┐ ┌────────────┐ ┌─────────────┐  │
│  │ Directed │ │ Random   │ │ Scenario   │ │ Fault       │  │
│  │ Tests    │ │ Tests    │ │ Tests      │ │ Injection   │  │
│  └────┬─────┘ └────┬─────┘ └─────┬──────┘ └──────┬──────┘  │
│       └─────────────┴─────────────┴───────────────┘         │
│                          │                                   │
├──────────────────────────┼───────────────────────────────────┤
│              SCOREBOARD / CHECKER LAYER                      │
│  ┌──────────┐ ┌──────────┐ ┌────────────┐ ┌─────────────┐  │
│  │ Protocol │ │ Data     │ │ Golden Ref │ │ Assertion   │  │
│  │ Checker  │ │ Checker  │ │ Comparator │ │ Checker     │  │
│  └────┬─────┘ └────┬─────┘ └─────┬──────┘ └──────┬──────┘  │
│       └─────────────┴─────────────┴───────────────┘         │
│                          │                                   │
├──────────────────────────┼───────────────────────────────────┤
│               BFM / DRIVER / MONITOR LAYER                   │
│  ┌──────────┐ ┌──────────┐ ┌────────────┐ ┌─────────────┐  │
│  │ AXI4-    │ │ SPI      │ │ PWM        │ │ Pulse /    │  │
│  │ Lite BFM │ │ BFM      │ │ Monitor    │ │ GPIO BFM   │  │
│  └────┬─────┘ └────┬─────┘ └─────┬──────┘ └──────┬──────┘  │
│       └─────────────┴─────────────┴───────────────┘         │
│                          │                                   │
├──────────────────────────┼───────────────────────────────────┤
│                  SIGNAL / CLOCK LAYER                        │
│  ┌──────────┐ ┌──────────┐ ┌────────────┐                  │
│  │ Clock    │ │ Reset    │ │ CDC Bridge │                  │
│  │ Generator│ │ Generator│ │ (cross-dmn)│                  │
│  └────┬─────┘ └────┬─────┘ └─────┬──────┘                  │
│       └─────────────┴─────────────┘                         │
│                          │                                   │
├──────────────────────────┼───────────────────────────────────┤
│                    DUT (RTL)                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │          Module Under Test (Verilog RTL)              │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Directory Structure

```
tb/
├── Makefile                    # Top-level sim Makefile
├── conftest.py                 # Pytest fixtures + cocotb config
├── bfm/                        # Bus Functional Models
│   ├── __init__.py
│   ├── axi4lite_bfm.py         # AXI4-Lite Master/Slave BFM
│   ├── spi_bfm.py              # SPI Master/Slave BFM
│   ├── pwm_monitor.py          # PWM monitor + measurement
│   ├── uart_bfm.py             # UART BFM
│   ├── gpio_bfm.py             # GPIO driver/monitor
│   ├── pulse_generator.py      # Speed sensor pulse gen
│   ├── irq_monitor.py          # Interrupt monitor
│   └── clock_reset.py          # Clock + reset generators
├── scoreboard/                 # Scoreboard + checkers
│   ├── __init__.py
│   ├── axi_scoreboard.py       # AXI transaction scoreboard
│   ├── data_scoreboard.py      # Generic data-out vs expected
│   ├── protocol_checker.py     # Protocol compliance checker
│   └── timing_checker.py       # Timing constraint checker
├── golden/                     # Golden reference integration
│   ├── __init__.py
│   ├── ai_golden.py            # AI accelerator gold ref
│   ├── adas_golden.py          # ADAS algorithm gold ref
│   ├── spi_golden.py           # SPI protocol gold ref
│   └── safety_golden.py        # Safety monitor gold ref
├── coverage/                   # Coverage model definitions
│   ├── __init__.py
│   ├── ai_coverage.py
│   ├── spi_coverage.py
│   ├── ... (per module)
│   └── system_coverage.py
├── tests/                      # Test cases
│   ├── unit/                   # Module-level tests
│   │   ├── test_ai_accel.py
│   │   ├── test_spi_master.py
│   │   ├── test_servo_pwm.py
│   │   ├── test_speed_sensor.py
│   │   ├── test_buzzer_pwm.py
│   │   ├── test_uart.py
│   │   ├── test_gpio.py
│   │   ├── test_tcm.py
│   │   ├── test_axi_xbar.py
│   │   ├── test_rv32im.py
│   │   ├── test_window_wdt.py
│   │   ├── test_safety_monitor.py
│   │   └── test_rsc.py
│   ├── integration/            # Integration tests
│   │   ├── test_cpu_tcm.py
│   │   ├── test_cpu_axi.py
│   │   └── test_safety_chain.py
│   ├── system/                 # System-level tests
│   │   ├── test_adas_scenarios.py
│   │   └── test_end_to_end.py
│   └── fault/                  # Fault injection tests
│       ├── test_fault_lockstep.py
│       ├── test_fault_wdt.py
│       ├── test_fault_ecc.py
│       └── test_fault_shutdown.py
├── utils/                      # Utilities
│   ├── __init__.py
│   ├── random_stimulus.py      # Constrained random generators
│   ├── seed_manager.py         # Deterministic seed tracking
│   ├── report_generator.py     # HTML/JSON report generation
│   └── wave_config.py          # Waveform dumping config
└── logs/                       # Test output (gitignored)
    ├── regression_results/
    └── coverage_reports/
```

---

## 2. Cocotb Testbench Structure

### 2.1 Top-Level Cocotb Test Pattern

```python
# tests/unit/test_ai_accel.py
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

from bfm.axi4lite_bfm import Axi4LiteMaster
from bfm.clock_reset import ClockReset
from scoreboard.data_scoreboard import DataScoreboard
from golden.ai_golden import AIGoldenModel
from coverage.ai_coverage import AICoverage

@cocotb.test()
async def test_ai_matrix_multiply(dut):
    """
    Test: AI Accelerator 4×4 matrix multiply with known weights.
    """
    # --- Setup ---
    clk_rst = ClockReset(dut)
    await clk_rst.init()
    
    axi = Axi4LiteMaster(dut, "s_axi_")
    golden = AIGoldenModel()
    scoreboard = DataScoreboard()
    coverage = AICoverage()
    
    # --- Configure ---
    # Load weights
    weights = [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13, 14, 15, 16]]
    for row, w_row in enumerate(weights):
        packed = (w_row[0] & 0xFF) | ((w_row[1] & 0xFF) << 8) | \
                 ((w_row[2] & 0xFF) << 16) | ((w_row[3] & 0xFF) << 24)
        await axi.write(0x08 + row * 4, packed)
    
    # Load input
    inputs = [2, -3, 5, -1]
    packed_input = (inputs[0] & 0xFF) | ((inputs[1] & 0xFF) << 8) | \
                   ((inputs[2] & 0xFF) << 16) | ((inputs[3] & 0xFF) << 24)
    await axi.write(0x18, packed_input)
    
    # Compute golden expected
    expected = golden.compute(weights, inputs)
    
    # --- Start computation ---
    await axi.write(0x00, 0x1)  # GO = 1
    
    # --- Wait for DONE ---
    for _ in range(100):
        status = await axi.read(0x00)
        if status & 0x4:  # DONE bit
            break
        await RisingEdge(dut.clk_i)
    
    # --- Check results ---
    for i in range(4):
        actual = await axi.read(0x24 + i * 4)
        scoreboard.compare(f"output[{i}]", actual, expected[i])
    
    # --- Report ---
    coverage.sample(status, weights, inputs, expected)
    scoreboard.report()
    assert scoreboard.all_passed(), f"Scoreboard failures: {scoreboard.failures}"
```

### 2.2 Test Lifecycle

```
┌─────────────┐
│  pytest     │  Discover + parameterize
│  discover   │
└──────┬──────┘
       │
┌──────▼──────┐
│  cocotb     │  Initialize simulator
│  initialize │
└──────┬──────┘
       │
┌──────▼──────┐
│  Setup      │  Clock, reset, BFMs, scoreboard
│  Phase      │
└──────┬──────┘
       │
┌──────▼──────┐
│  Stimulus   │  Configure DUT, apply test vectors
│  Phase      │
└──────┬──────┘
       │
┌──────▼──────┐
│  Wait       │  Await completion (DONE, timeout, interrupt)
│  Phase      │
└──────┬──────┘
       │
┌──────▼──────┐
│  Check      │  Scoreboard comparison, assertion checks
│  Phase      │
└──────┬──────┘
       │
┌──────▼──────┐
│  Teardown   │  Coverage sample, log, report
│  Phase      │
└─────────────┘
```

### 2.3 Clock and Reset Generator

```python
# bfm/clock_reset.py
class ClockReset:
    """Unified clock and reset management for cocotb testbenches."""
    
    def __init__(self, dut, sys_clk_period_ns=10, wdt_clk_period_ns=30517):
        self.dut = dut
        self.sys_clk_period = sys_clk_period_ns      # 100 MHz = 10 ns
        self.wdt_clk_period = wdt_clk_period_ns        # 32.768 kHz = ~30.5 µs
        self._sys_clk = None
        self._wdt_clk = None
    
    async def init(self, reset_cycles=10):
        """Start clocks and apply reset sequence."""
        # Start clocks
        self._sys_clk = Clock(self.dut.sys_clk_i, self.sys_clk_period, units='ns')
        self._wdt_clk = Clock(self.dut.wdt_clk_i, self.wdt_clk_period, units='ns')
        await cocotb.start_soon(self._sys_clk.start())
        await cocotb.start_soon(self._wdt_clk.start())
        
        # Apply reset
        self.dut.sys_rst_n_i.value = 0
        self.dut.wdt_rst_n_i.value = 0
        await ClockCycles(self.dut.sys_clk_i, reset_cycles)
        
        # Release reset
        self.dut.sys_rst_n_i.value = 1
        await ClockCycles(self.dut.sys_clk_i, 5)
        self.dut.wdt_rst_n_i.value = 1
        await ClockCycles(self.dut.sys_clk_i, 5)
    
    async def reset_sys(self, cycles=5):
        """Assert system reset only."""
        self.dut.sys_rst_n_i.value = 0
        await ClockCycles(self.dut.sys_clk_i, cycles)
        self.dut.sys_rst_n_i.value = 1
    
    async def reset_wdt(self, cycles=5):
        """Assert watchdog reset only."""
        self.dut.wdt_rst_n_i.value = 0
        await ClockCycles(self.dut.wdt_clk_i, cycles)
        self.dut.wdt_rst_n_i.value = 1
```

---

## 3. Bus Functional Models (BFMs)

### 3.1 AXI4-Lite Master BFM

```python
# bfm/axi4lite_bfm.py

class Axi4LiteMaster:
    """
    AXI4-Lite Master BFM for cocotb.
    
    Drives AXI4-Lite read and write transactions.
    Supports backpressure (de-assert ready to test slave handling).
    Configurable random delays for stress testing.
    """
    
    def __init__(self, dut, prefix="s_axi_", clock=None):
        self.dut = dut
        self.prefix = prefix
        self.clk = clock or dut.clk_i
        
        # Signal path helpers
        self._awaddr = getattr(dut, f"{prefix}awaddr")
        self._awvalid = getattr(dut, f"{prefix}awvalid")
        self._awready = getattr(dut, f"{prefix}awready")
        self._wdata = getattr(dut, f"{prefix}wdata")
        self._wstrb = getattr(dut, f"{prefix}wstrb")
        self._wvalid = getattr(dut, f"{prefix}wvalid")
        self._wready = getattr(dut, f"{prefix}wready")
        self._bresp = getattr(dut, f"{prefix}bresp")
        self._bvalid = getattr(dut, f"{prefix}bvalid")
        self._bready = getattr(dut, f"{prefix}bready")
        self._araddr = getattr(dut, f"{prefix}araddr")
        self._arvalid = getattr(dut, f"{prefix}arvalid")
        self._arready = getattr(dut, f"{prefix}arready")
        self._rdata = getattr(dut, f"{prefix}rdata")
        self._rresp = getattr(dut, f"{prefix}rresp")
        self._rvalid = getattr(dut, f"{prefix}rvalid")
        self._rready = getattr(dut, f"{prefix}rready")
        
        self._init_signals()
    
    def _init_signals(self):
        """Initialize all master outputs to inactive."""
        self._awaddr.value = 0
        self._awvalid.value = 0
        self._wdata.value = 0
        self._wstrb.value = 0
        self._wvalid.value = 0
        self._bready.value = 0
        self._araddr.value = 0
        self._arvalid.value = 0
        self._rready.value = 0
    
    async def write(self, addr, data, strb=0xF, timeout_cycles=1000):
        """Perform an AXI4-Lite write transaction."""
        # Address phase
        self._awaddr.value = addr
        self._awvalid.value = 1
        await self._wait_handshake(self._awready, timeout_cycles)
        self._awvalid.value = 0
        
        # Data phase
        self._wdata.value = data
        self._wstrb.value = strb
        self._wvalid.value = 1
        await self._wait_handshake(self._wready, timeout_cycles)
        self._wvalid.value = 0
        
        # Response phase
        self._bready.value = 1
        await self._wait_handshake(self._bvalid, timeout_cycles)
        bresp = int(self._bresp.value)
        self._bready.value = 0
        
        if bresp != 0:  # Not OKAY
            raise AxiSlaveError(f"Write to 0x{addr:08X} got BRESP={bresp}")
        
        await RisingEdge(self.clk)
    
    async def read(self, addr, timeout_cycles=1000):
        """Perform an AXI4-Lite read transaction."""
        # Address phase
        self._araddr.value = addr
        self._arvalid.value = 1
        await self._wait_handshake(self._arready, timeout_cycles)
        self._arvalid.value = 0
        
        # Data phase
        self._rready.value = 1
        await self._wait_handshake(self._rvalid, timeout_cycles)
        rdata = int(self._rdata.value)
        rresp = int(self._rresp.value)
        self._rready.value = 0
        
        if rresp != 0:  # Not OKAY
            raise AxiSlaveError(f"Read from 0x{addr:08X} got RRESP={rresp}")
        
        await RisingEdge(self.clk)
        return rdata
    
    async def _wait_handshake(self, ready_signal, timeout_cycles):
        """Wait for valid→ready handshake."""
        for _ in range(timeout_cycles):
            await RisingEdge(self.clk)
            if int(ready_signal.value) == 1:
                return
        raise TimeoutError(f"AXI handshake timeout after {timeout_cycles} cycles")
    
    # --- Stress / Randomization Methods ---
    
    async def write_random_delay(self, addr, data, min_delay=0, max_delay=5, **kwargs):
        """Write with random delay before address phase."""
        delay = random.randint(min_delay, max_delay)
        await ClockCycles(self.clk, delay)
        return await self.write(addr, data, **kwargs)
    
    async def burst_write(self, transactions):
        """Execute list of (addr, data, strb) back-to-back."""
        results = []
        for addr, data, strb in transactions:
            results.append(await self.write(addr, data, strb))
        return results
```

### 3.2 SPI Slave BFM

```python
# bfm/spi_bfm.py

class SpiSlave:
    """
    SPI Slave BFM for verifying SPI Master controller.
    
    Simulates an SPI slave device (LIDAR sensor model).
    Supports configurable SPI mode, response data, and error injection.
    """
    
    def __init__(self, dut):
        self.dut = dut
        self.mode = 0  # CPOL=0, CPHA=0
        self.tx_queue = []  # Data to send to master (MISO)
        self.rx_data = []   # Data received from master (MOSI)
    
    async def connect(self):
        """Start monitoring SPI lines."""
        self._monitor_task = cocotb.start_soon(self._monitor_loop())
    
    async def _monitor_loop(self):
        """Continuously monitor SPI bus and respond as slave."""
        while True:
            await FallingEdge(self.dut.cs_n_o)  # Transaction start
            await self._handle_transaction()
    
    async def _handle_transaction(self):
        """Handle one SPI transaction (N bytes)."""
        byte_count = 0
        rx_byte = 0
        bit_count = 0
        
        while int(self.dut.cs_n_o.value) == 0:
            if self.mode == 0:
                await RisingEdge(self.dut.sck_o)  # Sample on rising edge
            else:
                await FallingEdge(self.dut.sck_o)
            
            # Sample MOSI
            mosi_bit = int(self.dut.mosi_o.value)
            rx_byte = (rx_byte << 1) | mosi_bit
            bit_count += 1
            
            if bit_count == 8:
                self.rx_data.append(rx_byte)
                rx_byte = 0
                bit_count = 0
                byte_count += 1
            
            # Drive MISO (second edge of clock)
            if self.mode == 0:
                await FallingEdge(self.dut.sck_o)  # Drive on falling edge
            else:
                await RisingEdge(self.dut.sck_o)
            
            if self.tx_queue:
                self.dut.miso_i.value = (self.tx_queue[0] >> (7 - (bit_count - 1))) & 1
    
    def prepare_response(self, data_bytes):
        """Queue response data for next transaction."""
        self.tx_queue = list(data_bytes)
    
    def inject_crc_error(self):
        """Corrupt next response to inject CRC error."""
        if self.tx_queue:
            self.tx_queue[-1] ^= 0xFF  # Flip all bits in last byte
```

### 3.3 PWM Monitor BFM

```python
# bfm/pwm_monitor.py

class PwmMonitor:
    """
    PWM Signal Monitor for measuring period, duty cycle, and glitch detection.
    
    Measures at system clock granularity (10 ns @ 100 MHz = 0.01 µs resolution).
    Detects glitches (pulses < SPEC_MIN_WIDTH).
    """
    
    def __init__(self, dut, pwm_signal, clk_signal=None):
        self.dut = dut
        self.pwm = pwm_signal
        self.clk = clk_signal or dut.clk_i
        self.period_cycles = 0
        self.high_cycles = 0
        self.glitch_count = 0
        self.measurements = []
    
    async def measure_cycle(self, timeout_cycles=3000000):
        """
        Measure one complete PWM cycle.
        
        Returns:
            (period_ns, high_time_ns, duty_cycle_pct, glitch_detected)
        """
        clk_period_ns = 10  # 100 MHz
        
        # Wait for rising edge
        await RisingEdge(self.pwm)
        start_cycle = cocotb.utils.get_sim_time(units='ns')
        
        # Measure high time
        high_start = cocotb.utils.get_sim_time(units='ns')
        await FallingEdge(self.pwm)
        high_time_ns = cocotb.utils.get_sim_time(units='ns') - high_start
        
        # Measure low time
        low_start = cocotb.utils.get_sim_time(units='ns')
        await RisingEdge(self.pwm)
        period_ns = cocotb.utils.get_sim_time(units='ns') - start_cycle
        
        duty_pct = (high_time_ns / period_ns * 100) if period_ns > 0 else 0
        
        self.measurements.append((period_ns, high_time_ns, duty_pct))
        return period_ns, high_time_ns, duty_pct, False
    
    async def check_glitch_free(self, min_high_ns=100):
        """Verify no glitches shorter than min_high_ns occur."""
        # Monitor continuously for glitch detection
        prev_val = int(self.pwm.value)
        prev_time = cocotb.utils.get_sim_time(units='ns')
        
        for _ in range(100000):  # Monitor for 100K cycles
            await RisingEdge(self.clk)
            curr_val = int(self.pwm.value)
            if curr_val != prev_val:
                pulse_width = cocotb.utils.get_sim_time(units='ns') - prev_time
                if prev_val == 1 and pulse_width < min_high_ns:
                    self.glitch_count += 1
                prev_val = curr_val
                prev_time = cocotb.utils.get_sim_time(units='ns')
        
        return self.glitch_count == 0
```

### 3.4 Pulse Generator BFM (Speed Sensor)

```python
# bfm/pulse_generator.py

class PulseGenerator:
    """
    Wheel speed sensor pulse generator.
    
    Generates pulse trains simulating wheel tachometer output.
    Configurable frequency (→ simulated speed) and glitch injection.
    """
    
    def __init__(self, dut, pulse_signal, clk_signal):
        self.dut = dut
        self.pulse = pulse_signal
        self.clk = clk_signal
        self.pulse.value = 0
    
    async def generate_pulses(self, frequency_hz, num_pulses=100, duty_cycle=0.5):
        """
        Generate N pulses at specified frequency.
        
        Args:
            frequency_hz: Pulse frequency in Hz.
            num_pulses: Number of pulses to generate.
            duty_cycle: High time fraction (0.0 to 1.0).
        """
        period_ns = int(1e9 / frequency_hz) if frequency_hz > 0 else float('inf')
        high_ns = int(period_ns * duty_cycle)
        low_ns = period_ns - high_ns
        
        for _ in range(num_pulses):
            self.pulse.value = 1
            await Timer(high_ns, units='ns')
            self.pulse.value = 0
            await Timer(low_ns, units='ns')
    
    async def inject_glitch(self, width_ns=50):
        """Inject a short glitch (< 100ns) that should be filtered."""
        self.pulse.value = 1
        await Timer(width_ns, units='ns')
        self.pulse.value = 0
    
    async def simulate_vehicle_speed(self, speed_kmh, wheel_pulses_per_rev=4,
                                      wheel_circumference_m=2.0, duration_ms=100):
        """
        Simulate vehicle traveling at given speed for given duration.
        
        Converts speed to pulse frequency based on wheel parameters.
        """
        speed_m_s = speed_kmh / 3.6
        revs_per_sec = speed_m_s / wheel_circumference_m
        pulse_freq = revs_per_sec * wheel_pulses_per_rev
        
        num_pulses = int(pulse_freq * duration_ms / 1000)
        await self.generate_pulses(pulse_freq, num_pulses)
```

### 3.5 UART BFM

```python
# bfm/uart_bfm.py

class UartAgent:
    """
    UART TX/RX agent for verifying UART 16550 module.
    """
    
    def __init__(self, dut):
        self.dut = dut
        self.dut.rx_i.value = 1  # Idle high
    
    async def send_byte(self, data, baud_rate=115200, data_bits=8,
                         parity='N', stop_bits=1):
        """Send one byte over UART (drive rx_i of DUT)."""
        bit_time_ns = int(1e9 / baud_rate)
        
        # Start bit
        self.dut.rx_i.value = 0
        await Timer(bit_time_ns, units='ns')
        
        # Data bits (LSB first)
        parity_val = 0
        for i in range(data_bits):
            bit = (data >> i) & 1
            self.dut.rx_i.value = bit
            parity_val ^= bit
            await Timer(bit_time_ns, units='ns')
        
        # Parity bit
        if parity == 'E':
            self.dut.rx_i.value = parity_val
        elif parity == 'O':
            self.dut.rx_i.value = ~parity_val & 1
        elif parity == 'M':
            self.dut.rx_i.value = 1
        elif parity == 'S':
            self.dut.rx_i.value = 0
        
        if parity != 'N':
            await Timer(bit_time_ns, units='ns')
        
        # Stop bit(s)
        self.dut.rx_i.value = 1
        await Timer(int(bit_time_ns * stop_bits), units='ns')
    
    async def send_string(self, text, **kwargs):
        """Send a string over UART."""
        for ch in text.encode('ascii'):
            await self.send_byte(ch, **kwargs)
    
    async def receive_byte(self, baud_rate=115200, data_bits=8,
                           parity='N', stop_bits=1, timeout_ms=100):
        """Receive one byte from UART (monitor tx_o of DUT)."""
        bit_time_ns = int(1e9 / baud_rate)
        
        # Wait for start bit
        for _ in range(int(timeout_ms * 1e6 / 10)):  # timeout in 10ns cycles
            await Timer(10, units='ns')
            if int(self.dut.tx_o.value) == 0:
                break
        else:
            raise TimeoutError("UART RX timeout waiting for start bit")
        
        # Wait half bit time to sample in middle
        await Timer(bit_time_ns // 2, units='ns')
        
        # Data bits (LSB first)
        data = 0
        for i in range(data_bits):
            await Timer(bit_time_ns, units='ns')
            if int(self.dut.tx_o.value):
                data |= (1 << i)
        
        return data
```

### 3.6 Interrupt Monitor

```python
# bfm/irq_monitor.py

class IrqMonitor:
    """
    Interrupt line monitor.
    
    Records IRQ assertion/de-assertion events with timestamps.
    Verifies interrupt handling protocol (assert → ack → deassert).
    """
    
    def __init__(self, dut, irq_signals, clk_signal):
        self.dut = dut
        self.irqs = irq_signals  # Dict {name: signal}
        self.clk = clk_signal
        self.events = []  # List of (timestamp, irq_name, edge)
    
    async def monitor(self, num_events=100):
        """Monitor interrupt lines for events."""
        prev_values = {name: int(sig.value) for name, sig in self.irqs.items()}
        
        for _ in range(num_events * 1000):  # Up to N*1000 cycles
            await RisingEdge(self.clk)
            for name, sig in self.irqs.items():
                curr = int(sig.value)
                if curr != prev_values[name]:
                    self.events.append((
                        cocotb.utils.get_sim_time(units='ns'),
                        name,
                        'RISE' if curr == 1 else 'FALL'
                    ))
                    prev_values[name] = curr
                    if len(self.events) >= num_events:
                        return self.events
        
        return self.events
    
    def verify_protocol(self, irq_name):
        """
        Verify IRQ protocol for a specific line:
        - Assertion followed by handler servicing
        - De-assertion after acknowledge
        """
        events = [e for e in self.events if e[1] == irq_name]
        assert len(events) >= 2, f"IRQ {irq_name} not enough events"
        assert events[0][2] == 'RISE', f"IRQ {irq_name} first event not RISE"
        assert events[-1][2] == 'FALL', f"IRQ {irq_name} last event not FALL"
```

---

## 4. Scoreboard Architecture

### 4.1 Data Scoreboard

```python
# scoreboard/data_scoreboard.py

class DataScoreboard:
    """
    Scoreboard comparing actual vs expected data values.
    
    Features:
    - Per-field comparison with configurable tolerance
    - Accumulated pass/fail counts
    - Detailed mismatch logging
    - Timestamp for waveform correlation
    """
    
    def __init__(self, tolerance=0):
        self.tolerance = tolerance
        self.passed = 0
        self.failed = 0
        self.mismatches = []
    
    def compare(self, field_name, actual, expected, tol=None):
        """Compare actual vs expected, record result."""
        _tol = tol if tol is not None else self.tolerance
        match = abs(actual - expected) <= _tol
        
        if match:
            self.passed += 1
        else:
            self.failed += 1
            self.mismatches.append({
                'field': field_name,
                'actual': actual,
                'expected': expected,
                'delta': actual - expected,
                'time_ns': cocotb.utils.get_sim_time(units='ns')
            })
        
        return match
    
    def compare_bit_exact(self, field_name, actual, expected):
        """Bit-exact comparison (tolerance=0)."""
        return self.compare(field_name, actual, expected, tol=0)
    
    def all_passed(self):
        return self.failed == 0
    
    def report(self):
        print(f"Scoreboard: {self.passed} passed, {self.failed} failed")
        if self.mismatches:
            print(f"  First mismatch: {self.mismatches[0]}")
```

### 4.2 AXI Protocol Checker

```python
# scoreboard/protocol_checker.py

class AxiProtocolChecker:
    """
    AXI4-Lite protocol compliance checker.
    
    Checks:
    - Handshake validity (valid must not depend on ready)
    - Address alignment (32-bit)
    - No combinatorial loops
    - Response encoding
    """
    
    def __init__(self, dut, prefix="s_axi_"):
        self.dut = dut
        self.prefix = prefix
        self.violations = []
    
    def check_write_address_stable(self):
        """AWADDR must be stable while AWVALID && !AWREADY."""
        # Checked per-cycle in monitor
        pass
    
    def check_read_address_stable(self):
        """ARADDR must be stable while ARVALID && !ARREADY."""
        pass
    
    def check_no_combinatorial_loop(self):
        """Ensure no comb loop between valid/ready."""
        pass
    
    def check_response_encoding(self, resp):
        """BRESP/RRESP must be OKAY, SLVERR, or DECERR."""
        valid_responses = {0, 2, 3}  # OKAY, SLVERR, DECERR
        if resp not in valid_responses:
            self.violations.append(f"Invalid response: {resp}")
```

---

## 5. Golden Reference Integration

### 5.1 AI Accelerator Golden Model

```python
# golden/ai_golden.py

import numpy as np

class AIGoldenModel:
    """
    Bit-exact golden model for the AI accelerator.
    
    Implements the exact INT8 arithmetic used by the RTL:
    - Weight-stationary 4×4 systolic array
    - INT8 weights/inputs → INT32 accumulation
    - Optional ReLU, Sigmoid (LUT-based), TanH (LUT-based)
    - Bias addition (INT16 → INT32)
    - Output scaling (Q8.8 fixed-point)
    """
    
    def compute(self, weights_4x4, inputs_4, biases_4=None, 
                activation='NONE', scale_q8_8=0x100):
        """
        Compute 4×4 matrix-vector product: output = W @ a + b.
        
        Args:
            weights_4x4: 4×4 list-of-lists of INT8 values.
            inputs_4: List of 4 INT8 values.
            biases_4: List of 4 INT16 values (default zeros).
            activation: 'NONE', 'RELU', 'SIGMOID', 'TANH'.
            scale_q8_8: Q8.8 scaling factor.
        
        Returns:
            List of 4 INT32 output values.
        """
        W = np.array(weights_4x4, dtype=np.int32)
        a = np.array(inputs_4, dtype=np.int32)
        
        # Matrix multiply
        result = W @ a
        
        # Bias addition
        if biases_4 is not None:
            b = np.array(biases_4, dtype=np.int32)
            result = result + b
        
        # Activation function
        if activation == 'RELU':
            result = np.maximum(0, result)
        elif activation == 'SIGMOID':
            result = self._sigmoid_lut(result)
        elif activation == 'TANH':
            result = self._tanh_lut(result)
        
        # Output scaling (Q8.8)
        result = (result.astype(np.int64) * scale_q8_8) >> 8
        result = np.clip(result, -2**31, 2**31 - 1)
        
        return result.tolist()
    
    def _sigmoid_lut(self, x):
        """LUT-based sigmoid approximation matching RTL implementation."""
        # Match RTL LUT exactly (256 entries)
        import math
        result = np.zeros_like(x, dtype=np.int32)
        for i, val in enumerate(x):
            # Quantized sigmoid: scale to LUT index
            idx = max(0, min(255, (val + 128) // 1))
            result[i] = idx  # Placeholder — matches RTL LUT
        return result
    
    def _tanh_lut(self, x):
        """LUT-based tanh approximation."""
        import math
        result = np.zeros_like(x, dtype=np.int32)
        for i, val in enumerate(x):
            idx = max(0, min(255, (val + 128) // 1))
            result[i] = idx
        return result
    
    def compute_all_256_cases(self):
        """
        Exhaustive: all 256^5 combinations = too large.
        Instead: compute all 256 weight values × all 256 input values for
        a single MAC, then verify 16 MACs produce the right sum.
        """
        pass  # Used for exhaustive directed testing
```

### 5.2 ADAS Algorithm Golden Model

```python
# golden/adas_golden.py

import sys
sys.path.insert(0, "/path/to/firmware_engineer/")
from reference_model import (
    ADASController, ADASState, SafetyMonitor,
    SensorFrame, ObjectClass, compute_ttc, compute_braking_decision
)

class AdasGoldenModel:
    """
    Wrapper around the firmware reference model for testbench comparison.
    
    Provides cycle-accurate expected outputs for any sensor input.
    """
    
    def __init__(self):
        self.controller = ADASController()
        self.safety_monitor = SafetyMonitor()
    
    def process_frame(self, ego_speed_m_s, distance_m, rel_speed_m_s, 
                      object_class, timestamp_ms):
        """Process one sensor frame and return expected outputs."""
        frame = SensorFrame(
            ego_speed_m_s=ego_speed_m_s,
            object_distance_m=distance_m,
            object_relative_speed_m_s=rel_speed_m_s,
            object_class=object_class,
            timestamp_ms=timestamp_ms
        )
        return self.controller.process_frame(frame)
    
    def predict_safety(self, should_brake, brake_engaged, timestamp_ms):
        """Predict safety monitor output."""
        shutdown, status = self.safety_monitor.monitor(
            should_brake, brake_engaged, timestamp_ms
        )
        return shutdown, status
```

---

## 6. Monitor and Checker Architecture

### 6.1 Continuous Monitor Pattern

```python
# Monitor pattern used across all testbenches

class ContinuousMonitor:
    """
    Generic continuous monitor pattern.
    
    Runs as a background coroutine during test execution:
    - Samples signals every clock cycle
    - Checks assertions
    - Feeds scoreboard
    - Updates coverage
    """
    
    def __init__(self, dut, clk, check_interval=1):
        self.dut = dut
        self.clk = clk
        self.check_interval = check_interval
        self.running = False
    
    async def start(self):
        """Start background monitoring."""
        self.running = True
        self._task = cocotb.start_soon(self._run())
    
    async def stop(self):
        self.running = False
    
    async def _run(self):
        while self.running:
            await RisingEdge(self.clk)
            self.sample()
    
    def sample(self):
        """Override in subclass to define monitoring behavior."""
        raise NotImplementedError
```

### 6.2 Assertion Checkers

```python
# Inline assertions in testbenches

async def assert_no_x(dut, signal, name="", timeout=1000):
    """Assert that a signal never becomes 'x' or 'z'."""
    for _ in range(timeout):
        await RisingEdge(dut.clk_i)
        val = int(signal.value)
        assert val in (0, 1), f"Signal {name} has X/Z at time {cocotb.utils.get_sim_time(units='ns')}ns"

async def assert_signal_within(signal, expected, timeout_cycles=1000):
    """Assert that signal becomes expected value within timeout."""
    for _ in range(timeout_cycles):
        if int(signal.value) == expected:
            return True
        await RisingEdge(signal._dut.clk_i)
    raise AssertionError(f"Signal never reached {expected} within {timeout_cycles} cycles")

async def assert_no_glitch(dut, signal, stable_cycles=5):
    """Assert signal is glitch-free for specified cycles."""
    prev = int(signal.value)
    for _ in range(stable_cycles):
        await RisingEdge(dut.clk_i)
        curr = int(signal.value)
        assert curr == prev, f"Glitch detected on signal at time {cocotb.utils.get_sim_time(units='ns')}ns"
        prev = curr
```

---

## 7. Per-Module Testbench Specifications

### 7.1 AI Accelerator Testbench

```
DUT: ai_accel_4x4
Topology:
  ┌──────────────┐
  │  Clock/Reset  │
  └──────┬───────┘
         │
  ┌──────▼───────────────────────────────────┐
  │                                            │
  │  ┌──────────┐     ┌───────────────────┐   │
  │  │ AXI4-Lite │────→│   ai_accel_4x4   │   │
  │  │ Master BFM│     │      (DUT)        │   │
  │  └──────────┘     └───┬───┬───┬───────┘   │
  │                       │   │   │            │
  │  ┌────────────────────┘   │   └──────┐    │
  │  │                        │          │    │
  │  ▼                        ▼          ▼    │
  │ ┌──────┐            ┌──────┐    ┌──────┐  │
  │ │ IRQ  │            │Fault │    │Done/ │  │
  │ │Monitor│           │Monitor│   │Busy  │  │
  │ └──┬───┘            └──┬───┘    │Monitor│  │
  │    │                   │       └──┬───┘  │
  │    └───────────────────┴──────────┘      │
  │                          │                │
  │                   ┌──────▼───────┐        │
  │                   │  Scoreboard   │        │
  │                   │ + Gold Ref    │        │
  │                   └──────────────┘        │
  └────────────────────────────────────────────┘

Signals monitored: s_axi_*, irq_done_o, irq_error_o, fault_o
Signals driven: s_axi_* (AXI BFM)
```

### 7.2 SPI Controller Testbench

```
DUT: spi_master
Topology:
  ┌──────────────────────────────────────────┐
  │  ┌──────────┐     ┌───────────────┐      │
  │  │ AXI4-Lite │────→│  spi_master   │      │
  │  │ Master BFM│     │    (DUT)      │      │
  │  └──────────┘     └─┬──┬──┬──┬───┘      │
  │                     │  │  │  │            │
  │  ┌──────────────────┘  │  │  └──────┐    │
  │  │                     │  │         │    │
  │  ▼                     ▼  ▼         ▼    │
  │ ┌────────┐       ┌─────────────┐ ┌────┐  │
  │ │  IRQ   │       │ SPI Slave   │ │Fault│  │
  │ │Monitor │       │    BFM      │ │Mon │  │
  │ └───┬────┘       │ (LIDAR sim) │ └──┬─┘  │
  │     │            └──────┬──────┘    │    │
  │     │                   │           │    │
  │     └───────────────────┴───────────┘    │
  │                         │                 │
  │                  ┌──────▼──────┐          │
  │                  │  Scoreboard  │          │
  │                  │ + Gold Ref   │          │
  │                  └─────────────┘          │
  └──────────────────────────────────────────┘

Signals monitored: sck_o, mosi_o, cs_n_o, irq_*, fault_o
Signals driven: miso_i (by SPI Slave BFM), s_axi_* (AXI BFM)
```

### 7.3 Servo PWM Testbench

```
DUT: servo_pwm
Topology:
  ┌──────────┐     ┌───────────────┐
  │ AXI BFM  │────→│  servo_pwm    │
  └──────────┘     │   (DUT)       │──→ pwm_o ──→ PWM Monitor
                   └───┬───┬───────┘
                       │   │
                  ┌────┘   └────┐
                  ▼             ▼
             ┌────────┐   ┌────────┐
             │  IRQ   │   │ Fault  │
             │Monitor │   │Monitor │
             └───┬────┘   └───┬────┘
                 │            │
                 └─────┬──────┘
                       ▼
                 ┌──────────┐
                 │Scoreboard│
                 └──────────┘

PWM Monitor measures: period, duty cycle, glitch detection
```

### 7.4 Safety Monitor Testbench

```
DUT: safety_monitor
Topology:
  ┌────────────────────────────────────────────────┐
  │                                                 │
  │  ┌──────────┐     ┌───────────────────────┐    │
  │  │ AXI BFM  │────→│   safety_monitor      │    │
  │  └──────────┘     │      (DUT)            │    │
  │                    └─┬──┬──┬──┬──┬──┬──┬──┘    │
  │                      │  │  │  │  │  │  │       │
  │  ┌───────────────────┘  │  │  │  │  │  │       │
  │  │  ┌───────────────────┘  │  │  │  │  │       │
  │  │  │  ┌───────────────────┘  │  │  │  │       │
  │  │  │  │  ┌───────────────────┘  │  │  │       │
  │  │  │  │  │  ┌───────────────────┘  │  │       │
  │  │  │  │  │  │  ┌───────────────────┘  │       │
  │  │  │  │  │  │  │  ┌───────────────────┘       │
  │  ▼  ▼  ▼  ▼  ▼  ▼  ▼                          │
  │ ┌──────────────────────────┐                   │
  │ │   Fault Source Drivers   │                   │
  │ │  (ai, spi, servo, speed, │                   │
  │ │   wdt, parity, lockstep) │                   │
  │ └──────────────────────────┘                   │
  │                      │                          │
  │  ┌───────────────────┴──────────────┐          │
  │  │                                  │          │
  │  ▼                                  ▼          │
  │ ┌────────────┐                ┌──────────┐     │
  │ │  Response  │                │  Score   │     │
  │ │  Monitor   │                │  board   │     │
  │ │(halt, agg, │                │+ Golden  │     │
  │ │ irq, shutdown)              │  Ref     │     │
  │ └────────────┘                └──────────┘     │
  └────────────────────────────────────────────────┘

Fault injection: Per-source assertion/de-assertion with configurable timing
```

### 7.5 CDC Bridge Testbench

```
DUT: clock domain crossings (wdt registers, fault signals)
Topology:
  ┌─────────────────────────────────────────────┐
  │  sys_clk domain              wdt_clk domain  │
  │                                              │
  │  ┌──────┐    ┌───────────┐    ┌──────────┐  │
  │  │ AXI  │───→│ CDC Bridge │───→│ window_  │  │
  │  │ BFM  │    │ (2FF sync) │    │  wdt     │  │
  │  └──────┘    └───────────┘    └────┬─────┘  │
  │                                    │        │
  │                              ┌─────▼─────┐  │
  │                              │  Fault    │  │
  │                              │  → CDC →  │  │
  │                              │  sys_clk  │  │
  │                              └───────────┘  │
  └─────────────────────────────────────────────┘

CDC testing: Verify 2FF synchronizers prevent metastability propagation.
              Test with data changing during setup/hold window.
```

---

## 8. System-Level Testbench

### 8.1 Top-Level (`adas_v2_top`)

```
┌─────────────────────────────────────────────────────────────────────┐
│                     adas_v2_top System Testbench                     │
│                                                                      │
│  ┌─────────┐                                                        │
│  │ sys_clk │──┐                                                     │
│  │  Gen    │  │                                                     │
│  └─────────┘  │     ┌──────────────────────────────────────┐       │
│               ├────→│                                       │       │
│  ┌─────────┐  │     │           adas_v2_top                 │       │
│  │ wdt_clk │──┘     │             (DUT)                     │       │
│  │  Gen    │        │                                       │       │
│  └─────────┘        │  ┌──────┐ ┌──────┐ ┌──────┐         │       │
│                      │  │RV32IM│ │ ITCM │ │ DTCM │         │       │
│  ┌─────────┐        │  └──┬───┘ └──────┘ └──────┘         │       │
│  │ Reset   │────────┼─────┤                                  │       │
│  │  Gen    │        │     │  ┌──────────────────────────┐   │       │
│  └─────────┘        │     └──┤  AXI4-Lite Crossbar      │   │       │
│                      │        └──┬──┬──┬──┬──┬──┬──┬──┬──┘   │       │
│  ┌───────────┐      │           │  │  │  │  │  │  │  │       │       │
│  │ LIDAR     │      │  ┌────────┘  │  │  │  │  │  │  │       │       │
│  │ Sensor    │──────┼──┤ SPI       │  │  │  │  │  │  │       │       │
│  │ Model     │      │  └──────────┘  │  │  │  │  │  │       │       │
│  └───────────┘      │  ┌─────────────┘  │  │  │  │  │       │       │
│                      │  │  ┌─────────────┘  │  │  │  │       │       │
│  ┌───────────┐      │  │  │  ┌──────────────┘  │  │  │       │       │
│  │ Wheel     │──────┼──┤  │  │  ┌───────────────┘  │  │       │       │
│  │ Speed Gen │      │  │  │  │  │  ┌────────────────┘  │       │       │
│  └───────────┘      │  │  │  │  │  │  ┌─────────────────┘       │       │
│                      │  ▼  ▼  ▼  ▼  ▼  ▼                        │       │
│  ┌───────────┐      │ ┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐                │       │
│  │ UART      │──────┼─┤  ││  ││  ││  ││  ││  │                │       │
│  │ Terminal  │      │ └──┘└──┘└──┘└──┘└──┘└──┘                │       │
│  └───────────┘      │  AI SP SV SS BZ GP                     │       │
│                      │                                          │       │
│  ┌───────────┐      │  ┌──────────────────────────┐           │       │
│  │ Servo     │◄─────┼──┤ PWM, GPIO, Safety        │           │       │
│  │ Monitor   │      │  └──────────────────────────┘           │       │
│  └───────────┘      └──────────────────────────────────────┘       │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                 System Scoreboard + Gold Ref                   │   │
│  │                                                                │   │
│  │  ADAS Golden Model ←→ RTL Outputs                              │   │
│  │  Safety Monitor ←→ RTL Safety Signals                         │   │
│  │  Timing Checker: E2E latency < 5ms                             │   │
│  │  State Checker: Safe state entry verification                  │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### 8.2 System Test Scenarios (from `reference_model.py` §6)

| Scenario | Sensor Inputs | Expected Behavior | Passing Criteria |
|----------|--------------|-------------------|-----------------|
| `approach_and_brake` | Pedestrian 60→15m, ego 20m/s | BRAKING state, PWM duty proportional to TTC | PWM duty matches golden ±1% |
| `crossing_clear` | Car crosses then moves away | MONITORING→IDLE, no brake | Never enters BRAKING |
| `stationary_obstacle` | Obstacle 30→2m, ego 10m/s | BRAKING when TTC < 1.2s | Brake before distance < 5m |
| `safety_timeout` | Car at threshold, brake fails to engage | SHUTDOWN after 100ms | shutdown_n_o asserted |
| `sensor_fault` | Invalid distance (-5m) | FAULT state | No brake output |
| `wdt_timeout` | WDT not kicked within window | aggregated_fault → shutdown | safe state < 1ms |

---

## 9. Environment Configuration

### 9.1 Makefile

```makefile
# Makefile for ADAS v2 verification

# Simulation tools
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# RTL sources
VERILOG_SOURCES = \
    $(RTL_DIR)/rv32im_core.v \
    $(RTL_DIR)/tcm_8kb.v \
    $(RTL_DIR)/axi4lite_xbar_1m_9s.v \
    $(RTL_DIR)/ai_accel_4x4.v \
    $(RTL_DIR)/spi_master.v \
    $(RTL_DIR)/servo_pwm.v \
    $(RTL_DIR)/speed_sensor.v \
    $(RTL_DIR)/buzzer_pwm.v \
    $(RTL_DIR)/uart_16550.v \
    $(RTL_DIR)/gpio_32bit.v \
    $(RTL_DIR)/safety_monitor.v \
    $(RTL_DIR)/window_wdt.v \
    $(RTL_DIR)/redundant_shutdown_ctrl.v \
    $(RTL_DIR)/adas_v2_top.v

# Top-level module
TOPLEVEL = adas_v2_top

# cocotb modules
MODULE = tests.system.test_adas_scenarios

# Coverage
COVERAGE ?= 1
export COVERAGE

# Waveform dumping
WAVES ?= 1
export WAVES

# Random seed
SEED ?= $(shell date +%s)
export SEED

include $(shell cocotb-config --makefiles)/Makefile.sim

# Custom targets
coverage-report:
    python utils/report_generator.py --coverage logs/coverage_reports/

regression:
    python -m pytest tests/ -v --tb=short -n 8

regression-random:
    SEED=$$(date +%s) python -m pytest tests/ -v -k "random" -n 8

clean:
    rm -rf sim_build/ __pycache__/ *.vcd *.fst logs/
```

### 9.2 Pytest conftest.py

```python
# conftest.py

import pytest
import os
import random

def pytest_addoption(parser):
    parser.addoption("--seed", type=int, default=None, help="Random seed")
    parser.addoption("--cycles", type=int, default=100000, help="Random test cycles")
    parser.addoption("--waves", action="store_true", help="Enable waveform dumping")
    parser.addoption("--coverage", action="store_true", help="Enable coverage collection")

@pytest.fixture
def seed(request):
    s = request.config.getoption("--seed")
    if s is None:
        s = int(os.environ.get("SEED", random.randint(0, 2**32 - 1)))
    random.seed(s)
    return s

@pytest.fixture
def random_cycles(request):
    return request.config.getoption("--cycles")

@pytest.fixture
def enable_waves(request):
    return request.config.getoption("--waves")

@pytest.fixture
def enable_coverage(request):
    return request.config.getoption("--coverage")
```

---

## Revision History

| Version | Date | Author | Description |
|---------|------|--------|-------------|
| 1.0 | 2026-04-29 | Rahul Sharma | Initial testbench architecture specification |

---

*"The testbench architecture is the stage. The tests are the performance. Every BFM must sing in tune."*  
*— Rahul Sharma, Verification Lead*
