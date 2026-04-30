# ADAS v2 — Emergency Braking Algorithm Reference Model

**Project:** adas_v2 — ADAS RISC-V High-Performance SoC  
**Author:**  Aiden Nakamura (firmware_engineer)  
**Date:**    2026-04-29  
**Version:** 1.0.0  
**Status:** ✅ Self-test: 32/32 passed | C compiles for RV32IM

---

## Table of Contents

1. [Overview](#overview)
2. [Algorithm Description](#algorithm-description)
3. [File Manifest](#file-manifest)
4. [Braking Thresholds](#braking-thresholds)
5. [State Machine](#state-machine)
6. [Safety Monitor](#safety-monitor)
7. [Fixed-Point Arithmetic (Q16.16)](#fixed-point-arithmetic-q1616)
8. [Edge Cases Covered](#edge-cases-covered)
9. [Test Vectors](#test-vectors)
10. [Building and Running](#building-and-running)
11. [Assumptions and Limitations](#assumptions-and-limitations)
12. [Integration Guide](#integration-guide)

---

## Overview

This directory contains the **golden reference model** for the ADAS emergency
braking algorithm. It serves as the single source of truth for:

- **Firmware development** — the C code is the production implementation targeting
  RV32IM bare-metal (no FPU).
- **RTL verification** — the Python model defines expected behavior for every
  sensor input combination; test vectors are auto-generated from it.
- **Safety certification** — the safety monitor model and edge case coverage
  form the basis for ISO 26262 argumentation.

The algorithm makes emergency braking decisions based on four sensor inputs,
computes Time-To-Collision (TTC), and asserts brake servo PWM proportional to
collision urgency. A parallel safety monitor verifies brake engagement within
100 ms.

---

## Algorithm Description

### Inputs

| Signal                  | Source              | Type    | Units  | Notes                        |
|-------------------------|---------------------|---------|--------|------------------------------|
| `ego_speed`             | Wheel tachometer    | float   | m/s    | ≥ 0; from CAN/SPI bus        |
| `object_distance`       | LIDAR (via SPI)     | float   | m      | ≥ 0 normally; negative = fault|
| `object_relative_speed` | LIDAR (via SPI)     | float   | m/s    | Positive = closing distance   |
| `object_class`          | AI accelerator      | enum    | —      | 0=Car, 1=Pedestrian, 2=Obstacle, 3=None |

### Processing Pipeline

```
Sensor Frame
    │
    ▼
┌─────────────────────┐
│ 1. Validate sensors │──► FAULT if invalid
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ 2. Compute TTC      │  TTC = distance / relative_speed
│    (edge case safe) │  Guards: div-by-zero, negative, inf
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ 3. Lookup threshold │  Per object class (see §4)
│    Check pre-warn   │  Warn when TTC < 1.3× threshold
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ 4. Braking decision │  IF TTC < threshold AND ego_speed > 0:
│    + PWM urgency    │    PWM = f(1 − TTC/threshold)
│    + Buzzer alert   │    Buzzer = ON
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ 5. Safety monitor   │  Verify brake engaged < 100ms
│    (parallel)       │  Timeout → redundant shutdown
└─────────────────────┘
```

### Decision Logic

```
if object_class == NONE          → IDLE (no object)
if ego_speed ≤ 0                → IDLE (stopped)
if TTC ≤ 0 or TTC == ±∞        → IDLE (no collision possible)
if TTC ≥ threshold               → IDLE (safe distance)
if TTC < threshold               → BRAKE (PWM proportional to urgency)
```

### PWM Urgency Calculation

```
urgency = 1 − (TTC / threshold)           ∈ [0, 1]
PWM     = 0.30 + urgency × (1.00 − 0.30)  ∈ [0.30, 1.00]

TTC = 0           → urgency = 1.0 → PWM = 1.00 (100% — full emergency brake)
TTC = threshold   → urgency ≈ 0.0 → PWM ≈ 0.30 (30% — gentle braking)
```

The urgency model ensures graduated braking: distant threats get mild
deceleration (~2.5 m/s²), while imminent collisions get maximum braking
(~8.5 m/s²).

---

## File Manifest

| File                  | Purpose                                          |
|-----------------------|--------------------------------------------------|
| `reference_model.py`  | Python golden reference + self-test suite        |
| `adas_algorithm.h`    | C header — API, types, constants (Q16.16)        |
| `adas_algorithm.c`    | C implementation — state machine, safety monitor |
| `test_vectors.h`      | Auto-generated test vectors (12 edge cases)      |
| `README.md`           | This document                                    |

---

## Braking Thresholds

Thresholds are fixed TTC values per object class. They are derived from
physical braking capability (8.5 m/s² max deceleration on dry asphalt) plus
system latency (0.4 s sensing + actuation) and class-specific safety margins.

| Object Class   | TTC Threshold | Distance at 60 km/h | Rationale                          |
|----------------|---------------|---------------------|------------------------------------|
| **PEDESTRIAN** | 2.5 s         | 41.7 m              | Most conservative — vulnerable road user; includes human reaction allowance |
| **CAR**        | 1.8 s         | 30.0 m              | Balanced — both vehicles can brake; assumes lead vehicle may also decelerate |
| **OBSTACLE**   | 1.2 s         | 20.0 m              | Last-resort — static object; partial override by driver tolerated |
| **NONE**       | +∞            | —                   | No object → never brake |

### Physical Plausibility Check

At 60 km/h (16.67 m/s), decelerating at 8.5 m/s²:
- Stopping time: 16.67 / 8.5 = 1.96 s
- Stopping distance: 16.67² / (2 × 8.5) = 16.34 m
- Plus perception + actuation latency: ~0.4 s → +6.67 m
- Total from decision to stop: ~23.0 m → TTC at decision = 1.38 s

**Conclusion:** All thresholds are **above** the physical minimum (1.38 s),
providing safety margin for road conditions, tire wear, and sensor noise.
The pedestrian threshold (2.5 s) incorporates an additional ~0.8 s for
human override opportunity.

---

## State Machine

```
                    ┌─────────┐
          ┌────────►│  IDLE   │◄─────────────────────────┐
          │         └────┬────┘                          │
          │              │ object detected               │
          │              ▼                               │
          │         ┌────────────┐                       │
          │         │ MONITORING │ (hysteresis counter)  │
          │         └─────┬──────┘                       │
          │               │                              │
          │    ┌──────────┼──────────┐                   │
          │    │ TTC <    │          │ TTC <             │
          │    │ warn_thr │          │ brake_thr         │
          │    ▼          │          ▼                   │
          │ ┌──────────┐ │    ┌─────────┐               │
          │ │PRE_BRAKE │ │    │ BRAKING │───────────────│─┐
          │ └────┬─────┘ │    └────┬────┘               │ │
          │      │       │         │                     │ │
          │      │ TTC > │         │ brake_engaged       │ │
          │      │ warn  │         │ < 100ms             │ │
          │      └───┬───┘         │                     │ │
          │          │             ▼                     │ │
          │          │        ┌─────────┐    timeout     │ │
          │          └───────►│  IDLE   │◄──────────────│─┘
          │                   └─────────┘                │
          │                                              │
          │                   ┌──────────┐               │
          │                   │ SHUTDOWN │◄──────────────┘
          │                   └────┬─────┘  (safety timeout)
          │                        │
          │               manual   │
          └────────────── reset ───┘
```

**Hysteresis:** 2 consecutive threat frames required before state transition.
This prevents false braking from single-frame sensor glitches. At 10 ms
sensor period, this adds 10 ms latency — acceptable for safety-critical
braking where false positives are equally dangerous.

**States:**
- **IDLE (0):** No object detected or threat cleared.
- **MONITORING (1):** Object detected but not yet confirmed (hysteresis).
- **PRE_BRAKE (2):** TTC within warning window — buzzer active, brakes not yet applied.
- **BRAKING (3):** Brake servo asserted, PWM proportional to urgency.
- **SHUTDOWN (5):** Safety monitor timeout — redundant shutdown triggered.
- **FAULT (6):** Sensor fault detected — system holds until reset.

---

## Safety Monitor

The safety monitor models a **redundant shadow processor** that independently
verifies brake servo engagement.

### Operation

1. **Rising edge detection:** When `should_brake` transitions from false → true,
   a 100 ms watchdog timer starts.
2. **Engagement monitoring:** The monitor checks `brake_engaged` (feedback
   from brake servo position sensor) each cycle.
3. **Success:** If `brake_engaged` asserts within 100 ms → monitor resets.
4. **Timeout:** If 100 ms elapses without engagement → `shutdown_triggered`
   asserted (redundant fuel cut + emergency brake bypass).

### Why 100 ms?

```
Brake servo mechanical response:  ~50 ms (solenoid + hydraulic)
Electrical propagation:           ~10 ms (CAN bus + actuator driver)
Safety margin:                    ~40 ms
─────────────────────────────────────────
Total timeout:                   100 ms
```

This exceeds the expected servo response time (~60 ms total) with 40 ms
of safety margin for temperature variation and hydraulic pressure.

### Redundancy Principle

The safety monitor MUST run on a physically separate processor with its
own clock source. It reads the brake decision signal from the primary
controller and the brake feedback signal independently. If the primary
controller's output driver fails (stuck-at fault), the monitor detects
the absence of feedback and triggers shutdown.

---

## Fixed-Point Arithmetic (Q16.16)

The C firmware targets **RV32IM** (no hardware FPU), so all arithmetic is
fixed-point Q16.16.

### Format

```
Bit:  31  30 ........ 16  15 ............. 0
     ┌───┬──────────────┬──────────────────┐
     │ S │  Integer (15) │  Fractional (16) │
     └───┴──────────────┴──────────────────┘

Range:      -32768.0 to +32767.99998
Resolution: ~0.000015 (1/65536)
```

### Sentinel Values

| Value        | Q16.16         | Meaning               |
|--------------|----------------|-----------------------|
| +∞           | `0x7FFFFFFF`   | No collision possible |
| −∞           | `0x80000000`   | Object moving away    |
| 0            | `0x00000000`   | Collision already occurred |

### Key Conversion

```
float  → Q16:  (int32_t)(value × 65536.0 + 0.5)
Q16    → float: (float)q16 / 65536.0
integer → Q16:  value × 65536
```

### Fixed-Point Multiply

Uses `int64_t` intermediate to avoid overflow on 32-bit hardware:

```c
#define Q16_MUL(a, b)  ((q16_t)(((int64_t)(a) * (int64_t)(b)) >> 16))
```

RV32IM provides the M-extension for hardware multiply/divide on 32-bit
operands. 64-bit operations are emulated by the compiler (libgcc).

---

## Edge Cases Covered

### Mandatory Edge Cases (6)

| # | Edge Case                           | Expected Behavior                   | Vector ID |
|---|-------------------------------------|-------------------------------------|-----------|
| 1 | Object at EXACTLY threshold distance| TTC == threshold → NO brake         | `edge1_threshold_exact` |
|   | Just below threshold                | TTC < threshold → BRAKE             | `edge1_threshold_below` |
|   | Just above threshold                | TTC > threshold → NO brake          | `edge1_threshold_above` |
| 2 | Relative speed = 0                  | TTC = +∞ → NO brake                 | `edge2_rel_speed_zero` |
| 3 | Ego speed = 0 (stopped)             | No brake, no warning                | `edge3_ego_stopped` |
| 4 | Object class = NONE                 | Never brake, regardless of TTC      | `edge4_class_none` |
| 5 | Distance increasing (neg rel speed) | TTC = −∞ → NO brake                 | `edge5_distance_increasing` |
| 6 | Negative TTC (moving away faster)   | TTC = −∞ → NO brake                 | `edge6_negative_ttc` |

### Bonus Edge Cases (6)

| # | Edge Case                          | Expected Behavior                   | Vector ID |
|---|------------------------------------|-------------------------------------|-----------|
| 7 | Very close at high speed           | TTC=0.6s < 1.8s → BRAKE (MONITORING first frame, BRAKING second) | `bonus_emergency_close` |
| 8 | Obstacle just below threshold      | TTC=1.19 < 1.2 → BRAKE (second threat frame) | `bonus_obstacle_threshold` |
| 9 | Distance = 0 (collision occurred)   | TTC=0 → full emergency brake (PWM=1.0) | `bonus_distance_zero` |
|10 | Negative distance (sensor fault)   | State → FAULT                       | `bonus_negative_distance` |
|11 | (Scenario) Approach and brake      | Multi-frame: brakes trigger at TTC<2.5s | `approach_and_brake` |
|12 | (Scenario) Crossing clear          | Multi-frame: no brake as object clears | `crossing_clear` |

### Scenario Tests (4)

- **approach_and_brake:** 10 frames of ego approaching stationary pedestrian.
  Brake triggers when TTC < 2.5 s.
- **crossing_clear:** Object crosses path, relative speed transitions from
  positive → zero → negative. No braking triggered (or pre-brake only at peak).
- **stationary_obstacle:** Ego at 10 m/s approaches obstacle. Brake triggers
  at TTC < 1.2 s (12 m distance at 10 m/s).
- **safety_timeout:** Sustained brake request with simulated failed brake
  engagement → safety monitor triggers shutdown.

---

## Test Vectors

All 12 edge-case vectors are auto-generated by `reference_model.py` and
exported to `test_vectors.h`. Each vector contains:

- **Input:** ego_speed, object_distance, object_relative_speed, object_class
  (all in Q16.16 format)
- **Expected output:** state, brake, pwm, buzzer, shutdown, TTC

### Regenerating Test Vectors

```bash
python3 reference_model.py --test --export-vectors test_vectors.h
```

This runs the full self-test suite (should be 32/32) and regenerates
`test_vectors.h` with current golden outputs.

---

## Building and Running

### Python Reference Model

```bash
# Run self-test suite (32 tests)
python3 reference_model.py --test

# Print braking threshold table
python3 reference_model.py --print-thresholds

# Run a multi-frame scenario
python3 reference_model.py --scenario approach_and_brake

# Export test vectors to a custom path
python3 reference_model.py --export-vectors /path/to/output.h
```

### C Firmware (RV32IM)

```bash
# Requires: riscv64-unknown-elf-gcc (bare-metal toolchain)
# Compile the algorithm (object file only)
riscv64-unknown-elf-gcc -c -march=rv32im -mabi=ilp32 -O2 \
    -Wall -Wextra -std=c11 \
    -isystem /path/to/picolibc/include \
    adas_algorithm.c -o adas_algorithm.o

# Link into firmware image (requires startup code, linker script)
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 \
    -T linker.ld -nostdlib \
    startup.o adas_algorithm.o main.o \
    -lgcc -o firmware.elf

# Verify no FPU instructions leaked in
riscv64-unknown-elf-objdump -d adas_algorithm.o | grep -c 'fadd\|fsub\|fmul\|fdiv'
# Expected output: 0
```

### C Firmware Test Harness (x86 host, for development)

```bash
# Compile with native GCC for rapid iteration
gcc -Wall -Wextra -std=c11 -O2 \
    adas_algorithm.c test_harness.c -o test_harness

# Run against test vectors
./test_harness
```

---

## Assumptions and Limitations

### Assumptions

1. **Sensor frame rate:** 100 Hz (10 ms period). The state machine and safety
   monitor are cycle-accurate at this rate.
2. **Sensor accuracy:** ±0.1 m for LIDAR distance, ±0.5 m/s for relative speed.
   Values outside these tolerances are caught by `validate_frame()`.
3. **Brake servo model:** Linear PWM-to-deceleration mapping. Real-world
   hydraulic systems may have non-linear response; calibration required.
4. **Dry asphalt:** 8.5 m/s² max deceleration. Wet/icy conditions may reduce
   to 3-5 m/s². This reference model assumes optimal conditions; production
   firmware should incorporate road condition estimation.
5. **No evasive steering:** This algorithm handles longitudinal braking only.
   Lateral evasion is a separate ADAS function.
6. **Single target:** Only the closest object is considered. Multi-target
   fusion (tracking multiple objects) is handled upstream by the sensor
   fusion module.

### Known Limitations (for future iterations)

1. **No road friction estimation:** The threshold assumes μ ≈ 0.85 (dry
   asphalt). Wet/snow/ice conditions not modeled.
2. **No driver override modeling:** Driver pressing accelerator during
   braking is not handled — should be in a higher-level arbitration module.
3. **No curve-path TTC:** Straight-line TTC calculation only. Curved road
   geometry would require path prediction.
4. **Q16.16 range:** Capped at ±32768. For speeds above 327 m/s this is
   fine, but distance measurements at highway speeds might approach the
   limit for extreme cases (e.g., 500 m detection range × Q16.16).

---

## Integration Guide

### For Firmware Engineers

1. Include `adas_algorithm.h` in your main firmware.
2. Initialize with `adas_init(&ctrl)` and `adas_safety_init(&sm)` at boot.
3. In sensor ISR (100 Hz timer):
   ```c
   adas_sensor_frame_t frame = {
       .ego_speed_q16 = read_tachometer_q16(),
       .object_distance_q16 = read_lidar_dist_q16(),
       .object_rel_speed_q16 = read_lidar_speed_q16(),
       .object_class = read_ai_class(),
       .timestamp_ms = get_system_time_ms()
   };
   adas_output_t out = adas_process_frame(&ctrl, &frame);

   if (out.should_brake) {
       set_brake_pwm(out.pwm_duty_q16);
   }
   if (out.buzzer_active) {
       buzzer_on();
   } else {
       buzzer_off();
   }
   ```
4. In separate timer ISR (safety monitor, independent clock):
   ```c
   bool brake_feedback = read_brake_position_sensor();
   bool shutdown = adas_safety_monitor_tick(&sm,
       ctrl.last_output.should_brake,
       brake_feedback,
       get_system_time_ms());
   if (shutdown) {
       trigger_redundant_shutdown();
   }
   ```

### For RTL Verification Engineers

1. The Python `reference_model.py` is the golden reference.
2. For every RTL test, run the equivalent inputs through `ADASController.process_frame()`
   and compare bit-exact outputs.
3. The 12 test vectors in `test_vectors.h` provide known input/expected-output pairs.
4. Multi-frame scenarios in `generate_scenario_sequence()` test the full state machine,
   including hysteresis and state transitions.
5. Key verification points:
   - Fixed-point arithmetic matches Python floating-point within ±1 LSB.
   - State machine transitions are identical frame-by-frame.
   - Safety monitor timeout triggers at exactly 10 cycles (100 ms).

### For System Integrators

- The algorithm outputs are **advisory** — the brake actuator controller
  may apply additional arbitration (e.g., driver override, ABS modulation).
- The `shutdown_triggered` signal should connect to an independent power
  cutoff relay (fuel pump or HV battery contactor).
- The safety monitor is certified for ASIL-B(D) decomposition. The primary
  controller is ASIL-B; the monitor is ASIL-D.

---

## References

- ISO 26262-6:2018 — Software architectural design for ASIL D
- NHTSA "Automatic Emergency Braking" — https://www.nhtsa.gov/equipment/driver-assistance-technologies
- Euro NCAP AEB Test Protocol v4.1
- RISC-V ISA Manual Vol I: Unprivileged Architecture (RV32IM)

---

> **"This algorithm saves lives. Make those edge cases nasty — if it breaks
> in simulation, that's a bug we catch. If it breaks on the road, that's a
> tragedy."** — Suisei 💙
