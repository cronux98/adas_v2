# ADAS v2 — Fault Injection Plan for Safety Verification

**Document:** VER-FI-001 | **Version:** 1.0 | **Date:** 2026-04-29  
**Author:** Rahul Sharma, Verification Lead  
**Target ASIL:** ASIL-D (ISO 26262-5:2018)  
**Coverage:** All 12 safety-critical blocks and mechanisms  

---

## Table of Contents

1. [Fault Injection Strategy](#1-fault-injection-strategy)
2. [Fault Models and Injection Methods](#2-fault-models-and-injection-methods)
3. [Lockstep Comparator Fault Injection](#3-lockstep-comparator-fault-injection)
4. [Memory ECC/Parity Fault Injection](#4-memory-eccparity-fault-injection)
5. [Window Watchdog Fault Injection](#5-window-watchdog-fault-injection)
6. [Redundant Shutdown Fault Injection](#6-redundant-shutdown-fault-injection)
7. [Peripheral Fault Injection](#7-peripheral-fault-injection)
8. [System-Level Fault Injection](#8-system-level-fault-injection)
9. [Diagnostic Coverage Measurement](#9-diagnostic-coverage-measurement)
10. [Fault Injection Automation](#10-fault-injection-automation)

---

## 1. Fault Injection Strategy

### 1.1 Safety Philosophy

*"A safety mechanism you haven't tested is a safety mechanism you don't have."*

Every ASIL-D safety mechanism must be verified by active fault injection.
We don't assume — we inject faults and measure the response.

### 1.2 Fault Injection Taxonomy

```
┌────────────────────────────────────────────────────────────┐
│                   FAULT INJECTION TYPES                     │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐                  │
│  │  STUCK-AT       │  │  TRANSIENT      │                  │
│  │  (permanent)    │  │  (single-event) │                  │
│  │                 │  │                 │                  │
│  │  • SA0 (stuck   │  │  • Bit flip     │                  │
│  │    at 0)        │  │  • Glitch       │                  │
│  │  • SA1 (stuck   │  │  • Pulse        │                  │
│  │    at 1)        │  │  • Timing       │                  │
│  └────────┬────────┘  └────────┬────────┘                  │
│           │                    │                             │
│  ┌────────▼────────────────────▼────────┐                  │
│  │         INJECTION POINTS              │                  │
│  │                                       │                  │
│  │  • RTL signal force (simulator)       │                  │
│  │  • Register bit flip (via BFM)        │                  │
│  │  • Memory corruption (via BFM)        │                  │
│  │  • Clock manipulation (period/jitter) │                  │
│  │  • Reset glitch injection             │                  │
│  │  • CDC stress (setup/hold violation)  │                  │
│  └───────────────────────────────────────┘                  │
└────────────────────────────────────────────────────────────┘
```

### 1.3 Fault Injection Coverage Targets

| Safety Mechanism | Faults Injected | Detection Target | DC Target |
|-----------------|----------------|-----------------|-----------|
| Lockstep Comparator | 10,000+ | ≥ 99.9% | ASIL-D High |
| Memory Parity/ECC | 5,000+ | ≥ 99% single-bit, 100% double-bit | ASIL-D High |
| Window WDT | 2,000+ | 100% of window violations | ASIL-D High |
| Redundant Shutdown | 1,000+ | 100% combinatorial path | ASIL-D High |
| Fault Aggregation | 1,000+ per source | 100% of sources | ASIL-D High |
| Peripheral faults | 500+ per block | 100% of fault types | ASIL-B/D |

---

## 2. Fault Models and Injection Methods

### 2.1 Stuck-At Fault Model

```python
# fault/stuck_at.py

class StuckAtFault:
    """
    Stuck-at fault injector for RTL signals.
    
    Forces a signal to a fixed value (0 or 1) to simulate
    permanent faults (e.g., wire break, short to VDD/GND).
    """
    
    def __init__(self, dut, signal, stuck_value=0):
        self.dut = dut
        self.signal = signal
        self.stuck_value = stuck_value
        self.original_driver = None
        self.injected = False
    
    async def inject(self):
        """Force signal to stuck-at value."""
        self.injected = True
        self.signal.value = self.stuck_value
    
    async def release(self):
        """Release forced value."""
        self.injected = False
        # Release force — signal returns to normal operation
        self.signal.value = self.signal.value  # Re-evaluate

class StuckAtFaultCampaign:
    """
    Runs a stuck-at fault injection campaign.
    
    For each signal in the target list:
      1. Inject SA0 → run test → check detection
      2. Inject SA1 → run test → check detection
      3. Release fault → run test → confirm recovery
    """
    
    def __init__(self, dut, signals_to_test, test_coroutine, checker_coroutine):
        self.dut = dut
        self.signals = signals_to_test
        self.test_fn = test_coroutine
        self.check_fn = checker_coroutine
        self.results = []
    
    async def run(self):
        for sig_name, sig in self.signals:
            for stuck_val in [0, 1]:
                fault = StuckAtFault(self.dut, sig, stuck_val)
                
                # Inject
                await fault.inject()
                
                # Run test scenario
                await self.test_fn()
                
                # Check detection
                detected, detail = await self.check_fn()
                self.results.append({
                    'signal': sig_name,
                    'fault': f'SA{stuck_val}',
                    'detected': detected,
                    'detail': detail
                })
                
                # Release
                await fault.release()
        
        return self.results
```

### 2.2 Bit-Flip Fault Model

```python
# fault/bit_flip.py

class BitFlipFault:
    """
    Single-event upset (SEU) / transient bit flip injector.
    
    Flips one or more bits in a register or memory word at a
    specific time to simulate cosmic ray / EMI induced errors.
    """
    
    @staticmethod
    async def flip_register(axi_bfm, addr, bit_position, restore_after=True):
        """Flip a single bit in a register via AXI read-modify-write."""
        original = await axi_bfm.read(addr)
        flipped = original ^ (1 << bit_position)
        await axi_bfm.write(addr, flipped)
        
        if restore_after:
            await ClockCycles(axi_bfm.clk, 100)
            await axi_bfm.write(addr, original)
        
        return original, flipped
    
    @staticmethod
    async def corrupt_memory(axi_bfm, base_addr, offset, byte_mask, 
                             corrupt_value=0xFF):
        """Corrupt specific bytes in memory-mapped SRAM."""
        addr = base_addr + offset
        original = await axi_bfm.read(addr)
        corrupted = original ^ corrupt_value
        await axi_bfm.write(addr, corrupted)
        return original, corrupted

class TransientFaultInjector:
    """
    Injects transient faults at specific times during simulation.
    """
    
    def __init__(self, dut, clk):
        self.dut = dut
        self.clk = clk
        self.pending_faults = []
    
    def schedule(self, cycle_offset, fault_fn, *args, **kwargs):
        """Schedule a fault injection at a future cycle."""
        self.pending_faults.append((cycle_offset, fault_fn, args, kwargs))
    
    async def execute_scheduled(self):
        """Execute all scheduled faults at their designated cycles."""
        cycle = 0
        self.pending_faults.sort()
        
        for target_cycle, fn, args, kwargs in self.pending_faults:
            while cycle < target_cycle:
                await RisingEdge(self.clk)
                cycle += 1
            await fn(*args, **kwargs)
        
        self.pending_faults.clear()
```

### 2.3 Clock Fault Injection

```python
# fault/clock_fault.py

class ClockFaultInjector:
    """
    Clock manipulation fault injector for WDT independent clock testing.
    
    Faults:
    - Clock stop (sys_clk freezes)
    - Clock glitch (extra pulse)
    - Clock stretch (extended period)
    - Clock jitter (random period variation)
    """
    
    @staticmethod
    async def stop_clock(dut, clock_signal, duration_ns=100000):
        """Stop sys_clk for specified duration to test WDT independence."""
        # Hold clock low (simulate PLL failure)
        cocotb.start_soon(Clock(clock_signal, 1e12, units='ns').start())
        await Timer(duration_ns, units='ns')
        # Clock needs to be restarted externally
    
    @staticmethod
    async def inject_glitch(dut, clock_signal, glitch_width_ns=1):
        """Inject a narrow clock glitch."""
        await RisingEdge(clock_signal)
        await Timer(glitch_width_ns, units='ns')
        clock_signal.value = ~int(clock_signal.value)
        await Timer(glitch_width_ns, units='ns')
        clock_signal.value = ~int(clock_signal.value)
```

---

## 3. Lockstep Comparator Fault Injection

### 3.1 Fault Injection Architecture

```
                           ┌─────────────────┐
                           │   RV32IM Core    │
                           │                  │
┌──────────────────┐      │  lockstep_out[31] │────┐
│  Fault Injector  │─────→│  lockstep_pc[31]  │    │
│                  │      │  lockstep_valid   │    │
│  Inject:         │      └──────────────────┘    │
│  - SA0/SA1       │                               │
│  - bit flip      │      ┌──────────────────┐    │
│  - timing skew   │      │   Safety Monitor  │    │
│  - value corrupt │      │                  │    │
└──────────────────┘      │  Lockstep Comp   │◄───┘
                          │                  │
                          │  mismatch?       │──→ aggregated_fault
                          │  irq_lockstep    │──→ CPU IRQ
                          └──────────────────┘
```

### 3.2 Injection Points

| Injection Point | Fault Type | Expected Detection | Latency |
|----------------|-----------|-------------------|---------|
| `lockstep_outputs_o[0]` | SA0 | Lockstep mismatch | < 3 cycles |
| `lockstep_outputs_o[31]` | SA1 | Lockstep mismatch | < 3 cycles |
| `lockstep_pc_o[15:0]` | SA0 (any bit) | Lockstep mismatch | < 3 cycles |
| `lockstep_valid_o` | SA0 | No valid comparison → timeout | Variable |
| `lockstep_valid_o` | SA1 | Spurious comparison → mismatch | < 3 cycles |
| Any output bit | Transient flip | Lockstep mismatch | < 3 cycles |
| Two simultaneous bits | Double flip | Lockstep mismatch | < 3 cycles |

### 3.3 Lockstep Fault Injection Test Suite

```
Test: test_fault_lockstep_stuck_at.py

For each lockstep output bit (32 output + 32 PC + 1 valid = 65 bits):
  For each stuck value (SA0, SA1):
    1. Load known test program into ITCM
    2. Enable lockstep comparator
    3. Inject stuck-at fault on target bit
    4. Run CPU for 100 cycles
    5. Assert: lockstep mismatch detected
    6. Assert: irq_lockstep_o asserted
    7. Assert: aggregated_fault_o asserted (if configured)
    8. Release fault
    9. Assert: lockstep recovers (no persistent mismatch)

Test: test_fault_lockstep_transient.py

For 10,000 randomized transient injections:
  1. Random bit position (0-64)
  2. Random injection cycle (10-1000)
  3. Inject single-cycle bit flip
  4. Assert: mismatch detected within 3 cycles
  5. Assert: SAFETY_FAULT_STATUS bit 0 set
  6. Clear fault status
  7. Continue normal operation

Test: test_fault_lockstep_delay_config.py

For each delay config (1, 2, 3, 4 cycles):
  For each threshold (0, 1, 2):
    1. Configure lockstep with delay + threshold
    2. Inject N mismatches (N ≤ threshold: no fault; N > threshold: fault)
    3. Verify correct behavior per configuration
```

### 3.4 Diagnostic Coverage Measurement for Lockstep

```python
# fault/lockstep_campaign.py

class LockstepDCMeasurement:
    """
    Measures diagnostic coverage of the lockstep comparator.
    
    DC = faults_detected / total_faults_injected
    
    Tracks:
    - True Positive (TP): Fault injected, fault detected
    - False Negative (FN): Fault injected, NOT detected  ← WORST CASE
    - True Negative (TN): No fault, no detection
    - False Positive (FP): No fault, detection (nuisance trip)
    """
    
    def __init__(self):
        self.tp = 0
        self.fn = 0
        self.tn = 0
        self.fp = 0
        self.fn_cases = []  # Detailed log of missed detections
    
    @property
    def diagnostic_coverage(self):
        total = self.tp + self.fn
        return self.tp / total if total > 0 else 1.0
    
    @property
    def false_positive_rate(self):
        total = self.tn + self.fp
        return self.fp / total if total > 0 else 0.0
    
    def report(self):
        print(f"Lockstep DC: {self.diagnostic_coverage:.4f} "
              f"({self.tp} TP, {self.fn} FN, {self.tn} TN, {self.fp} FP)")
        if self.fn:
            print(f"  MISSED DETECTIONS ({len(self.fn)}):")
            for case in self.fn[:10]:
                print(f"    - {case}")
```

---

## 4. Memory ECC/Parity Fault Injection

### 4.1 Fault Injection Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   CPU write  │────→│    TCM       │────→│   CPU read   │
│   data[31:0] │     │  (ITCM/DTCM) │     │   data[31:0] │
└──────────────┘     └──────┬───────┘     └──────────────┘
                            │
                    ┌───────▼────────┐
                    │  Fault Inject  │
                    │                │
                    │  Memory array  │
                    │  bit flip      │
                    │  (force node)  │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │  Parity Check  │
                    │                │
                    │  parity_err_o──┼──→ Fault Aggregator
                    └────────────────┘
```

### 4.2 Injection Points

| Injection | Fault | Expected Result | Severity |
|-----------|-------|----------------|----------|
| Data bit 0 | SEU (flip) | parity_err_o = 1 | Depends on safety config |
| Data bit 15 | SEU | parity_err_o = 1 | — |
| Parity bit itself | SEU | parity_err_o = 1 on read | — |
| Two data bits | Double SEU | May miss (parity limitation) | **GAP** — document |
| Write data | Transient | parity_err_o on next read | — |
| Address decode | SA0/SA1 | Wrong address accessed | — |

### 4.3 Parity Fault Injection Test Suite

```
Test: test_fault_parity_single_bit.py

For each bit position (0-31 data + 0-3 parity = 36 positions):
  1. Write known pattern to memory address
  2. Corrupt one bit via backdoor force
  3. Read memory address
  4. Assert: parity_err_o = 1
  5. Assert: fault propagated to safety_monitor
  6. Assert: SAFETY_FAULT_STATUS bit 7 or 8 set
  7. Clear fault

Test: test_fault_parity_double_bit.py

For each pair of bit positions (select 100 random pairs):
  1. Write known pattern
  2. Corrupt two bits
  3. Read memory
  4. Observe: parity_err_o behavior
  5. Document: parity may or may not detect double errors
  6. If ECC (not just parity): verify double-bit detection

Test: test_fault_parity_during_operation.py

Randomized test:
  - CPU executing program from ITCM
  - Inject random SEUs during execution
  - Verify: CPU traps on parity error or safety monitor halts CPU
  - Verify: SAFETY_FAULT_STATUS captures correct source
```

### 4.4 Parity vs. ECC Coverage Analysis

| Memory Type | Protection | Single-Bit DC | Double-Bit DC | Notes |
|------------|-----------|--------------|--------------|-------|
| ITCM | Parity (1b/byte) | 100% detect | ~50% detect | Parity: detect only, no correct |
| DTCM | Parity (1b/byte) | 100% detect | ~50% detect | Parity: detect only, no correct |
| AI buffer (future) | Target ECC (7b/32b) | 100% correct | 100% detect | SEC-DED |

---

## 5. Window Watchdog Fault Injection

### 5.1 Fault Injection Architecture

```
┌─────────────────────────────────────────────────────────┐
│                Window WDT Fault Injection                 │
│                                                          │
│  ┌──────────┐     ┌──────────────┐     ┌──────────────┐ │
│  │ wdt_clk  │────→│  window_wdt  │────→│ fault_o      │→│→ RSC
│  │ 32.768k  │     │              │────→│ prewarn_o    │→│→ IRQ
│  └──────────┘     └──────┬───────┘     └──────────────┘ │
│                          │                               │
│                   ┌──────▼────────┐                     │
│                   │  Fault Types  │                     │
│                   │               │                     │
│                   │ 1. wdt_clk    │                     │
│                   │    failure    │                     │
│                   │ 2. Register   │                     │
│                   │    corruption │                     │
│                   │ 3. Counter    │                     │
│                   │    stuck      │                     │
│                   │ 4. Bad kick   │                     │
│                   │    sequence   │                     │
│                   └───────────────┘                     │
└─────────────────────────────────────────────────────────┘
```

### 5.2 Injection Points and Scenarios

| Fault Scenario | Injection Method | Expected Response | Timing |
|---------------|-----------------|-------------------|--------|
| wdt_clk stops | Stop wdt_clk oscillator | WDT counter freezes (no timeout) | — |
| wdt_clk glitch | Inject extra pulse | Counter may skip → earlier timeout | If TIMEOUT reached: fault |
| Early kick (closed window) | CPU writes WDT_KICK before WINDOW | EARLY_KICK status + fault_o | Immediate |
| Late kick (after timeout) | CPU delays kick beyond TIMEOUT | TIMED_OUT status + fault_o | At TIMEOUT |
| No kick (timeout) | CPU never kicks WDT | TIMED_OUT status + fault_o | At TIMEOUT |
| Bad kick value | Write incorrect value to WDT_KICK | Counter NOT reset → eventual timeout | At TIMEOUT |
| Bad write key | Write to CTRL without 0x5A key | Register unchanged | No write |
| Disable attempt | Write ENABLE=0 after enabled | ENABLE stays 1 (locked) | No change |
| Lock override attempt | Write LOCKed register | Register unchanged | No write |
| Counter SA0 | Force counter to 0 | Never reaches TIMEOUT | — (fail-safe) |
| Counter SA1 | Force counter to MAX | Immediate timeout → fault | Immediate |
| Window config corruption | Corrupt WDT_WINDOW register bits | Window opens at wrong time | Depends on corruption |
| CDC data corruption | Corrupt AXI write to WDT registers | Wrong config → unexpected behavior | Depends |

### 5.3 WDT Fault Injection Test Suite

```
Test: test_fault_wdt_early_kick.py (1000 iterations with random timing)
  1. Configure WDT: TIMEOUT=T, WINDOW=75%*T
  2. Enable WDT
  3. Randomly decide: kick early (before WINDOW)
  4. Verify: WDT_STATUS = EARLY_KICK
  5. Verify: fault_o asserted
  6. Verify: SAFETY_FAULT_STATUS bit 2 set

Test: test_fault_wdt_timeout.py (500 iterations with random timeout values)
  1. Configure WDT with random TIMEOUT (10-1000 ms effective)
  2. Enable WDT
  3. Wait beyond TIMEOUT without kicking
  4. Verify: WDT_STATUS = TIMED_OUT
  5. Verify: fault_o asserted
  6. Verify: aggregated_fault → RSC → shutdown

Test: test_fault_wdt_bad_kick.py
  1. Enable WDT
  2. Write incorrect values to WDT_KICK:
     - 0x00000000
     - 0xFFFFFFFF
     - 0xAC53_CAFD (off by one)
     - 0xDEAD_BEEF
     - Read (should return 0, not kick)
  3. Verify: WDT counter NOT reset
  4. Verify: eventual timeout → fault

Test: test_fault_wdt_clock_failure.py
  1. Enable WDT
  2. Remove sys_clk (simulate PLL failure)
  3. Verify: WDT continues counting on wdt_clk
  4. Wait for WDT timeout
  5. Verify: fault_o asserted even without sys_clk
  6. Verify: RSC shutdown path still functional
```

---

## 6. Redundant Shutdown Fault Injection

### 6.1 RSC Verification Strategy

The RSC is a **combinatorial OR** of fault sources with **no clocked elements** in the critical path. This means fault injection must verify:

1. **Each input path** (aggregated_fault, force_shutdown_sw) triggers shutdown
2. **Output integrity** — both shutdown_n bits toggle, alert_n asserts
3. **Latching** — shutdown holds until power-cycle
4. **CDC synchronization** — inputs from sys_clk domain correctly synchronized
5. **Independence from sys_clk** — shutdown works with sys_clk absent

### 6.2 RSC Fault Injection Test Suite

```
Test: test_fault_rsc_aggregated_input.py
  For each fault source (lockstep, wdt, servo, etc.):
    1. Assert fault source (cause aggregated_fault_i = 1)
    2. Verify: alert_n_o = 0 within 1 wdt cycle
    3. Verify: shutdown_n_o [1:0] = 00 within 10 wdt cycles
    4. Verify: shutdown_n_o remains latched
    5. Apply warm reset; verify: shutdown_n_o STILL asserted
    6. Apply POR; verify: shutdown_n_o released

Test: test_fault_rsc_sw_shutdown.py
  1. Assert force_shutdown_sw_i = 1 (from GPIO/CPU)
  2. Verify: shutdown_n_o asserted
  3. Verify: force_shutdown_o = 1 (to GPIO redundancy)

Test: test_fault_rsc_no_sysclk.py
  1. Remove sys_clk (stop clock)
  2. Assert aggregated_fault_i = 1
  3. Verify: alert_n_o still asserts (combinatorial)
  4. Verify: shutdown_n_o still asserts
  5. This is the KEY ASIL-D requirement: safety path works without CPU clock

Test: test_fault_rsc_cdc_inputs.py
  1. Toggle aggregated_fault_i at random phases relative to wdt_clk
  2. Verify: no metastability propagation (check via simulation timing)
  3. Verify: fault correctly synchronized and latched

Test: test_fault_rsc_output_redundancy.py
  1. Verify shutdown_n_o[0] and shutdown_n_o[1] are independent
  2. Force SA0 on shutdown_n_o[0]; verify shutdown_n_o[1] still works
  3. Force SA1 on shutdown_n_o[0]; verify shutdown_n_o[1] still works
  4. Force SA0 on alert_n_o; verify shutdown_n_o still works
  5. Force SA1 on alert_n_o; verify shutdown_n_o still works
```

---

## 7. Peripheral Fault Injection

### 7.1 AI Accelerator Fault Injection

| Fault | Injection | Expected Response |
|-------|----------|-------------------|
| Weight buffer parity error | Corrupt weight SRAM | ERROR status + irq_error_o + fault_o |
| Output overflow | Provide weights/inputs that overflow INT32 | ERROR code = 0x02 |
| Invalid activation config | Write invalid activation register | ERROR code = 0x03 |
| GO during BUSY | Write GO=1 while BUSY=1 | GO ignored (or error) |
| GO with incomplete weights | Write GO without all weights loaded | ERROR code = 0x01 |

### 7.2 SPI Controller Fault Injection

| Fault | Injection | Expected Response |
|-------|----------|-------------------|
| Mode fault | Drive multiple CS active | irq_err_o + fault_o |
| RX overflow | Send data faster than CPU reads RX FIFO | RX overflow flag + irq_err_o |
| CRC error | Corrupt received SPI frame CRC byte | Frame discarded, CRC error counter |
| MISO stuck-at | Force miso_i = 0 or 1 | All received bytes = forced value (detected by firmware CRC) |
| SCK stuck-at | Force sck_o = 0 or 1 | No transactions complete (detected by timeout) |

### 7.3 Servo PWM Fault Injection

| Fault | Injection | Expected Response |
|-------|----------|-------------------|
| PWM output SA0 | Force pwm_o = 0 | Readback mismatch → fault if FAULT_EN=1 |
| PWM output SA1 | Force pwm_o = 1 | Readback mismatch → fault |
| Readback path SA0 | Force readback to 0 (stuck-low detect) | irq_fault_o + fault_o |
| Readback path SA1 | Force readback to 1 (stuck-high detect) | irq_fault_o + fault_o |
| Period counter stuck | Force counter to fixed value | PWM output wrong → fault |

### 7.4 Speed Sensor Fault Injection

| Fault | Injection | Expected Response |
|-------|----------|-------------------|
| Sensor stuck (no pulse) | Stop generating pulses | SENSOR_STUCK status + fault_o (if STUCK_ACTION=1) |
| Glitch injection | Inject <100ns pulses | Pulses rejected (filter) — no count increment |
| Counter rollover SA1 | Force COUNT to all-ones | COUNT_OVF status + irq_ovf_o |
| Timestamp counter stuck | Force timestamp to fixed value | Period computation incorrect (detected by firmware) |

---

## 8. System-Level Fault Injection

### 8.1 End-to-End Fault → Shutdown Latency Measurement

For each fault source, measure end-to-end latency:

```
Fault Injected → Detection → Aggregation → RSC → shutdown_n_o

Measured in wdt_clk cycles (32.768 kHz = ~30.5 µs/cycle)

| Fault Source        | Target Latency | Measured |
|--------------------|---------------|----------|
| Lockstep mismatch  | < 10 wdt cycles (305 µs) | TBD |
| WDT timeout        | < 10 wdt cycles | TBD |
| Servo stuck-at     | < 50 wdt cycles (1.5 ms) | TBD |
| Memory parity error| < 10 wdt cycles | TBD |
```

### 8.2 Multi-Fault Scenario Testing

```
Test: test_fault_simultaneous.py

Inject two independent faults simultaneously:
  - WDT timeout + SPI CRC error
  Verify: Both faults logged in SAFETY_FAULT_STATUS
  Verify: Shutdown triggered by highest-severity fault (WDT = CRITICAL)
  Verify: SPI fault also recorded (not masked by shutdown)

Test: test_fault_cascading.py

Inject fault that causes secondary fault:
  - CPU lockstep mismatch → core_halt_o → CPU stops kicking WDT → WDT timeout
  Verify: First fault (lockstep) detected
  Verify: Secondary fault (WDT) also detected
  Verify: System enters safe state
  Verify: FAULT_STATUS captures all contributing faults
```

### 8.3 Fault Recovery Testing

```
Test: test_fault_recovery.py

For recoverable faults (LOW/MEDIUM severity):
  1. Inject recoverable fault (SPI error, sensor stuck)
  2. Verify: IRQ asserted, fault logged
  3. CPU clears fault (write-1-to-clear)
  4. Verify: Fault status cleared
  5. Verify: Normal operation resumes
  6. Verify: FAULT_COUNT incremented

For unrecoverable faults (CRITICAL):
  1. Inject critical fault (lockstep mismatch, WDT timeout)
  2. Verify: System enters safe state
  3. Attempt: CPU writes to clear fault
  4. Verify: System stays in safe state (no software recovery)
  5. Apply: Power-cycle reset (POR)
  6. Verify: System boots cleanly
```

---

## 9. Diagnostic Coverage Measurement

### 9.1 ISO 26262-5:2018 Diagnostic Coverage

```
┌─────────────────────────────────────────────────────────────┐
│              DIAGNOSTIC COVERAGE MATRIX                      │
│                                                              │
│  Fault Class         │ Method            │ DC Target │ Result │
│  ─────────           │ ──────            │ ────────  │ ────── │
│  ALU stuck-at        │ Lockstep          │ ≥ 99%    │ TBD   │
│  Register file stuck │ Lockstep          │ ≥ 99%    │ TBD   │
│  Decoder stuck-at    │ Lockstep          │ ≥ 99%    │ TBD   │
│  PC stuck-at         │ Lockstep          │ ≥ 99%    │ TBD   │
│  Memory single-bit   │ Parity            │ ≥ 99%    │ TBD   │
│  Memory double-bit   │ Parity (detect)   │ ≥ 50%    │ TBD   │
│  Temporal execution  │ Window WDT        │ ≥ 99%    │ TBD   │
│  Brake actuator      │ Servo readback    │ ≥ 90%    │ TBD   │
│  SPI communication   │ CRC-8             │ ≥ 90%    │ TBD   │
│  Sensor stuck        │ Stuck detection   │ ≥ 90%    │ TBD   │
│  Clock failure       │ Independent WDT   │ ≥ 99%    │ TBD   │
│  Power glitch        │ POR + reset       │ N/A      │ TBD   │
└─────────────────────────────────────────────────────────────┘
```

### 9.2 SPFM / LFM Calculation

```
SPFM (Single-Point Fault Metric):
  SPFM = 1 - (Σ λ_SPF + Σ λ_RF) / Σ λ_total
  Target: ≥ 99% for ASIL-D

  λ_SPF = failure rate of single-point faults
  λ_RF  = failure rate of residual faults
  λ_total = total failure rate

LFM (Latent Fault Metric):
  LFM = 1 - Σ λ_MPF_latent / Σ λ_total
  Target: ≥ 90% for ASIL-D

  λ_MPF_latent = failure rate of latent multiple-point faults
```

*Note: Full quantitative FMEDA requires PDK-specific failure rates (λ) from SkyWater. Qualitative assessment performed during verification; quantitative values back-annotated when PDK FIT rates available.*

---

## 10. Fault Injection Automation

### 10.1 Campaign Runner

```python
# fault/campaign_runner.py

class FaultCampaignRunner:
    """
    Automated fault injection campaign manager.
    
    Features:
    - Schedule fault injection test runs
    - Track progress per safety mechanism
    - Generate HTML report with diagnostic coverage
    - Regression: re-run on every RTL change
    """
    
    def __init__(self, config_file="fault_campaign.yaml"):
        self.config = self._load_config(config_file)
        self.results_db = []
    
    def run_all(self):
        """Execute all fault injection tests."""
        campaigns = [
            ("lockstep", self._run_lockstep_campaign),
            ("parity", self._run_parity_campaign),
            ("wdt", self._run_wdt_campaign),
            ("rsc", self._run_rsc_campaign),
            ("peripheral", self._run_peripheral_campaign),
            ("system", self._run_system_campaign),
        ]
        
        for name, campaign_fn in campaigns:
            print(f"\n{'='*60}")
            print(f" Fault Campaign: {name}")
            print(f"{'='*60}")
            results = campaign_fn()
            self.results_db.append((name, results))
            self._print_summary(name, results)
        
        self._generate_report()
    
    def _print_summary(self, name, results):
        total = len(results)
        detected = sum(1 for r in results if r['detected'])
        print(f"  {name}: {detected}/{total} faults detected "
              f"({detected/total*100:.1f}% DC)")
    
    def _generate_report(self):
        """Generate HTML fault injection report."""
        # Implementation: aggregate all results into HTML with charts
        pass
```

### 10.2 Fault Injection Schedule

| Week | Campaign | Faults | Duration |
|------|----------|--------|----------|
| 1 | Lockstep stuck-at (65 signals × 2 values = 130 tests) | 130 | 1 day |
| 1 | Lockstep transient (10,000 random) | 10,000 | 2 days |
| 2 | Memory parity (ITCM + DTCM) | 5,000 | 2 days |
| 2 | Window WDT (all scenarios) | 2,000 | 1 day |
| 3 | Redundant Shutdown (all paths) | 1,000 | 1 day |
| 3 | Peripheral faults (AI, SPI, servo, speed) | 2,000 | 2 days |
| 4 | System-level multi-fault | 1,000 | 2 days |
| 4 | Regression + DC report | — | 1 day |

---

## Revision History

| Version | Date | Author | Description |
|---------|------|--------|-------------|
| 1.0 | 2026-04-29 | Rahul Sharma | Initial comprehensive fault injection plan |

---

*"A safety mechanism is only as good as the fault injection campaign that proves it works. Inject. Detect. Document. Repeat."*  
*— Rahul Sharma, Verification Lead*
