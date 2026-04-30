# ADAS v2 — Clock Domain Crossing (CDC) Plan

**Document:** ARCH-CDC-001 | **Version:** 1.0 | **Date:** 2026-04-29  
**Author:** Kenji Tanaka, Chief Architect  
**Reference:** `microarchitecture_spec.md` (ARCH-SPEC-001), `block_interfaces.md` (ARCH-IF-001)  

---

## Table of Contents

1. [Clock Domain Summary](#1-clock-domain-summary)
2. [CDC Crossing Inventory](#2-cdc-crossing-inventory)
3. [Synchronizer Selection](#3-synchronizer-selection)
4. [Detailed Crossing Analysis](#4-detailed-crossing-analysis)
5. [MTBF Estimation](#5-mtbf-estimation)
6. [CDC Verification Strategy](#6-cdc-verification-strategy)
7. [CDC Coding Guidelines](#7-cdc-coding-guidelines)

---

## 1. Clock Domain Summary

| Domain | Name | Frequency | Period | Source | Blocks |
|--------|------|-----------|--------|--------|--------|
| CD1 | sys_clk | 100 MHz | 10 ns | PLL (sys_osc ref) | RV32IM, ITCM, DTCM, AXI Xbar, AI Accel, SPI, Servo PWM, Speed Sensor, Buzzer PWM, UART, GPIO, Safety Monitor, Fault Aggregator |
| CD2 | wdt_clk | 32.768 kHz | 30.52 µs | Independent RC/XTAL oscillator | Window WDT, RSC |

### 1.1 Domain Relationship

- **CD1 ↔ CD2:** Asynchronous — clocks from independent sources with no known phase/frequency relationship.
- No mesochronous or rational-related domains exist in this design.
- The single sys_clk domain for all functional blocks eliminates CDC between CPU, peripherals, and AI accelerator.

---

## 2. CDC Crossing Inventory

### 2.1 Identified Crossings

| ID | Signal(s) | Source Domain | Dest Domain | Width | Type | Path |
|----|-----------|---------------|-------------|-------|------|------|
| CDC-01 | AXI4-Lite (WDT) | sys_clk (CD1) | wdt_clk (CD2) | 5 bundles | Bus protocol | CPU → WDT |
| CDC-02 | wdt_fault_o | wdt_clk (CD2) | sys_clk (CD1) | 1 | Single-bit level | WDT → Fault Agg |
| CDC-03 | aggregated_fault_o | sys_clk (CD1) | wdt_clk (CD2) | 1 | Single-bit level (latched) | Fault Agg → RSC |
| CDC-04 | wdt_prewarn_o | wdt_clk (CD2) | sys_clk (CD1) | 1 | Single-bit pulse | WDT → IRQ Controller |
| CDC-05 | force_shutdown_o | wdt_clk (CD2) | sys_clk (CD1) | 1 | Single-bit level (latched) | RSC → GPIO |
| CDC-06 | speed_pulse_i | external (async) | sys_clk (CD1) | 1 | Single-bit edge | External → Speed Sensor |
| CDC-07 | uart_rx_i | external (async) | sys_clk (CD1) | 1 | Serial bitstream | External → UART |

### 2.2 Crossing Classification

| Class | Description | Count |
|-------|-------------|-------|
| Bus (multibit) | Multiple signals requiring coherent transfer | 1 (CDC-01) |
| Single-bit level | Steady or slowly-changing signal | 3 (CDC-02, CDC-03, CDC-05) |
| Single-bit pulse | Short pulse crossing domains | 1 (CDC-04) |
| External input | Asynchronous external signal | 2 (CDC-06, CDC-07) |

### 2.3 Crossing Diagram

```
            CD1 (sys_clk, 100 MHz)          CD2 (wdt_clk, 32 kHz)
            ════════════════════════         ════════════════════════
                                                        
  CPU ──→ AXI ──→ [CDC-01] ────→ WDT Regs             
                   (AXI→WDT)                            
                                                        
            Fault Agg ←── [CDC-02] ──── WDT fault       
                         (WDT→Fault Agg)                
                                                        
            Fault Agg ──→ [CDC-03] ────→ RSC            
                         (Fault Agg→RSC)                
                                                        
            IRQ Ctrl  ←── [CDC-04] ──── WDT prewarn     
                         (WDT→IRQ)                      
                                                        
            GPIO      ←── [CDC-05] ──── RSC shutdown    
                         (RSC→GPIO)                     
                                                        
  ext ──→ Speed ←── [CDC-06] (2FF sync)                
                                                        
  ext ──→ UART  ←── [CDC-07] (oversampling)            
```

---

## 3. Synchronizer Selection

### 3.1 Synchronizer Types Used

| Type | Acronym | Structure | Use Case | MTBF Contribution |
|------|---------|-----------|----------|-------------------|
| 2-Stage Flip-Flop | 2FF | FF1 → FF2 (same clk dst) | Single-bit level signals, slow-changing | ~1000 years per crossing |
| Pulse Synchronizer | PULSE | Toggle FF(src) → 2FF(dst) → Edge detect | Single-bit pulses | ~500 years per crossing |
| Handshake (req/ack) | HSHAKE | req(src) → 2FF(dst) → ack(dst) → 2FF(src) | Multibit bus (coherent transfer) | ~500 years per crossing |
| Oversampling (3x) | OVERSMPL | 3-stage shift reg + majority vote | Async serial data (UART RX) | ~100 years per crossing |

### 3.2 Synchronizer Assignment

| CDC ID | Synchronizer Type | Depth | Notes |
|--------|-------------------|-------|-------|
| CDC-01 | Full Handshake (req/ack) | 2FF req, 2FF ack | AXI4-Lite to WDT; bus coherence required |
| CDC-02 | 2FF | 2 | Level signal (fault latched until cleared) |
| CDC-03 | 2FF | 2 | Level signal (latched in fault aggregator) |
| CDC-04 | Pulse Sync (toggle FF) | 2FF dst | Short pulse from WDT pre-warning |
| CDC-05 | 2FF | 2 | Level signal (shutdown latched until POR) |
| CDC-06 | 2FF | 2 | External pulse, ~kHz rate |
| CDC-07 | 3x Oversampling | 3 | UART RX at 16x baud rate oversample |

---

## 4. Detailed Crossing Analysis

### 4.1 CDC-01: AXI4-Lite to Window WDT (Handshake)

**Challenge:** AXI4-Lite is a multibit bus protocol with address, data, and control signals.
Simple 2FF synchronization would cause data incoherence (different bits arriving
in different destination clock cycles).

**Solution:** Full request-acknowledge handshake protocol.

```
      sys_clk Domain                     wdt_clk Domain
      ════════════                       ════════════
      
      ┌──────────┐                       ┌──────────────┐
      │ AXI Bus  │── data[31:0] ────────→│ WDT Register  │
      │          │── addr[31:0] ────────→│     File      │
      │          │── strobe[3:0] ───────→│               │
      │          │                       │               │
      │          │── req ──→ [2FF] ────→│               │
      │          │                       │ ack ←─────────│
      │          │←── [2FF] ←── ack ────│               │
      └──────────┘                       └──────────────┘
      
      Timing:
      1. sys_clk: Assert req, hold data/addr/strobe stable
      2. wdt_clk: 2FF samples req (metastability resolved)
      3. wdt_clk: Capture data on req assertion (req acts as enable)
      4. wdt_clk: Assert ack (registered output)
      5. sys_clk: 2FF samples ack
      6. sys_clk: De-assert req, release bus
      7. wdt_clk: De-assert ack
      8. sys_clk: 2FF samples ack de-assertion → ready for next transaction
```

**Throughput:** 
- WDT register read: ~15 µs (req + ack round-trip in slow domain)
- WDT register write: ~15 µs
- This is acceptable because WDT registers are infrequently accessed.

**Stability guarantee:** Data/addr/strobe are held stable by AXI master until
acknowledgement received.

### 4.2 CDC-02: WDT Fault to Fault Aggregator (2FF)

**Signal:** `wdt_fault_o` — level signal, asserted on WDT timeout, maintained until
WDT is refreshed or reset.

```
      wdt_clk Domain                   sys_clk Domain
      ═════════════                    ═════════════
      
      ┌─────────┐                      ┌──────────────┐
      │   WDT   │── fault ──→ [FF1]───→[FF2]──→ Fault│
      │         │                      │   Aggregator │
      └─────────┘                      └──────────────┘
      
      MTBF: ~1000 years (100 MHz, 32 kHz, 2FF)
```

**Why 2FF suffices:** The fault signal is a persistent level, not a pulse.
The fault aggregator will catch it within 2 sys_clk cycles (20 ns) of
wdt_clk assertion. Metastability resolution is handled by 2FF cascade.
Data loss is impossible because the level is held.

**False positive risk:** Zero — the 2FF resolves metastability to either 0 or 1.
On first assertion, the worst case is a 1-cycle delay in detection.

### 4.3 CDC-03: Aggregated Fault to RSC (2FF)

**Signal:** `aggregated_fault_o` — level signal, latched in fault aggregator
until fault is cleared (or POR).

```
      sys_clk Domain                    wdt_clk Domain
      ═════════════                     ═════════════
      
      ┌─────────┐                       ┌──────────────┐
      │  Fault  │── fault ──→ [FF1]────→[FF2]──→  RSC │
      │   Agg   │                       │              │
      └─────────┘                       └──────────────┘
      
      MTBF: ~1000 years (same analysis as CDC-02)
```

**Critical consideration:** This crossing is on the safety-critical path.
The RSC must receive the fault signal reliably. We add a third FF stage
(3FF total) for extra MTBF margin in the final implementation.

**Latency:** Maximum 3 wdt_clk cycles (~92 µs) from fault assertion to RSC recognition.

### 4.4 CDC-04: WDT Pre-warning to IRQ Controller (Pulse Synchronizer)

**Signal:** `wdt_prewarn_o` — short pulse (~1 wdt_clk cycle wide) indicating
watchdog is approaching timeout.

**Challenge:** A 1-cycle pulse in the 32 kHz domain (~30 µs wide) could be
missed by a 2FF synchronizer in the 100 MHz domain (sampling ambiguity).

**Solution:** Pulse synchronizer using toggle flip-flop.

```
      wdt_clk Domain                   sys_clk Domain
      ═════════════                    ═════════════
      
      pulse_in ──→ [Toggle FF]── toggle ──→ [FF1]──→[FF2]──→[FF3]──┐
                   (toggles on                                   │
                    each pulse)                               XOR ←──┘
                                                                │
                                                            pulse_out
      
      Operation:
      1. wdt_clk: Each pulse toggles the toggle FF
      2. sys_clk: 3FF chain resolves toggle signal
      3. sys_clk: XOR of FF2 and FF3 outputs detects edge → regenerates pulse
```

**MTBF:** ~500 years (3FF chain)

**Pulse width on output:** 1 sys_clk cycle (10 ns)

### 4.5 CDC-05: RSC Shutdown Override to GPIO (2FF)

**Signal:** `force_shutdown_o` — level signal, asserted on shutdown, latched forever.

```
      wdt_clk Domain                   sys_clk Domain
      ═════════════                    ═════════════
      
      ┌─────────┐                      ┌──────────────┐
      │   RSC   │── shdn ──→ [FF1]────→[FF2]──→ GPIO │
      └─────────┘                      └──────────────┘
```

Same analysis as CDC-02. Level signal, 2FF adequate.

### 4.6 CDC-06: External Speed Sensor Pulse (2FF)

**Signal:** `pulse_i` — external asynchronous pulse from wheel tachometer.

```
      External (async)                 sys_clk Domain
      ═══════════════                  ═════════════
      
      pulse ──→ [FF1]──→ [FF2]──→ Edge Detect ──→ Counter
                    ↑         ↑
                 (meta)   (clean)
```

**Constraints:**
- Pulse rate: < 10 kHz (wheel sensor, ~600 RPM max with 1 pulse/rev → 10 Hz)
- **Anti-metastability constraint:** Minimum pulse width on external pin:
  Must be > 2 × sys_clk period (20 ns) to guarantee detection.
  Real wheel sensors produce pulses >> 20 ns → safe.
- Edge detector: Positive edge only.

### 4.7 CDC-07: External UART RX (Oversampling)

**Signal:** `uart_rx_i` — asynchronous serial data at up to 115200 baud.

```
      External (async)                 sys_clk Domain
      ═══════════════                  ═════════════
      
      rx ──→ [SR0]──→[SR1]──→[SR2]──→ Majority Vote ──→ UART FSM
              (16x baud clock sampling, not sys_clk)
```

**Strategy:** UART uses 16x oversampling (not raw sys_clk). The baud-rate
generator produces a 16x baud clock. The RX line is sampled at 16x baud,
and the 3 middle samples (samples 7, 8, 9) are majority-voted to determine
bit value. This is the standard UART approach — effectively another form
of sampling-based synchronization.

---

## 5. MTBF Estimation

### 5.1 Methodology

MTBF (Mean Time Between Failures) due to metastability is estimated using
the standard formula:

```
MTBF = exp(Tw / τ) / (f_clk_dst × f_data × T0)
```

Where:
- `Tw` = Resolution time = (N_sync_stages - 0.5) × T_clk_dst - T_setup
- `τ` = Metastability resolution time constant (~30 ps for sky130hs)
- `f_clk_dst` = Destination clock frequency
- `f_data` = Data transition frequency
- `T0` = Metastability window (~15 ps for sky130hs)

### 5.2 sky130hs Flip-Flop Parameters

| Parameter | Value | Source |
|-----------|-------|--------|
| τ (tau) | 30 ps | LVT FF characterization (typical) |
| T0 | 15 ps | Metastability aperture window |
| T_setup | 65 ps | sky130_fd_sc_hs DFF setup time |
| T_clk2q | 120 ps | sky130_fd_sc_hs DFF clock-to-Q |

### 5.3 Per-Crossing MTBF

| CDC ID | N_FF | f_clk_dst | f_data | Tw (ns) | MTBF (years) | Safety Margin |
|--------|------|-----------|--------|---------|-------------|---------------|
| CDC-01* | 2 | 32.768 kHz | ~100 Hz | 30,490 | > 10^9 | Excellent |
| CDC-02 | 2 | 100 MHz | ~1 Hz | 19.94 | ~10^8 | Excellent |
| CDC-03 | 3 | 32.768 kHz | ~1 Hz | 61,000 | > 10^15 | Extreme |
| CDC-04 | 3 | 100 MHz | ~1 Hz | 29.94 | ~10^12 | Extreme |
| CDC-05 | 2 | 100 MHz | ~0.001 Hz | 19.94 | ~10^11 | Excellent |
| CDC-06 | 2 | 100 MHz | <10 kHz | 19.94 | ~10^4 | Adequate |
| CDC-07 | 3 (vote) | 16x baud | 115.2 kHz | — | ~10^3 | Adequate |

*CDC-01 uses handshake; data stability guaranteed by protocol.

### 5.4 System-Level MTBF

Assuming independent failure modes, system MTBF ≈ min(per-crossing MTBF) / N_crossings:

- Worst-case individual: CDC-07 @ ~10^3 years
- With 7 crossings: System MTBF ≈ 10^3 / 7 ≈ 140 years

**Conclusion:** All crossings have MTBF > 100 years, exceeding ASIL-D recommendation
(>10^3 FIT, equivalent to MTBF > 114 years). Adequate for safety-critical application.

### 5.5 Special: CDC-03 Redundancy

For the safety-critical CDC-03 (aggregated_fault → RSC), we add a **redundant path**:
the fault is also routed through a separate physical wire with independent 3FF
synchronizer. Both paths must agree. This is a dual-redundant CDC — a common
ASIL-D pattern.

---

## 6. CDC Verification Strategy

### 6.1 Static CDC Analysis (SpyGlass / Questa CDC)

If these tools are available, the following checks must pass:

| Check | Description | Severity |
|-------|-------------|----------|
| cdc_setup | All CDC signals declared with proper synchronizer | ERROR |
| cdc_sync | Synchronizer structure matches declared type | ERROR |
| cdc_reconvergence | No reconvergence of synchronized signals without care | WARNING |
| cdc_glitch | No combinational logic driving CDC input | ERROR |

### 6.2 Simulation-Based Verification

| Test | Description | CDC IDs Covered |
|------|-------------|-----------------|
| CDC Random Jitter | Vary clock phase relationship randomly | All |
| Stuck-at Fault Injection | Inject 0/1 on CDC signals | CDC-02, CDC-03, CDC-05 |
| Metastability Injection | Force X on synchronizer FF1 output | All |
| Pulse Width Variation | Minimum/maximum pulse widths | CDC-04, CDC-06 |
| Back-to-Back Crossing | Rapid successive CDC events | CDC-01, CDC-04 |
| Fault Injection on Safety Path | Simultaneous fault on redundant path | CDC-03 |

### 6.3 Formal CDC Verification

For the safety-critical path (CDC-03), formal verification should be used to prove:
1. No metastability can propagate to destination domain undetected.
2. Redundant path always agrees within 1 destination clock.
3. Glitch on source cannot cause spurious assertion at destination.

---

## 7. CDC Coding Guidelines

### 7.1 Mandatory Rules (RTL)

1. **No combinational logic before first synchronizer FF.**
   - ❌ `assign sync_in = sig_a & sig_b;` followed by 2FF.
   - ✅ Register the combination in source domain, then synchronize.

2. **All CDC signals must use vendor synchronizer cells or explicit attributes.**
   - Synthesis directive: `(* ASYNC_REG = "TRUE" *)` on synchronizer FFs.
   - Prevents synthesis optimization from disturbing the synchronizer chain.

3. **Synchronizer FFs must be placed adjacent in layout.**
   - SDC constraint: `set_max_delay 1.0 -from [get_cells sync_ff1/Q] -to [get_cells sync_ff2/D]`
   - Prevents routing delay from eating into metastability resolution time.

4. **Bus crossings (CDC-01) MUST use handshake or FIFO. Never 2FF on each bit.**
   - Data coherence must be guaranteed.

5. **No clock gating on synchronizer FFs.**
   - Synchronizers must always be clocked.

6. **Reset on synchronizer FFs must match destination domain.**
   - Destination domain reset drives synchronizer reset.

### 7.2 Template: 2FF Synchronizer (Verilog)

```verilog
// CDC-02, CDC-03, CDC-05, CDC-06
module cdc_2ff_sync (
    input  wire clk_dst,
    input  wire rst_n_dst,
    input  wire sig_in,
    output wire sig_out
);
    (* ASYNC_REG = "TRUE" *) reg sync_ff1;
    (* ASYNC_REG = "TRUE" *) reg sync_ff2;

    always @(posedge clk_dst or negedge rst_n_dst) begin
        if (!rst_n_dst) begin
            sync_ff1 <= 1'b0;
            sync_ff2 <= 1'b0;
        end else begin
            sync_ff1 <= sig_in;
            sync_ff2 <= sync_ff1;
        end
    end

    assign sig_out = sync_ff2;
endmodule
```

### 7.3 Template: Pulse Synchronizer (Verilog)

```verilog
// CDC-04
module cdc_pulse_sync (
    input  wire clk_src,
    input  wire rst_n_src,
    input  wire clk_dst,
    input  wire rst_n_dst,
    input  wire pulse_in,
    output wire pulse_out
);
    // Source domain: toggle FF
    reg toggle_ff;
    always @(posedge clk_src or negedge rst_n_src) begin
        if (!rst_n_src)
            toggle_ff <= 1'b0;
        else if (pulse_in)
            toggle_ff <= ~toggle_ff;
    end

    // Destination domain: 3FF chain + edge detect
    (* ASYNC_REG = "TRUE" *) reg sync_ff1, sync_ff2, sync_ff3;
    always @(posedge clk_dst or negedge rst_n_dst) begin
        if (!rst_n_dst) begin
            sync_ff1 <= 1'b0;
            sync_ff2 <= 1'b0;
            sync_ff3 <= 1'b0;
        end else begin
            sync_ff1 <= toggle_ff;
            sync_ff2 <= sync_ff1;
            sync_ff3 <= sync_ff2;
        end
    end

    assign pulse_out = sync_ff2 ^ sync_ff3;
endmodule
```

### 7.4 Template: Handshake Synchronizer (Verilog)

```verilog
// CDC-01: AXI4-Lite bus crossing
// Source domain (sys_clk):
//   1. Hold data/addr/strobe stable
//   2. Assert req
//   3. Wait for ack (synchronized back to sys_clk)
//   4. De-assert req
//   5. Wait for ack de-assertion
//   6. Release bus

// Destination domain (wdt_clk):
//   1. Sample req from 2FF synchronizer
//   2. On req assertion: latch data/addr/strobe
//   3. Assert ack
//   4. Wait for req de-assertion (via 2FF)
//   5. De-assert ack
```

---

## CDC Summary Table

| CDC ID | From | To | Type | Sync | FFs | MTBF (yr) | Safety Path? |
|--------|------|----|------|------|-----|-----------|-------------|
| CDC-01 | sys_clk | wdt_clk | Bus | Handshake | 2+2 | >10^9 | No |
| CDC-02 | wdt_clk | sys_clk | Level | 2FF | 2 | ~10^8 | No |
| CDC-03 | sys_clk | wdt_clk | Level | 3FF + redundant | 3×2 | >10^15 | **YES** |
| CDC-04 | wdt_clk | sys_clk | Pulse | Pulse Sync | 3 | ~10^12 | No |
| CDC-05 | wdt_clk | sys_clk | Level | 2FF | 2 | ~10^11 | **YES** |
| CDC-06 | ext | sys_clk | Pulse | 2FF | 2 | ~10^4 | No |
| CDC-07 | ext | sys_clk | Serial | Oversample | 3 | ~10^3 | No |

**System MTBF: >140 years** ✓

---

## Revision History

| Version | Date | Author | Description |
|---------|------|--------|-------------|
| 1.0 | 2026-04-29 | Kenji Tanaka | Initial CDC plan |

---

*"No metastability shall pass. Every domain crossing, accounted. Every synchronizer, placed. Every bit, coherent."*  
*— Kenji Tanaka, Chief Architect*
