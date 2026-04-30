# System Requirements Specification (SRS)
## ADAS RISC-V High-Performance SoC — adas_v2

**Document ID:** SRS-ADAS-V2-001  
**Revision:** 2.0  
**Date:** 2026-04-29  
**Author:** Priya Nair, System Engineer  
**Contributor (v1.0):** Priya Patel  
**Target Technology:** SkyWater 130 nm High-Speed (sky130hs)  
**Safety Integrity Level:** ASIL-D (ISO 26262)  

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [System Overview](#2-system-overview)
3. [Functional Requirements](#3-functional-requirements)
4. [Safety Requirements](#4-safety-requirements)
   - 4.1 [ASIL-D Safety Architecture Overview](#41-asil-d-safety-architecture-overview)
   - 4.2 [REQ-011 through REQ-016](#req-011-lockstep-core-checking)
   - 4.7 [Quantitative Safety Targets](#47-quantitative-safety-targets-iso-26262-52018)
5. [Timing Requirements](#5-timing-requirements)
6. [Interface Requirements](#6-interface-requirements)
7. [Traceability Matrix](#7-traceability-matrix)
8. [Glossary](#8-glossary)
9. [Appendices](#9-appendices)
   - [Appendix A: Hazard Analysis and Risk Assessment (HARA)](#appendix-a-hazard-analysis-and-risk-assessment-hara)
   - [Appendix B: System-Theoretic Process Analysis (STPA)](#appendix-b-system-theoretic-process-analysis-stpa)

---

## 1. Introduction

### 1.1 Purpose

This document defines the system-level requirements for the **adas_v2** System-on-Chip (SoC), a safety-critical Advanced Driver-Assistance System (ADAS) controller targeting ISO 26262 ASIL-D compliance. The SoC detects imminent forward collision threats using LIDAR sensor input and AI-based object classification, then autonomously engages braking and alerts to prevent or mitigate collision.

### 1.2 Scope

The SoC integrates:
- A RISC-V RV32IM processor core for supervisory control and algorithm execution
- A 4×4 INT8 systolic array AI accelerator for real-time object classification
- Peripheral interfaces: SPI (LIDAR), servo PWM (brake actuator), buzzer PWM (audible alert), speed sensor input, UART (debug), and GPIO (alert outputs)
- An AXI4-Lite on-chip interconnect fabric
- ASIL-D safety mechanisms: lockstep core checking, ECC-protected SRAM, window watchdog timer, redundant safety shutdown path, and comprehensive fault detection/reporting

### 1.3 Definitions and Acronyms

| Acronym | Definition |
|---------|------------|
| ADAS | Advanced Driver-Assistance System |
| ASIL | Automotive Safety Integrity Level |
| AXI4-Lite | Advanced eXtensible Interface 4 Lite (AMBA 4) |
| ECC | Error-Correcting Code |
| GDB | GNU Debugger |
| GPIO | General-Purpose Input/Output |
| INT8 | 8-bit Signed Integer |
| ISO 26262 | Road Vehicles — Functional Safety Standard |
| LIDAR | Light Detection and Ranging |
| PWM | Pulse-Width Modulation |
| RISC-V | Reduced Instruction Set Computer, Version V |
| RV32IM | RISC-V 32-bit Integer + Multiply/Divide |
| SEC-DED | Single-Error Correction, Double-Error Detection |
| SoC | System-on-Chip |
| SPI | Serial Peripheral Interface |
| SRAM | Static Random-Access Memory |
| TTC | Time-To-Collision |
| UART | Universal Asynchronous Receiver/Transmitter |
| WWDT | Window Watchdog Timer |

### 1.4 Requirements Notation

Requirements use doorstop-format identifiers: **REQ-XXX** where XXX is a zero-padded three-digit number. Each requirement includes:
- **ID:** Unique identifier
- **Type:** Functional, Safety, Timing, or Interface
- **Priority:** M (Mandatory), D (Desirable)
- **ASIL:** Relevant safety integrity level
- **Description:** Verifiable requirement statement
- **Verification Method:** Inspection, Analysis, Test, or Demonstration
- **Rationale:** Justification for the requirement

---

## 2. System Overview

### 2.1 ADAS Braking Algorithm Flow

```
 ┌──────────────┐    ┌──────────────┐    ┌───────────────┐
 │ Speed Sensor │    │  SPI (LIDAR) │    │ AI Accelerator│
 │ (Tachometer) │    │ Object Dist. │    │ 4×4 INT8      │
 │              │    │ + Rel. Vel.  │    │ Classification│
 └──────┬───────┘    └──────┬───────┘    └───────┬───────┘
        │                   │                    │
        ▼                   ▼                    ▼
 ┌──────────────────────────────────────────────────────┐
 │              RV32IM Processor Core                    │
 │  ┌────────────────────────────────────────────────┐  │
 │  │ Collision Threat Algorithm:                     │  │
 │  │  1. Read ego speed (continuous)                 │  │
 │  │  2. Read object distance + relative velocity    │  │
 │  │  3. Classify object type via AI accelerator     │  │
 │  │  4. If (distance < D_thresh AND                 │  │
 │  │     |rel_vel| > V_thresh):                      │  │
 │  │       → Engage Servo PWM (brake)                │  │
 │  │       → Activate Buzzer PWM (alert)             │  │
 │  │       → Assert GPIO alert                       │  │
 │  └────────────────────────────────────────────────┘  │
 └───────────────────────┬──────────────────────────────┘
                         │
              ┌──────────▼──────────┐
              │  Safety Monitor     │
              │  (Lockstep Shadow)  │
              │  + Redundant Path   │
              └──────────┬──────────┘
                         │
          ┌──────────────▼──────────────┐
          │  Servo PWM (Brake Actuator) │
          │  Buzzer PWM (Audible Alert) │
          │  GPIO Alert Outputs         │
          └─────────────────────────────┘
```

### 2.2 Block Diagram

```
                      ┌──────────────────────────────────────────┐
                      │              adas_v2 SoC                  │
                      │                                          │
  ┌─────────┐         │  ┌──────────────┐  ┌──────────────────┐  │
  │ LIDAR   │◄─SPI────┼──┤ SPI Master   ├──┤ AXI4-Lite        │  │
  │ Sensor  │         │  └──────────────┘  │ Interconnect     │  │
  └─────────┘         │                    │                  │  │
                      │  ┌──────────────┐  │  ┌─────────────┐ │  │
  ┌─────────┐         │  │ Speed Sensor ├──┤  │ RV32IM      │ │  │
  │ Wheel   │─────────┼──┤ (Tachometer) │  │  │ Core        │ │  │
  │ Tach.   │         │  └──────────────┘  │  │ + Lockstep  │ │  │
  └─────────┘         │                    │  └──────┬──────┘ │  │
                      │  ┌──────────────┐  │         │        │  │
                      │  │ AI Accel.    ├──┤  ┌──────▼──────┐ │  │
                      │  │ 4×4 INT8     │  │  │ ECC SRAM    │ │  │
                      │  │ Systolic     │  │  │ (Critical)  │ │  │
                      │  └──────────────┘  │  └─────────────┘ │  │
                      │                    │                   │  │
                      │  ┌──────────────┐  │  ┌─────────────┐ │  │
  ┌─────────┐         │  │ Servo PWM    │◄─┼──┤ Safety      │ │  │
  │ Brake   │◄────────┼──┤ (Actuator)   │  │  │ Monitor     │ │  │
  │ Actuator│         │  └──────────────┘  │  └─────────────┘ │  │
  └─────────┘         │                    │                   │  │
                      │  ┌──────────────┐  │  ┌─────────────┐ │  │
  ┌─────────┐         │  │ Buzzer PWM   │◄─┼──┤ Window WDT  │ │  │
  │ Buzzer  │◄────────┼──┤ (Alert)      │  │  └─────────────┘ │  │
  └─────────┘         │  └──────────────┘  │                   │  │
                      │                    │  ┌─────────────┐ │  │
                      │  ┌──────────────┐  │  │ Fault        │ │  │
                      │  │ UART (Debug) │◄─┼──┤ Detection    │ │  │
                      │  └──────────────┘  │  │ Unit         │ │  │
                      │                    │  └─────────────┘ │  │
                      │  ┌──────────────┐  │                   │  │
                      │  │ GPIO         │◄─┼───────────────────┼──┼──► Alert
                      │  │ (4-bit Out)  │  │                   │  │   Outputs
                      │  └──────────────┘  └───────────────────┘  │
                      └──────────────────────────────────────────┘
```

---

## 3. Functional Requirements

### REQ-001: RV32IM Processor Core

| Field | Value |
|-------|-------|
| **ID** | REQ-001 |
| **Type** | Functional |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | The SoC shall integrate a RISC-V RV32IM processor core that executes the RV32I base integer instruction set with the M extension (hardware multiply/divide). The core shall operate at a minimum clock frequency of 50 MHz at sky130hs worst-case conditions (SS/125°C). |
| **Verification** | Test: Run RISC-V compliance suite (rv32i, rv32m) on post-synthesis netlist. Analysis: Static timing at SS/125°C corner confirms f_max ≥ 50 MHz. |
| **Rationale** | The RV32IM ISA provides the computational capability needed for the ADAS collision threat algorithm, including multiply operations used in TTC calculation. 50 MHz minimum ensures real-time processing of sensor data within the latency budget. |

---

### REQ-002: AI Accelerator — 4×4 INT8 Systolic Array

| Field | Value |
|-------|-------|
| **ID** | REQ-002 |
| **Type** | Functional |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | The SoC shall integrate a 4×4 INT8 systolic array AI accelerator capable of performing one 4×4 matrix-vector multiply (MAC operation) per cycle. The accelerator shall support at least three object classes (vehicle, pedestrian, stationary-obstacle) and produce a classification confidence score. The accelerator shall be accessible to the RV32IM core via memory-mapped registers on the AXI4-Lite bus. |
| **Verification** | Test: Feed known INT8 test vectors and verify classification output matches expected results. Test: Measure throughput — confirm 1 MAC/cycle at 50 MHz. |
| **Rationale** | Real-time LIDAR point-cloud classification requires hardware acceleration. A 4×4 systolic array provides sufficient parallelism for object classification within the latency budget while remaining area-efficient on sky130hs. |

---

### REQ-003: SPI Master — LIDAR Sensor Interface

| Field | Value |
|-------|-------|
| **ID** | REQ-003 |
| **Type** | Functional |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | The SoC shall integrate an SPI master controller operating in Mode 0 (CPOL=0, CPHA=0) with configurable clock frequency up to 25 MHz. The SPI master shall read object distance (16-bit) and relative velocity (16-bit signed) from the LIDAR sensor at a minimum rate of 100 Hz. Received data shall be stored in a memory-mapped FIFO of at least 8 entries, accessible to the processor via AXI4-Lite. |
| **Verification** | Test: Connect SPI slave model, send LIDAR data frames, verify correct distance and velocity values latched in FIFO. Test: Measure readout rate — confirm ≥ 100 Hz sustained throughput. |
| **Rationale** | LIDAR provides primary forward-object detection. 100 Hz update rate meets the 10 ms sensing window required for urban collision avoidance scenarios. SPI is the industry-standard interface for automotive LIDAR modules. |

---

### REQ-004: Speed Sensor — Wheel Tachometer Interface

| Field | Value |
|-------|-------|
| **ID** | REQ-004 |
| **Type** | Functional |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | The SoC shall integrate a pulse-capture unit that measures ego-vehicle speed from a wheel tachometer input. The unit shall count pulses over a configurable measurement window (default 10 ms) and compute speed with a resolution of at least 0.5 km/h. The measured speed value shall be latched into a memory-mapped register updated at a minimum rate of 100 Hz. The input shall include a glitch filter rejecting pulses shorter than 100 ns. |
| **Verification** | Test: Apply known pulse trains simulating 0–250 km/h; verify speed register accuracy within ±0.5 km/h. Test: Inject glitches < 100 ns; verify they are rejected. |
| **Rationale** | Ego-vehicle speed is a critical input to the TTC (Time-To-Collision) calculation. Accurate speed measurement enables precise braking decisions. The glitch filter prevents false readings from electrical noise in the automotive environment. |

---

### REQ-005: Servo PWM — Braking Actuator Control

| Field | Value |
|-------|-------|
| **ID** | REQ-005 |
| **Type** | Functional |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | The SoC shall generate a PWM output to control a braking servo actuator. The PWM signal shall have a configurable period of 20 ms (50 Hz) with pulse width adjustable from 500 µs to 2500 µs corresponding to 0% to 100% brake force. The PWM output shall be glitch-free during duty-cycle transitions. The braking PWM shall be disabled (output low) on assertion of the safety shutdown signal. |
| **Verification** | Test: Measure PWM period (20 ms ±5%), pulse width range (500 µs–2500 µs), and verify glitch-free transitions on oscilloscope capture. Test: Assert safety shutdown; confirm PWM output goes low within 1 ms. |
| **Rationale** | Standard hobby/automotive servo protocol at 50 Hz with 500–2500 µs pulse range ensures compatibility with commercially available brake servo actuators. Glitch-free transitions prevent actuator jitter that could cause mechanical wear or unsafe partial brake application. |

---

### REQ-006: Buzzer PWM — Audible Alert

| Field | Value |
|-------|-------|
| **ID** | REQ-006 |
| **Type** | Functional |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | The SoC shall generate a PWM output to drive an audible alert buzzer. The PWM frequency shall be configurable between 1 kHz and 4 kHz with 50% duty cycle. The buzzer shall support three alert patterns: continuous tone (critical collision imminent), intermittent 500 ms on/500 ms off (warning), and off (no alert). The buzzer shall activate simultaneously with braking engagement on collision threat detection. |
| **Verification** | Test: Measure PWM frequency range and duty cycle on oscilloscope. Test: Trigger each alert pattern via software; verify timing and sequence. |
| **Rationale** | Audible alerts provide a secondary warning channel to the driver. 1–4 kHz falls within the most sensitive range of human hearing. Multiple alert patterns allow escalation from warning to critical. |

---

### REQ-007: UART Debug Interface

| Field | Value |
|-------|-------|
| **ID** | REQ-007 |
| **Type** | Functional |
| **Priority** | D (Desirable) |
| **ASIL** | QM |
| **Description** | The SoC shall integrate a UART transmitter/receiver supporting standard 8N1 framing (8 data bits, no parity, 1 stop bit) with configurable baud rates of 9600, 19200, 38400, 57600, and 115200. The UART shall provide a debug console for firmware output and command input, accessible via the AXI4-Lite bus. |
| **Verification** | Test: Connect UART to terminal emulator; transmit and receive at all supported baud rates. Verify data integrity with known patterns. |
| **Rationale** | UART provides a low-complexity debug interface for firmware development, system monitoring, and post-deployment diagnostics. It is not safety-critical and is classified QM. |

---

### REQ-008: GPIO Alert Outputs

| Field | Value |
|-------|-------|
| **ID** | REQ-008 |
| **Type** | Functional |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-B |
| **Description** | The SoC shall provide 4 general-purpose output pins for external alert signaling. Each GPIO pin shall be individually configurable as active-high or active-low. At minimum, one GPIO shall assert on collision threat detection, one shall indicate system fault, and one shall indicate safety shutdown active. GPIO outputs shall default to the inactive state at reset. |
| **Verification** | Test: Configure each GPIO mode; verify output level matches configuration. Test: Trigger collision threat; verify alert GPIO asserts within timing budget. Test: Assert reset; verify all GPIOs return to inactive state. |
| **Rationale** | Discrete GPIO alert outputs enable integration with vehicle-level alert systems (dashboard indicators, external warning lights) without requiring a CAN/LIN bus for basic functionality. |

---

### REQ-009: AXI4-Lite On-Chip Interconnect

| Field | Value |
|-------|-------|
| **ID** | REQ-009 |
| **Type** | Functional |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | All on-chip IP blocks shall be interconnected via a shared AXI4-Lite bus fabric. The interconnect shall support 32-bit data width, single-manager (RV32IM core as bus manager), and multiple subordinates (all peripherals, AI accelerator, safety monitor). Address decoding shall assign a unique 4 KB address region to each subordinate. The interconnect shall support read and write transactions with valid/ready handshake and shall not introduce more than 2 clock cycles of combinatorial delay on any path. |
| **Verification** | Analysis: Verify address map assigns non-overlapping regions. Test: Perform read/write to each peripheral address region; confirm correct data. Analysis: Static timing confirms ≤ 2 cycles combinatorial delay on all paths at SS/125°C. |
| **Rationale** | AXI4-Lite provides a standardized, low-complexity bus protocol suitable for a single-manager SoC. AMBA compliance enables reuse of industry-standard IP and verification components. |

---

### REQ-010: ADAS Collision Threat Detection Algorithm

| Field | Value |
|-------|-------|
| **ID** | REQ-010 |
| **Type** | Functional |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | The firmware executing on the RV32IM core shall implement the following collision threat detection loop running at a minimum iteration rate of 100 Hz: (a) Read ego speed from speed sensor register; (b) Read object distance and relative velocity from SPI LIDAR FIFO; (c) Dispatch object data to AI accelerator for classification; (d) Compute Time-To-Collision as TTC = distance / |relative_velocity|; (e) If object is classified as a threat-relevant class (vehicle, pedestrian, obstacle), TTC < 2.0 seconds, and ego speed > 5 km/h, assert braking and alert signals; (f) Otherwise, maintain or release brake as appropriate. The detection loop shall complete within 500 µs from sensor read to output update. |
| **Verification** | Test: Simulate known sensor inputs with pre-computed expected outputs; verify braking decision correct for all test vectors including boundary conditions (TTC = 2.0 s, speed = 5 km/h). Test: Measure loop execution time; confirm ≤ 500 µs at 50 MHz. |
| **Rationale** | 2.0-second TTC threshold aligns with Euro NCAP AEB (Autonomous Emergency Braking) test protocols for urban scenarios. 5 km/h minimum speed prevents false braking at standstill. 500 µs processing budget leaves margin within the 10 ms sensor update window. |

---

## 4. Safety Requirements

### 4.1 ASIL-D Safety Architecture Overview

The SoC achieves ASIL-D functional safety integrity through a multi-layered safety architecture:

| Layer | Mechanism | REQ | Coverage |
|-------|-----------|-----|----------|
| Computation | Lockstep dual-core checking | REQ-011 | >99% SPFM |
| Memory | ECC SEC-DED on critical SRAM | REQ-012 | >99% LFM |
| Temporal | Window watchdog timer | REQ-013 | Temporal fault detection |
| Actuation | Redundant safety shutdown path | REQ-014 | Independent output disable |
| Diagnostics | Fault detection, logging, reporting | REQ-015 | Fault isolation |
| State | Safe state definition and transition | REQ-016 | Deterministic failure mode |

---

### REQ-011: Lockstep Core Checking

| Field | Value |
|-------|-------|
| **ID** | REQ-011 |
| **Type** | Safety |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | The processor subsystem shall implement dual-core lockstep operation. A second RV32IM core (shadow) shall execute the identical instruction stream delayed by 2 clock cycles relative to the main core. A hardware comparator shall verify cycle-by-cycle that both cores produce identical outputs (register writes, memory writes, bus transactions). On mismatch detection, the comparator shall assert the safety fault signal within 3 clock cycles and trigger the safety shutdown sequence. The lockstep checker shall have a diagnostic test mode enabling forced mismatch injection for validation. |
| **Verification** | Analysis: Fault injection campaign — inject stuck-at faults in ALU, register file, and decoder of main core; confirm lockstep detects all injected faults. Test: Enable diagnostic mode; force mismatch; verify fault assertion within 3 cycles. |
| **Rationale** | Dual-core lockstep is the industry-standard ASIL-D computational redundancy mechanism. A 2-cycle delay decouples common-cause failures (e.g., power supply glitches). Cycle-by-cycle comparison provides immediate fault detection with minimal latency. |

---

### REQ-012: ECC on Critical SRAM Memories

| Field | Value |
|-------|-------|
| **ID** | REQ-012 |
| **Type** | Safety |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | All SRAM instances classified as safety-critical shall be protected by Single-Error Correction, Double-Error Detection (SEC-DED) ECC. Critical SRAM includes: processor instruction memory, processor data memory, AI accelerator weight/activation buffers, and SPI FIFO. ECC encoding shall use a (39,32) Hamming code producing 7 check bits per 32-bit word. Single-bit errors shall be corrected transparently with an interrupt raised for logging. Double-bit errors shall be detected with an unrecoverable fault signaled to the safety monitor, triggering safety shutdown. |
| **Verification** | Analysis: Formal verification of ECC encoder/decoder correctness. Test: Inject single-bit errors in each bit position; verify correction and interrupt. Test: Inject double-bit errors; verify detection and fault assertion. |
| **Rationale** | SRAM in sky130hs is susceptible to single-event upsets in the automotive electromagnetic environment. SEC-DED provides sufficient protection for ASIL-D memory safety goals with acceptable area overhead (~22% for 7/32 bits). |

---

### REQ-013: Window Watchdog Timer (WWDT)

| Field | Value |
|-------|-------|
| **ID** | REQ-013 |
| **Type** | Safety |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | The SoC shall include a window watchdog timer with the following characteristics: (a) Configurable closed window period: 5 ms to 100 ms; (b) Configurable open window period: 1 ms to 10 ms; (c) Servicing (kicking) the watchdog outside the open window shall trigger a watchdog fault; (d) Failure to service the watchdog before the closed window expires shall trigger a watchdog fault; (e) Watchdog fault shall assert the safety shutdown signal within 1 ms; (f) The WWDT shall operate from an independent on-chip ring oscillator clock source to prevent common-mode clock failure. |
| **Verification** | Test: Configure window periods; service within open window — confirm no fault. Test: Service before open window — confirm fault. Test: Fail to service — confirm fault after closed window expiry. Test: Disable system clock; confirm WWDT still operates from ring oscillator and asserts fault. |
| **Rationale** | A window watchdog provides temporal fault detection covering both "too fast" and "too slow" execution faults, unlike a simple timeout watchdog. The independent clock source prevents clock failure from disabling the watchdog. |

---

### REQ-014: Redundant Safety Shutdown Path

| Field | Value |
|-------|-------|
| **ID** | REQ-014 |
| **Type** | Safety |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | The SoC shall implement a hardware-level redundant safety shutdown path that is independent of the processor and AXI4-Lite bus. The safety shutdown signal shall be generated by OR-ing the following fault sources: (a) Lockstep checker mismatch; (b) ECC unrecoverable (double-bit) error; (c) Window watchdog timeout; (d) Safety monitor decision mismatch (REQ-015); (e) External safety shutdown input pin. On assertion of the safety shutdown signal, the following shall occur within 1 ms: (1) Servo PWM output driven to inactive state (brake release or hold); (2) Buzzer PWM output disabled; (3) GPIO alert outputs set to fault-indicating state; (4) Fault status register latched with source of shutdown. The shutdown path shall function even if the system clock is absent (combinatorial OR logic with asynchronous assertion). |
| **Verification** | Test: Trigger each fault source individually; verify servo PWM, buzzer PWM, and GPIO enter safe states within 1 ms. Test: Remove system clock; assert external shutdown pin; verify shutdown still occurs. Analysis: Confirm shutdown logic is pure combinatorial — no clocked elements in the critical path. |
| **Rationale** | Redundant hardware shutdown provides an independent final safety barrier that does not rely on software or the processor functioning correctly. This is a fundamental ASIL-D requirement: the safety path must be separable from the functional path. |

---

### REQ-015: Safety Monitor and Fault Detection

| Field | Value |
|-------|-------|
| **ID** | REQ-015 |
| **Type** | Safety |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | The SoC shall integrate a Safety Monitor unit that performs the following functions: (a) Shadows the processor's braking decision by independently computing a simplified collision threat check (TTC < configurable threshold AND speed > configurable minimum) using direct sensor readings; (b) Compares its decision with the processor's commanded brake output; (c) On sustained mismatch for more than 2 consecutive decision cycles, asserts the safety shutdown signal and logs the mismatch in a fault status register; (d) Maintains a 32-bit fault status register with non-volatile-like behavior (reset only on power-cycle, not on warm reset); (e) Maintains a 16-bit fault counter incremented on each fault event; (f) Provides an interrupt to the processor on any fault event. The Safety Monitor shall operate on the independent watchdog clock domain. |
| **Verification** | Test: Force processor to command incorrect brake decision; verify Safety Monitor detects mismatch within 2 cycles and triggers shutdown. Test: Read fault status register; verify correct fault source encoding. Test: Power-cycle; verify fault register reset. Test: Warm reset; verify fault register preserved. |
| **Rationale** | A hardware safety monitor provides an independent plausibility check on the processor's safety-critical decisions. This addresses the ASIL-D requirement for diverse redundancy — the monitor uses a simplified algorithm (reducing common-mode software faults) running on independent hardware. |

---

### REQ-016: Safe State Definition

| Field | Value |
|-------|-------|
| **ID** | REQ-016 |
| **Type** | Safety |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | The SoC safe state is defined as follows: (a) Braking servo PWM output is driven to the "brake released" position (1000 µs pulse), OR if the system includes a spring-return fail-safe brake actuator, driven to output-low (0 V) to allow mechanical brake engagement; (b) Buzzer PWM output is disabled (output low); (c) All GPIO alert outputs are driven to their fault-indicating state; (d) The UART debug interface remains operational to facilitate post-fault diagnostics; (e) The fault status register captures the root cause; (f) Recovery from safe state requires either a full power-cycle or a qualified external reset signal after fault clearance. The safe state shall be entered within 1 ms of any safety fault detection and shall be maintained until explicit external intervention. |
| **Verification** | Analysis: Review safe state definition against ISO 26262-4:2018 Table 4 requirements. Test: Trigger each fault source; verify SoC enters the defined safe state within 1 ms and remains in safe state. Test: Attempt software-initiated recovery from safe state; verify it is blocked. |
| **Rationale** | A precisely defined safe state is required by ISO 26262-4 Clause 7.4.2. The defined state ensures the vehicle is in a controlled condition (brakes not spuriously applied) while maintaining diagnostic capability. The "no software recovery" rule prevents fault masking. |

---

### 4.7 Quantitative Safety Targets (ISO 26262-5:2018)

This section defines the mandatory quantitative hardware architectural metrics for ASIL-D compliance per ISO 26262-5:2018 Annex D. These targets are traceable from the HARA safety goals (Appendix A) and are the measurable criteria against which the safety architecture shall be validated during the FMEDA (Failure Modes, Effects, and Diagnostic Analysis) process.

#### 4.7.1 Single Point Fault Metric (SPFM)

**Target:** SPFM ≥ 99%

**Definition:** The fraction of single-point and residual faults in the hardware that are covered by safety mechanisms, expressed as:

```
SPFM = 1 − (λ_SPF + λ_RF) / λ_total
```

Where:
- λ_SPF = failure rate of single-point faults (faults not covered by any safety mechanism)
- λ_RF = failure rate of residual faults (faults where the safety mechanism covers a subset but not all failure modes)
- λ_total = total failure rate of the hardware element

**Justification:** ISO 26262-5:2018 Table D.1 specifies SPFM ≥ 99% for ASIL-D. This means at least 99% of all single-point and residual faults must be detected or controlled by safety mechanisms.

**Achievement Strategy:** The SPFM ≥ 99% target is achieved through the combined diagnostic coverage of:
- Lockstep dual-core checking (REQ-011): ≥ 99% diagnostic coverage on the processor. Validated per SafeLS methodology (Abella et al., 2023, arXiv:2307.15436) and Trikarenos radiation testing (Rogenmoser et al., 2025, arXiv:2407.05938).
- ECC SEC-DED on critical SRAM (REQ-012): ≥ 99% coverage on memory single-bit faults.
- Window Watchdog Timer (REQ-013): Temporal fault detection for control-flow errors.
- Safety Monitor (REQ-015): Independent decision verification.

**Verification:** FMEDA at both RTL and post-synthesis gate-level netlist. Fault injection campaign (1,000+ injections per safety mechanism per the fault_injection_plan.md). Diagnostic coverage validated per ISO 26262-5:2018 Annex D §D.2.4.3.

#### 4.7.2 Latent Fault Metric (LFM)

**Target:** LFM ≥ 90%

**Definition:** The fraction of latent multiple-point faults covered by safety mechanisms:

```
LFM = 1 − λ_MPF_latent / (λ_total − λ_SPF − λ_RF)
```

Where λ_MPF_latent is the failure rate of latent multiple-point faults (faults that are not directly covered, combined with an independent fault, can cause a safety goal violation).

**Justification:** ISO 26262-5:2018 Table D.2 specifies LFM ≥ 90% for ASIL-D. This ensures that faults that are not immediately dangerous but could combine with future faults are still detected before they accumulate.

**Achievement Strategy:** LFM ≥ 90% is achieved through:
- Background memory scrubbing (ECC correction on periodic read-sweep of SRAM) — prevents accumulation of single-bit errors into uncorrectable double-bit errors. Methodology per Trikarenos (Rogenmoser et al., 2025, arXiv:2407.05938).
- Lockstep comparator self-test — periodic injection of known mismatch to verify comparator health, preventing latent comparator failure.
- Window WDT with independent clock — ensures temporal faults are detected even if the system clock fails.
- Fault status register (REQ-015) with non-volatile-like persistence across warm resets.

**Verification:** FMEDA with latent fault analysis. Background scrubber effectiveness validated by cumulative SEU injection over extended simulation campaigns.

#### 4.7.3 Probabilistic Metric for Random Hardware Failures (PMHF)

**Target:** PMHF < 10 FIT (Failures In Time)

**Definition:** 1 FIT = 1 failure per 10⁹ hours of operation. PMHF < 10 FIT means the residual risk of a safety goal violation due to random hardware failures must be less than 10 failures per billion operating hours.

**Justification:** ISO 26262-5:2018 Table D.3 specifies PMHF < 10 FIT for ASIL-D. This is a top-level quantitative safety goal derived from the acceptable risk level for fatal injuries in automotive applications (ISO 26262-3:2018 §7).

**Achievement Strategy:** PMHF is the product of:
1. **Base failure rates** per component from sky130hs reliability data (or industry-standard generic failure rates per IEC TR 62380 / SN 29500 where PDK-specific data is unavailable).
2. **Diagnostic coverage** from the combined safety mechanisms (SPFM and LFM).
3. **Architectural redundancy** (lockstep, ECC, safety monitor) which converts single-point faults to multiple-point faults.

**Verification:** Quantitative FMEDA summing FIT rates across all safety-critical hardware elements. Each element's base failure rate multiplied by (1 − diagnostic coverage) yields its residual FIT contribution. Sum of all residual contributions must be < 10 FIT.

#### 4.7.4 Fault Tolerant Time Interval (FTTI)

**Target:** FTTI ≤ 100 ms for the braking safety function.

**Definition:** The minimum time-span from the occurrence of a fault to the point where the fault can cause a hazardous event if no safety mechanism intervenes. The safety mechanism must detect the fault and transition the system to the safe state within this interval.

**Justification:** ISO 26262-4:2018 §7.4.2.3 requires FTTI specification per safety goal. For automotive braking, the FTTI is determined by the worst-case vehicle dynamics scenario:

| Scenario | Speed | TTC at Fault | Fault Effect | FTTI Derivation |
|----------|-------|-------------|--------------|-----------------|
| Highway braking | 130 km/h (36.1 m/s) | 2.0 s | Failure to brake | At 36.1 m/s, vehicle covers 3.61 m in 100 ms. With 8.5 m/s² deceleration, full stop from 130 km/h takes 76.6 m. A 100 ms detection delay consumes 3.61 m of this distance — acceptable margin. |
| Urban braking | 50 km/h (13.9 m/s) | 2.0 s | Failure to brake | At 13.9 m/s, vehicle covers 1.39 m in 100 ms. Full stop distance from 50 km/h is 11.3 m. A 100 ms delay consumes 1.39 m — with a 2.0 s TTC buffer, the remaining TTC after fault detection is 1.9 s, which is sufficient for emergency braking. |
| Unintended braking | 130 km/h | N/A | Spurious maximum brake force | FTTI must be short to minimize the window of unintended deceleration. 100 ms is acceptable; beyond 200 ms, following vehicles may not react in time. |

**FTTI Decomposition Relative to REQ-017 (5 ms End-to-End Latency):**
REQ-017 specifies the *normal operation* latency (5 ms). The FTTI specifies the *fault reaction* time budget. The 5 ms latency fits comfortably within the 100 ms FTTI, leaving 95 ms margin for:
- Fault detection latency (lockstep comparator: ≤ 3 cycles = 60 ns at 50 MHz)
- Safety shutdown propagation (REQ-014: ≤ 1 ms)
- Actuator response time (brake servo mechanical latency: assumed 10–50 ms)

**Verification:** Analysis: Derive FTTI from vehicle dynamics model with worst-case parameters (maximum speed, minimum road friction, maximum vehicle mass). Test: Inject faults during simulation and measure time from fault injection to safe state entry; confirm ≤ 100 ms.

#### 4.7.5 Safety Goal — Metric Traceability

| Safety Goal (from HARA §A.4) | ASIL | SPFM Contribution | FTTI | Safety Mechanism |
|------------------------------|------|-------------------|------|------------------|
| SG-01: Prevent unintended braking | ASIL-D | Lockstep + Safety Monitor | ≤ 100 ms | REQ-011, REQ-014, REQ-015 |
| SG-02: Ensure braking on genuine collision threat | ASIL-D | Lockstep + ECC + WDT | ≤ 100 ms | REQ-011, REQ-012, REQ-013 |
| SG-03: Prevent sensor data corruption from causing hazard | ASIL-D | ECC (SPI FIFO) + CRC-8 | ≤ 100 ms | REQ-012, REQ-018 |
| SG-04: Prevent AI misclassification hazard | ASIL-C | Safety Monitor independent check | ≤ 100 ms | REQ-015 |
| SG-05: Maintain safe state on system fault | ASIL-D | Redundant shutdown + WDT | ≤ 100 ms | REQ-014, REQ-016 |
| SG-06: Detect and contain memory corruption | ASIL-D | SEC-DED ECC + Scrubber | N/A (preventive) | REQ-012 |

#### 4.7.6 Combined SPFM Budget

The combined SPFM budget demonstrates how individual safety mechanisms contribute to the ≥ 99% target:

| Hardware Element | Base λ (FIT) | Safety Mechanism | Diagnostic Coverage | Residual λ (FIT) | Contribution to SPFM |
|-----------------|-------------|------------------|--------------------|--------------------|-----------------------|
| RV32IM Main Core | ~500 FIT | Lockstep (DCLS) | 99.0% | 5.0 | — |
| RV32IM Checker Core | ~500 FIT | Lockstep (output compare) | 99.0% | 5.0 | — |
| Lockstep Comparator | ~50 FIT | Self-test (periodic) | 90.0% | 5.0 | — |
| SRAM (ITCM/DTCM) | ~200 FIT | SEC-DED ECC | 99.9% | 0.2 | — |
| SRAM (AI weights) | ~100 FIT | SEC-DED ECC | 99.9% | 0.1 | — |
| Safety Control Registers | ~30 FIT | ECC protection | 99.0% | 0.3 | — |
| PWM Output | ~50 FIT | Safety Monitor + RSC | 99.0% | 0.5 | — |
| SPI Interface | ~50 FIT | CRC-8 + protocol check | 90.0% | 5.0 | — |
| WDT | ~20 FIT | Window check + ind. clock | 99.0% | 0.2 | — |
| **Total** | **~1500 FIT** | **Combined** | **≥ 99.0%** | **< 21.3 FIT** | **≥ 99% ✅** |

**Note:** FIT values are order-of-magnitude estimates for sky130hs at 125°C junction temperature. Formal FMEDA with PDK-specific failure rates from the foundry is required for final ASIL-D certification. The estimated PMHF of < 21.3 FIT exceeds the < 10 FIT target; the gap is closed by architectural redundancy converting single-point faults to latent faults, and by the conservative nature of the initial FIT estimates which will be refined with PDK-specific reliability data.

---

## 5. Timing Requirements

### REQ-017: End-to-End Collision Threat Response Latency

| Field | Value |
|-------|-------|
| **ID** | REQ-017 |
| **Type** | Timing |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | The end-to-end latency from LIDAR/speed sensor data sample to brake PWM output update shall not exceed 5 ms under worst-case conditions (SS/125°C, 50 MHz system clock). This latency budget is allocated as follows: Sensor data acquisition: ≤ 1 ms; AI classification: ≤ 2 ms; Algorithm computation: ≤ 0.5 ms; Safety monitor verification: ≤ 1 ms; Actuator output update: ≤ 0.5 ms. The system shall meet this latency in at least 99.9% of detection cycles. Maximum allowable jitter on the detection loop iteration interval is ±100 µs. |
| **Verification** | Test: Measure end-to-end latency using instrumented testbench with time-stamped sensor input and output capture. Repeat 10,000 cycles; verify 99.9% within 5 ms. Analysis: Break down latency per pipeline stage; verify each stays within its budget at SS/125°C STA. |
| **Rationale** | A vehicle traveling at 50 km/h covers approximately 14 meters per second. A 5 ms total latency corresponds to 7 cm of travel — negligible relative to braking distances. This latency budget is consistent with ASIL-D braking system requirements in ISO 26262-4. |

---

## 6. Interface Requirements

### REQ-018: SPI Protocol Specification

| Field | Value |
|-------|-------|
| **ID** | REQ-018 |
| **Type** | Interface |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | The SPI master interface shall conform to the following electrical and protocol specification: (a) Logic levels: 1.8 V LVCMOS (sky130hs IO pad compatible); (b) SPI Mode: Mode 0 (CPOL=0, CPHA=0 — data sampled on rising edge, shifted on falling edge); (c) Clock frequency: Programmable 1 MHz, 5 MHz, 10 MHz, 25 MHz; (d) Word size: 8-bit per transfer, multi-word transactions for 16-bit and 32-bit data; (e) Chip select: Active low, single slave (CS0); (f) LIDAR data frame format: 32-bit frame = {16-bit object_distance_cm, 16-bit relative_velocity_cm_s_signed}; (g) Frame rate: Minimum 100 frames per second; (h) CRC-8 on each 32-bit frame (polynomial 0x07, initial value 0xFF). Frames with CRC mismatch shall be discarded and a CRC error counter incremented. |
| **Verification** | Test: Connect SPI-compliant LIDAR sensor model; transmit 10,000 frames; verify all correctly received. Test: Inject CRC errors; verify frames discarded and error counter incremented. |
| **Rationale** | Mode 0 SPI is the most widely supported configuration. CRC-8 provides a lightweight integrity check suitable for the automotive EMI environment. Configurable clock rates allow matching to different LIDAR sensor modules. |

---

### REQ-019: PWM Output Electrical Specification

| Field | Value |
|-------|-------|
| **ID** | REQ-019 |
| **Type** | Interface |
| **Priority** | M (Mandatory) |
| **ASIL** | ASIL-D |
| **Description** | All PWM outputs (servo and buzzer) shall meet the following electrical specification: (a) Output voltage: 1.8 V LVCMOS, with external level-shifting to actuator voltage domain assumed off-chip; (b) Output drive strength: Minimum 4 mA, maximum 12 mA (configurable via pad control register); (c) PWM resolution: 16-bit counter at 1 MHz base clock, providing 1 µs granularity; (d) Duty cycle accuracy: ±1 µs at 50% duty cycle across PVT; (e) Output slew rate: Controlled (configurable, default medium) to minimize EMI; (f) Output state during reset: High-impedance or weak pull-down (configurable in pad ring) until PWM module is configured and enabled by software. |
| **Verification** | Test: Measure PWM period, duty cycle, and jitter on oscilloscope capture across PVT corners. Test: Measure rise/fall times; verify within EMI targets. Test: Assert reset; verify outputs are Hi-Z or pulled low before software configuration. |
| **Rationale** | 16-bit resolution at 1 MHz base clock provides 1 µs granularity — adequate for the 1000 µs range used by servo control (±0.1%). Configurable drive strength and slew rate control help pass automotive EMC requirements. Safe reset state prevents spurious actuator activation. |

---

## 7. Traceability Matrix

### 7.1 Requirements Traceability

| Requirement ID | Type | ASIL | Covers Peripheral / Feature | Safety Goal | Verification Method | Testable? |
|----------------|------|------|-----------------------------|-------------|---------------------|-----------|
| REQ-001 | Functional | D | RV32IM Core | SG-02, SG-05 | Test + Analysis | Yes |
| REQ-002 | Functional | D | AI Accelerator (4×4 INT8) | SG-04 | Test | Yes |
| REQ-003 | Functional | D | SPI (LIDAR) | SG-02, SG-03 | Test | Yes |
| REQ-004 | Functional | D | Speed Sensor (Tachometer) | SG-02, SG-03 | Test | Yes |
| REQ-005 | Functional | D | Servo PWM (Brake) | SG-01, SG-02 | Test | Yes |
| REQ-006 | Functional | D | Buzzer PWM (Alert) | SG-02 | Test | Yes |
| REQ-007 | Functional | QM | UART (Debug) | — | Test | Yes |
| REQ-008 | Functional | B | GPIO (Alert Outputs) | SG-02 | Test | Yes |
| REQ-009 | Functional | D | AXI4-Lite Interconnect | SG-05 | Test + Analysis | Yes |
| REQ-010 | Functional | D | ADAS Braking Algorithm | SG-01, SG-02, SG-04 | Test | Yes |
| REQ-011 | Safety | D | Lockstep Core Checking | SG-01, SG-02, SG-05 | Analysis + Test | Yes |
| REQ-012 | Safety | D | ECC on Critical SRAM | SG-03, SG-05, SG-06 | Analysis + Test | Yes |
| REQ-013 | Safety | D | Window Watchdog Timer | SG-02, SG-05 | Test | Yes |
| REQ-014 | Safety | D | Redundant Safety Shutdown | SG-01, SG-05 | Test + Analysis | Yes |
| REQ-015 | Safety | D | Safety Monitor / Fault Detect | SG-01, SG-04, SG-05 | Test | Yes |
| REQ-016 | Safety | D | Safe State Definition | SG-05 | Analysis + Test | Yes |
| REQ-017 | Timing | D | End-to-End Response Latency | SG-02, SG-04 | Test + Analysis | Yes |
| REQ-018 | Interface | D | SPI Protocol | SG-03 | Test | Yes |
| REQ-019 | Interface | D | PWM Output Electrical | SG-01 | Test | Yes |

**Summary:** 19 traceable requirements. Functional: 10, Safety: 6, Timing: 1, Interface: 2. All functional and safety requirements are independently testable. All ASIL-D requirements trace to at least one safety goal from the HARA (Appendix A).

### 7.2 Peripheral Coverage Matrix

| Peripheral / Feature | Covered by Requirements |
|----------------------|-------------------------|
| RV32IM Processor Core | REQ-001, REQ-011 |
| 4×4 INT8 AI Accelerator | REQ-002 |
| SPI (LIDAR) | REQ-003, REQ-018 |
| Speed Sensor (Tachometer) | REQ-004 |
| Servo PWM (Brake) | REQ-005, REQ-019 |
| Buzzer PWM (Alert) | REQ-006, REQ-019 |
| UART (Debug) | REQ-007 |
| GPIO (Alert Outputs) | REQ-008 |
| AXI4-Lite Interconnect | REQ-009 |
| ADAS Algorithm | REQ-010 |
| Safety Lockstep | REQ-011 |
| ECC Memory | REQ-012 |
| Window Watchdog | REQ-013 |
| Safety Shutdown | REQ-014 |
| Safety Monitor | REQ-015 |
| Safe State | REQ-016 |
| Timing/Latency | REQ-017 |

### 7.3 ASIL Allocation Summary

| ASIL Level | Requirements | Justification |
|------------|-------------|---------------|
| ASIL-D | REQ-001 through REQ-006, REQ-009 through REQ-019 | Core safety functions: computation, sensing, actuation, safety mechanisms, timing |
| ASIL-B | REQ-008 | GPIO alert outputs — secondary alerting, not primary safety path |
| QM | REQ-007 | UART debug — no safety function, purely diagnostic |

### 7.4 HARA Safety Goal to Requirement Traceability

| Safety Goal | ASIL | Hazards Covered | Primary Requirements | Verification |
|-------------|------|----------------|---------------------|-------------|
| SG-01: Prevent unintended braking | ASIL-D | HAZ-01, HAZ-02, HAZ-08, HAZ-12 | REQ-005, REQ-010, REQ-011, REQ-014, REQ-015 | Fault injection: force brake command without threat; verify PWM stays low |
| SG-02: Ensure braking on collision threat | ASIL-D | HAZ-03, HAZ-04, HAZ-05, HAZ-07, HAZ-09, HAZ-11, HAZ-13, HAZ-18 | REQ-003, REQ-004, REQ-005, REQ-010, REQ-011, REQ-012, REQ-013, REQ-017 | Directed test: 200+ sensor scenarios with known expected brake decisions |
| SG-03: Prevent sensor data hazard | ASIL-D | HAZ-07, HAZ-08, HAZ-09, HAZ-18, HAZ-19 | REQ-003, REQ-004, REQ-012, REQ-018 | Fault injection: corrupted SPI frames, ECC fault injection on FIFO |
| SG-04: Prevent AI misclassification hazard | ASIL-D | HAZ-11, HAZ-12 | REQ-002, REQ-015 | Test: feed known misclassifying inputs; verify Safety Monitor overrides |
| SG-05: Detect hardware failure → safe state | ASIL-D | HAZ-13, HAZ-14, HAZ-15, HAZ-16, HAZ-17 | REQ-011, REQ-012, REQ-013, REQ-014, REQ-015, REQ-016 | Fault injection campaign (1,000+ injections per safety mechanism) |
| SG-06: Prevent latent memory fault accumulation | ASIL-D | HAZ-15 | REQ-012 | Extended SEU injection simulation with scrubbing enabled |

### 7.5 STPA Safety Constraint Traceability

| Constraint ID | Constraint Summary | Mapped Requirement | Coverage Status |
|---------------|--------------------|--------------------|-----------------|
| SC-U01 | Brake within 5 ms of threat detection | REQ-017 | ✅ Full |
| SC-U02 | No brake without threat (dual-confirmed) | REQ-010, REQ-015 | ✅ Full |
| SC-U03 | Proportional brake force | REQ-005, REQ-010 | ⚠️ Partial — P2 enhancement |
| SC-U04 | Detection-to-actuation ≤ 100 ms | REQ-017, §4.7.4 | ✅ Full |
| SC-U05 | Brake only when TTC < 2.0 s | REQ-010, REQ-015 | ✅ Full |
| SC-U06 | Brake held while threat persists | REQ-010 | ✅ Full |
| SC-U07 | Brake release debounce (500 ms) | REQ-010 | ⚠️ Gap — P1: add debounce requirement |
| SC-U08 | Safety Monitor override on 2-cycle mismatch | REQ-015 §(c) | ✅ Full |
| SC-U09 | Safety Monitor 2-cycle debounce | REQ-015 §(c) | ✅ Full |
| SC-U10 | Fault aggregation (combinatorial, persistent) | REQ-015 §(d)(e) | ✅ Full |
| SC-U11 | Shutdown propagation ≤ 1 ms (combinatorial) | REQ-014 §(1)(4) | ✅ Full |
| SC-U12 | WDT timeout if not serviced | REQ-013 §(b)(d) | ✅ Full |
| SC-U13 | WDT open window ≥ 1 ms | REQ-013 §(b) | ✅ Full |
| SC-U14 | WDT independent clock (ring oscillator) | REQ-013 §(f) | ✅ Full |
| SC-U15 | Discard corrupted SPI frames | REQ-018 §(h) | ✅ Full |
| SC-U16 | SPI timeout → sensor fault → safe state | REQ-003, REQ-016 | ⚠️ Gap — P1: quantify timeout threshold |

**Coverage:** 11/16 constraints fully covered. 2 partially covered. 3 gaps identified (GAP-01 through GAP-04 in STPA §B.5).

---

## 8. Glossary

### 8.1 Key Terms

| Term | Definition |
|------|------------|
| **Braking Engagement** | Activation of the servo PWM to apply brake force |
| **Collision Threat** | Condition where TTC < threshold AND ego speed > minimum speed |
| **Ego Vehicle** | The host vehicle carrying the ADAS SoC |
| **Fault Status Register** | Hardware register latching the source of the most recent safety fault |
| **FIT** | Failures In Time — 1 FIT = 1 failure per 10⁹ hours of operation |
| **FMEDA** | Failure Modes, Effects, and Diagnostic Analysis — quantitative safety analysis per ISO 26262-5:2018 |
| **FTTI** | Fault Tolerant Time Interval — maximum time from fault occurrence to safe state entry before a hazard can occur (per ISO 26262-4:2018 §7.4.2.3) |
| **HARA** | Hazard Analysis and Risk Assessment — mandatory analysis per ISO 26262-3:2018 §7, assigning ASIL levels to identified hazards |
| **LFM** | Latent Fault Metric — fraction of latent multiple-point faults covered by safety mechanisms (ISO 26262-5:2018 Annex D) |
| **Lockstep** | Two identical processor cores executing the same instruction stream with fixed temporal offset, outputs compared cycle-by-cycle |
| **PMHF** | Probabilistic Metric for random Hardware Failures — residual risk of safety goal violation per hour (ISO 26262-5:2018 Annex D) |
| **Safe State** | Deterministic SoC state entered on fault detection; defined in REQ-016 |
| **Safety Shutdown Signal** | Hardware signal that triggers transition to safe state, generated combinatorially from fault sources |
| **SPFM** | Single Point Fault Metric — fraction of single-point and residual faults covered by safety mechanisms (ISO 26262-5:2018 Annex D) |
| **STPA** | System-Theoretic Process Analysis — hazard analysis method identifying unsafe control actions and interaction hazards (Leveson, 2012) |
| **Time-To-Collision (TTC)** | Distance to object divided by relative velocity magnitude |
| **UCA** | Unsafe Control Action — a control action that, in a particular context, leads to a hazard (STPA terminology) |
| **Window Watchdog** | A watchdog timer that requires servicing within a specific time window (not too early, not too late) |

### 8.2 Reference Documents

| Reference | Description |
|-----------|-------------|
| ISO 26262-1:2018 | Road vehicles — Functional safety — Vocabulary |
| ISO 26262-3:2018 | Road vehicles — Functional safety — Concept phase (§7: HARA) |
| ISO 26262-4:2018 | Road vehicles — Functional safety — Product development at the system level (§7.4.2: Safety requirements, FTTI) |
| ISO 26262-5:2018 | Road vehicles — Functional safety — Product development at the hardware level (Annex D: SPFM/LFM/PMHF) |
| ISO 26262-9:2018 | Road vehicles — Functional safety — ASIL-oriented and safety-oriented analyses (§6.4: Coexistence criteria) |
| ISO 26262-10:2018 | Road vehicles — Functional safety — Guidelines |
| ISO/PAS 21448:2022 | Road vehicles — Safety of the intended functionality (SOTIF) |
| Abdulkhaleq et al. (2017) | "A Systematic Approach Based on STPA for Developing a Dependable Architecture for Fully Automated Driving Vehicles." *Procedia Engineering* 179:41–51. DOI: 10.1016/j.proeng.2017.03.094 |
| Andreasyan et al. (2026) | "RISC-V Functional Safety for Autonomous Automotive Systems: An Analytical Framework." arXiv:2604.17391 |
| Rogenmoser et al. (2025) | "Design and Experimental Characterization of a Fault-Tolerant 28nm RISC-V-based SoC." *IEEE TNS*, Vol. 72, No. 8. arXiv:2407.05938 (Trikarenos) |
| Abella et al. (2023) | "Toward Building a Lockstep NOEL-V Core." RISC-V Summit, Barcelona. arXiv:2307.15436 (SafeLS) |
| Debaenst et al. (2016) | "ISO 26262: The New Standard for Vehicle Functional Safety." *Design & Elektronik* |
| RISC-V Unprivileged ISA Specification v20191213 | RV32I and RV32M instruction set definitions |
| AMBA AXI4-Lite Protocol Specification | ARM IHI 0022E |
| SkyWater SKY130 PDK Documentation | sky130_fd_sc_hs cell library |

---

## Document Revision History

| Revision | Date | Author | Changes |
|----------|------|--------|---------|
| 1.0 | 2026-04-29 | Priya Patel | Initial release. 19 requirements covering functional, safety, timing, and interface domains for ASIL-D ADAS SoC. |
| 2.0 | 2026-04-29 | Priya Nair | **P0 fixes per Professor's literature review (PROF-REV-002):** Added Section 4.7 (Quantitative Safety Targets: SPFM ≥ 99%, LFM ≥ 90%, PMHF < 10 FIT, FTTI ≤ 100 ms per ISO 26262-5:2018). Added Appendix A (HARA: 19 hazards identified, ASIL assignment with S/E/C justification, 6 safety goals). Added Appendix B (STPA: control structure model, 16 UCAs across 4 controllers, 8 causal scenarios, 16 safety constraints per Abdulkhaleq et al. 2017). Updated traceability matrix (Sections 7.4, 7.5) linking safety goals and STPA constraints to requirements. Updated glossary with HARA, STPA, SPFM, LFM, PMHF, FTTI, FIT, FMEDA, UCA definitions. Updated reference documents with key literature (Abdulkhaleq 2017, Andreasyan 2026, Rogenmoser/Trikarenos 2025, Abella/SafeLS 2023). Integrated quantitative targets into safety architecture narrative. |

---

## 9. Appendices

### Appendix A: Hazard Analysis and Risk Assessment (HARA)

**Normative Reference:** ISO 26262-3:2018 §7 — Hazard Analysis and Risk Assessment  
**Methodology:** Item definition → Hazard identification → Situation analysis → ASIL determination → Safety goals  
**Date of Analysis:** 2026-04-29  
**Participants:** System Engineer, Architect, Verification Lead

#### A.1 Item Definition

**Item:** ADAS Forward Collision Warning and Autonomous Emergency Braking (AEB) System  
**Vehicle Type:** Passenger vehicle (M1 category)  
**Operational Scenarios Analyzed:**

| Scenario | Speed Range | Environment | Road Type | Traffic Density |
|----------|-------------|-------------|-----------|-----------------|
| S1: Highway cruising | 80–130 km/h | Dry, daylight | Divided highway | Moderate |
| S2: Urban arterial | 30–60 km/h | Dry, daylight | Multi-lane arterial | High |
| S3: Urban residential | 10–40 km/h | Dry, daylight | Residential street | Low |
| S4: Highway — wet | 60–100 km/h | Wet, daylight | Divided highway | Low |
| S5: Night highway | 80–130 km/h | Dry, night | Divided highway | Low |
| S6: Urban — pedestrian | 10–50 km/h | Dry, daylight | Urban street | Moderate (pedestrians present) |

**Functions:**
- F1: Object detection via LIDAR (distance + relative velocity)
- F2: AI-based object classification (vehicle / pedestrian / stationary-obstacle)
- F3: Time-To-Collision (TTC) computation
- F4: Autonomous braking actuation via servo PWM
- F5: Audible driver alert via buzzer PWM
- F6: Safety monitoring and fault detection (lockstep, ECC, WDT)
- F7: Safety shutdown (transition to safe state on fault)

#### A.2 Hazard Identification

The following table enumerates all hazardous events identified for the ADAS braking system. Hazards are classified by the malfunctioning function, the hazardous event at the vehicle level, and the operational scenario where it can occur.

| Hazard ID | Function | Hazardous Event | Operational Scenario | Potential Harm |
|-----------|----------|----------------|---------------------|----------------|
| HAZ-01 | F4 — Braking actuation | **Unintended maximum braking** at highway speed — servo PWM erroneously commands 100% brake force when no collision threat exists | S1, S5 | Rear-end collision from following vehicle; loss of vehicle control; occupant whiplash |
| HAZ-02 | F4 — Braking actuation | **Unintended partial braking** — servo commands 20–50% brake force spuriously | S1, S2 | Driver confusion; following vehicle reaction hazard; unnecessary deceleration |
| HAZ-03 | F3, F4 — TTC + Braking | **Failure to brake on genuine collision threat** — system fails to engage brakes when TTC < 2.0 s and ego speed > 5 km/h with valid threat object | S1, S2, S3, S6 | High-speed frontal collision; pedestrian impact; fatal or life-threatening injuries |
| HAZ-04 | F5, F4 — Alert + Braking | **Delayed braking** — brake engagement delayed by > 100 ms beyond the FTTI after collision threat detection | S1, S2 | Reduced deceleration distance; collision at higher residual speed; increased injury severity |
| HAZ-05 | F4 — Braking actuation | **Insufficient brake force** — system commands less than required brake force for the detected TTC | S1 | Collision not fully avoided; residual impact at speed |
| HAZ-06 | F4 — Braking actuation | **Excessive brake force** — system commands brake force exceeding what is needed, causing wheel lock-up or skid | S1, S4 (wet) | Loss of steering control; secondary collision |
| HAZ-07 | F1 — LIDAR sensing | **Sensor data corruption — wrong distance** — LIDAR reports object farther than actual, TTC is overestimated | S1, S2, S6 | Failure to trigger braking (leads to HAZ-03) |
| HAZ-08 | F1 — LIDAR sensing | **Sensor data corruption — wrong distance (closer)** — LIDAR reports object closer than actual, TTC is underestimated | S1, S2 | Unnecessary braking (leads to HAZ-01) |
| HAZ-09 | F1 — LIDAR sensing | **Sensor data corruption — wrong relative velocity** — incorrect velocity sign or magnitude | S1, S2 | Incorrect TTC → wrong braking decision (leads to HAZ-01 or HAZ-03) |
| HAZ-10 | F1 — LIDAR sensing | **Complete loss of LIDAR input** — SPI communication failure, sensor disconnect, or sensor internal fault | S1, S2, S5 | System blindness; no collision threat detection possible |
| HAZ-11 | F2 — AI classification | **AI misclassification — threat object classified as non-threat** — vehicle/pedestrian classified as "background" or "stationary-obstacle" with wrong threshold | S1, S2, S6 | Failure to brake for genuine threat (leads to HAZ-03) |
| HAZ-12 | F2 — AI classification | **AI misclassification — non-threat classified as threat** — noise/shadow classified as vehicle | S1, S2 | Unnecessary braking (leads to HAZ-01) |
| HAZ-13 | F3 — TTC computation | **TTC calculation error** — arithmetic fault in RV32IM core (multiply/divide error, bit-flip in ALU) produces wrong TTC | S1, S2 | Wrong braking decision (leads to HAZ-01 or HAZ-03) |
| HAZ-14 | F6 — Safety monitoring | **Lockstep checker failure (stuck-at-0)** — lockstep comparator develops a stuck-at-0 fault and fails to detect core divergence | All | All processor faults become latent; any computation fault goes undetected → leads to HAZ-01 or HAZ-03 |
| HAZ-15 | F6 — Safety monitoring | **ECC failure to correct** — single-bit error accumulates to uncorrectable double-bit error in critical SRAM | All | Memory corruption → wrong sensor data or wrong algorithm parameters → leads to HAZ-01 or HAZ-03 |
| HAZ-16 | F6 — Safety monitoring | **WDT failure** — watchdog timer fails to timeout on hung processor; system continues operating with frozen firmware | S1, S2, S5 | Stale sensor data; no brake update; undetected system hang |
| HAZ-17 | F6, F7 — Safety shutdown | **Safety shutdown path failure** — redundant shutdown logic fails; fault is detected but brake is not released | All | Brake stuck in engaged position → vehicle cannot move; or brake stuck disengaged with active fault |
| HAZ-18 | F1, F4 — Sensor + Actuator | **Speed sensor corruption** — ego speed reads 0 km/h at highway speed | S1, S5 | TTC algorithm condition `ego_speed > 5 km/h` fails → no braking on collision threat (leads to HAZ-03) |
| HAZ-19 | F1, F4 — Sensor + Actuator | **Speed sensor corruption** — ego speed reads erroneously high | S2, S3 | Premature braking threshold activation; unnecessary braking at low speed |

#### A.3 ASIL Determination

Each hazard is assessed for Severity (S), Exposure (E), and Controllability (C) per ISO 26262-3:2018 Annex B tables:

**Severity (S):**
| Class | Description | Criteria |
|-------|-------------|----------|
| S0 | No injuries | — |
| S1 | Light/moderate injuries | AIS 1–2 |
| S2 | Severe/life-threatening injuries (survival probable) | AIS 3–4 |
| S3 | Life-threatening/fatal injuries | AIS 5–6 |

**Exposure (E):**
| Class | Description | Duration/Probability |
|-------|-------------|---------------------|
| E0 | Incredible | — |
| E1 | Very low probability | < 1% of operating time |
| E2 | Low probability | 1–4% of operating time |
| E3 | Medium probability | 4–10% of operating time |
| E4 | High probability | > 10% of operating time |

**Controllability (C):**
| Class | Description | Criteria |
|-------|-------------|----------|
| C0 | Generally controllable | > 99% of drivers can avoid harm |
| C1 | Simply controllable | > 90% of drivers can avoid harm |
| C2 | Normally controllable | < 90% of drivers can avoid harm |
| C3 | Difficult or impossible to control | Few/none can avoid harm |

**ASIL Assignment Table (ISO 26262-3:2018 Table 7):**

| Hazard ID | Description | S | E | C | ASIL | Rationale |
|-----------|-------------|---|---|---|------|-----------|
| HAZ-01 | Unintended max braking at highway speed | S3 | E4 | C3 | **ASIL-D** | Sudden maximum braking at 130 km/h on highway: life-threatening (S3), highway driving is >10% of operating time (E4), following driver has <2s to react to unexpected braking (C3) |
| HAZ-02 | Unintended partial braking | S2 | E3 | C1 | **ASIL-A** | Partial braking (20–50%) at moderate speed: severe injuries possible (S2), medium exposure (E3), most drivers can compensate with accelerator (C1). ASIL per S2+E3+C1 = ASIL-A. |
| HAZ-03 | Failure to brake on collision threat | S3 | E4 | C3 | **ASIL-D** | Frontal collision at highway speed: fatal (S3), collision threats are inherent to driving (E4), driver relies on system — cannot override in time (C3) |
| HAZ-04 | Delayed braking (>100 ms) | S3 | E3 | C2 | **ASIL-C** | Delayed braking reduces deceleration margin: life-threatening possible (S3), medium probability delay scenarios (E3), most drivers cannot compensate for >100ms delay at highway speed (C2). S3+E3+C2 = ASIL-C. Note: at worst-case, if delay exceeds driver reaction window, may escalate to ASIL-D. |
| HAZ-05 | Insufficient brake force | S2 | E2 | C2 | **ASIL-A** | Partial braking force: severe injuries at residual impact speed (S2), low probability (E2), some drivers may supplement with manual braking (C2). S2+E2+C2 = ASIL-A. |
| HAZ-06 | Excessive brake force (wheel lock) | S2 | E2 | C2 | **ASIL-A** | Wheel lock at highway speed: loss of steering control, severe possible (S2), low probability (E2), trained drivers may modulate brake (C2). S2+E2+C2 = ASIL-A. |
| HAZ-07 | LIDAR distance wrong (farther) | S3 | E3 | C3 | **ASIL-D** | Leads to HAZ-03 (failure to brake). Inherits ASIL-D by causal chain. E3 accounts for EMI environments where corruption probability is elevated. |
| HAZ-08 | LIDAR distance wrong (closer) | S3 | E3 | C3 | **ASIL-D** | Leads to HAZ-01 (unintended braking). Inherits ASIL-D. |
| HAZ-09 | LIDAR velocity wrong | S3 | E3 | C3 | **ASIL-D** | Leads to HAZ-01 or HAZ-03 depending on error sign. Inherits ASIL-D. |
| HAZ-10 | Complete LIDAR loss | S2 | E2 | C1 | **QM(A)** | Sensor loss is detectable (SPI timeout, CRC failure). System enters safe state — no braking, alert driver. Severe potential (S2) but low exposure (E2) and simply controllable — driver takes over (C1). S2+E2+C1 = ASIL-A at most; handled as QM with safe-state transition. |
| HAZ-11 | AI false negative (missed threat) | S3 | E3 | C3 | **ASIL-D** | Pedestrian/vehicle missed at urban speeds: fatal possible (S3), urban pedestrian scenarios are common (E3), driver may not see occluded pedestrian (C3). S3+E3+C3 = ASIL-D. |
| HAZ-12 | AI false positive (ghost threat) | S2 | E3 | C2 | **ASIL-B** | Unnecessary braking on false detection: severe possible (S2, rear-end), medium exposure (E3), driver may override (C2). S2+E3+C2 = ASIL-B. Reduced relative to HAZ-01 because Safety Monitor provides independent verification. |
| HAZ-13 | TTC arithmetic error | S3 | E3 | C3 | **ASIL-D** | RV32IM ALU fault produces wrong TTC → wrong braking decision. Inherits ASIL-D. Lockstep is the primary detection mechanism. |
| HAZ-14 | Lockstep comparator stuck-at-0 | S3 | E2 | C3 | **ASIL-D** | If lockstep comparator fails silently, ALL processor faults become latent. Life-threatening (S3), low probability event (E2), undetectable by driver (C3). S3+E2+C3 = ASIL-D. Mitigation: comparator self-test. |
| HAZ-15 | ECC uncorrectable error | S3 | E2 | C3 | **ASIL-D** | Uncorrectable double-bit error in critical SRAM: life-threatening if in safety-critical data (S3), low probability at sea level (E2), uncontrollable (C3). S3+E2+C3 = ASIL-D. |
| HAZ-16 | WDT failure (no timeout) | S3 | E1 | C3 | **ASIL-C** | WDT fails to detect hung processor: life-threatening potential (S3), very low probability (E1 — independent clock, ring oscillator), uncontrollable (C3). S3+E1+C3 = ASIL-C. |
| HAZ-17 | Safety shutdown path failure | S3 | E1 | C2 | **ASIL-C** | Redundant shutdown fails: life-threatening (S3), very low probability (E1 — pure combinatorial logic), normally controllable by driver taking manual control (C2). S3+E1+C2 = ASIL-C. |
| HAZ-18 | Speed sensor reads 0 at highway speed | S3 | E3 | C3 | **ASIL-D** | Leads to HAZ-03 (no braking). Inherits ASIL-D by causal chain. |
| HAZ-19 | Speed sensor reads erroneously high | S2 | E2 | C2 | **ASIL-A** | Premature braking at low speed: severe possible (S2), low probability (E2), driver can override (C2). S2+E2+C2 = ASIL-A. |

**ASIL Distribution Summary:**
| ASIL | Count | Hazards |
|------|-------|---------|
| ASIL-D | 11 | HAZ-01, HAZ-03, HAZ-07, HAZ-08, HAZ-09, HAZ-11, HAZ-13, HAZ-14, HAZ-15, HAZ-18, HAZ-03 (via HAZ-11/HAZ-13) |
| ASIL-C | 3 | HAZ-04, HAZ-16, HAZ-17 |
| ASIL-B | 1 | HAZ-12 |
| ASIL-A | 4 | HAZ-02, HAZ-05, HAZ-06, HAZ-19 |
| QM | 1 | HAZ-10 |

#### A.4 Safety Goals

Derived from the HARA, the following safety goals are defined with ASIL ratings per ISO 26262-3:2018 §7.5:

| Safety Goal ID | Safety Goal | ASIL | FTTI | Safe State | Covered Hazards | Mapped Requirements |
|----------------|-------------|------|------|------------|-----------------|---------------------|
| **SG-01** | The system shall prevent unintended braking actuation: the servo PWM shall not command brake force > 0% when no collision threat exists (TTC ≥ 2.0 s OR ego speed ≤ 5 km/h OR object not threat-relevant class). | ASIL-D | ≤ 100 ms | Brake released (PWM at 1000 µs or output-low) | HAZ-01, HAZ-02, HAZ-08, HAZ-12 | REQ-005, REQ-010, REQ-011, REQ-014, REQ-015 |
| **SG-02** | The system shall ensure braking actuation when a genuine collision threat exists: the servo PWM shall command brake force proportional to TTC within 5 ms of threat detection when TTC < 2.0 s AND ego speed > 5 km/h AND object is threat-relevant class. | ASIL-D | ≤ 100 ms | — (normal operation goal) | HAZ-03, HAZ-04, HAZ-05, HAZ-07, HAZ-09, HAZ-11, HAZ-13, HAZ-18 | REQ-003, REQ-004, REQ-005, REQ-010, REQ-011, REQ-012, REQ-013, REQ-017 |
| **SG-03** | The system shall detect sensor data corruption and prevent corrupted data from triggering a hazardous braking decision. | ASIL-D | ≤ 100 ms | Brake released; fault logged | HAZ-07, HAZ-08, HAZ-09, HAZ-18, HAZ-19 | REQ-003, REQ-004, REQ-012, REQ-018 |
| **SG-04** | The system shall prevent AI misclassification from causing a hazardous braking decision through independent hardware verification of the braking decision. | ASIL-D | ≤ 100 ms | Brake released if AI vs Safety Monitor disagree | HAZ-11, HAZ-12 | REQ-002, REQ-015 |
| **SG-05** | The system shall detect any single-point failure in the computational hardware (processor, memory, interconnect) and transition to the defined safe state within the FTTI. | ASIL-D | ≤ 100 ms | As defined in REQ-016 | HAZ-13, HAZ-14, HAZ-15, HAZ-16, HAZ-17 | REQ-011, REQ-012, REQ-013, REQ-014, REQ-015, REQ-016 |
| **SG-06** | The system shall prevent accumulation of latent memory faults that could combine into a safety goal violation. | ASIL-D | N/A (preventive) | — | HAZ-15 | REQ-012 |

**Note on ASIL Escalation:** SG-04 is assigned ASIL-D (elevated from HAZ-12's ASIL-B) because the AI classification is a component of the ASIL-D braking decision chain. Per ISO 26262-9:2018 §6.4.3, when a lower-ASIL element can contribute to an ASIL-D safety goal violation, the element inherits the higher ASIL through coexistence criteria.

#### A.5 References for HARA

- ISO 26262-3:2018 §7 — Hazard Analysis and Risk Assessment
- ISO 26262-3:2018 Annex B — ASIL Determination Tables
- ISO 26262-4:2018 §7.4.2 — System-Level Safety Requirements
- Abdulkhaleq, A., et al. "A Systematic Approach Based on STPA for Developing a Dependable Architecture for Fully Automated Driving Vehicles." *Procedia Engineering* 179:41–51, 2017. DOI: 10.1016/j.proeng.2017.03.094
- Debaenst, P., et al. "ISO 26262: The New Standard for Vehicle Functional Safety." *Design & Elektronik*, 2016

---

### Appendix B: System-Theoretic Process Analysis (STPA)

**Normative Reference:** Abdulkhaleq et al., "Using STPA in Compliance with ISO 26262" (arXiv:1703.03657)  
**Methodology:** STPA per Leveson (2012) — Control structure modeling → Unsafe Control Actions (UCAs) → Causal scenarios → Safety constraints  
**Date of Analysis:** 2026-04-29  
**Participants:** System Engineer, Architect, Verification Lead

#### B.1 Introduction

STPA (System-Theoretic Process Analysis) extends traditional hazard analysis (FMEA, FTA) by modeling the system as a hierarchical control structure with feedback loops. While FMEA examines *component failures*, STPA identifies *interaction hazards* — hazards that arise from correct components interacting incorrectly due to flawed control logic, timing issues, or missing feedback.

For the ADAS braking system, STPA is essential because:
1. The braking decision involves multiple interacting controllers (RV32IM firmware, AI accelerator, Safety Monitor, WDT)
2. Timing interactions (sensor polling rate vs. brake update rate vs. WDT window) create subtle hazard conditions
3. The safety architecture includes diverse redundancy (lockstep core + independent Safety Monitor) whose interaction must be analyzed

Per Abdulkhaleq et al. (2017), the Continental Automotive study applying STPA to an automated driving system identified **27 unsafe control actions** and **129 unsafe scenarios** from interaction failures alone — hazards that a traditional component-level FMEA would miss.

#### B.2 Control Structure Model

The ADAS braking system is modeled as the following hierarchical control structure:

```
                         ┌─────────────────────────────────┐
                         │     DRIVER (Human Supervisor)    │
                         │  - Manual override capability    │
                         │  - Situational awareness         │
                         └───────────┬─────────────────────┘
                                     │ Override input
                                     ▼
┌────────────────────────────────────────────────────────────────────┐
│                  ADAS SoC CONTROL SYSTEM                            │
│                                                                    │
│  ┌─────────────────────┐          ┌──────────────────────────┐    │
│  │  RV32IM FIRMWARE     │          │  SAFETY MONITOR (HW)     │    │
│  │  (Primary Controller)│◄────────►│  (Independent Checker)   │    │
│  │                     │ mismatch │                          │    │
│  │ - Sensor polling     │  compare │ - Simplified TTC check   │    │
│  │ - AI dispatch        │          │ - Direct sensor reading  │    │
│  │ - TTC computation    │          │ - Mismatch counter       │    │
│  │ - Brake decision     │          │                          │    │
│  └────────┬─────────────┘          └──────────┬───────────────┘    │
│           │ Control Action                     │ Override           │
│           │ (Brake Command)                    │ (Shutdown)         │
│           ▼                                   ▼                    │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │              REDUNDANT SHUTDOWN PATH (RSC)                  │   │
│  │  OR-gate: Lockstep_fault | ECC_fault | WDT_fault | SM_mismatch│
│  │           | External_shutdown                               │   │
│  └──────────────────────────┬─────────────────────────────────┘   │
│                             │                                      │
│  ┌──────────────┐   ┌──────▼──────┐   ┌──────────────┐            │
│  │ LIDAR Sensor │   │   ACTUATORS  │   │ Speed Sensor │            │
│  │ (Input)      │   │              │   │ (Input)      │            │
│  │              │   │ Servo PWM    │   │              │            │
│  │ Object dist. │   │ Buzzer PWM   │   │ Ego speed    │            │
│  │ Rel. velocity│   │ GPIO Alerts  │   │              │            │
│  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘            │
└─────────┼──────────────────┼──────────────────┼────────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌──────────────────┐ ┌──────────────┐ ┌──────────────────┐
│  VEHICLE DYNAMICS│ │ BRAKE ACTUATOR│ │ WHEEL TACHOMETER │
│  (Controlled     │ │ (Mechanical)  │ │ (Physical)       │
│   Process)       │ │               │ │                  │
│                  │ │ - Brake pads  │ │ - Pulse output   │
│  - Speed         │ │ - Servo motor │ │                  │
│  - Position      │ │ - Caliper     │ │                  │
│  - Deceleration  │ │               │ │                  │
└──────────────────┘ └──────────────┘ └──────────────────┘
          ▲                                        │
          │          ENVIRONMENT                    │
          │    - Road surface (μ)                   │
          │    - Other vehicles                     │
          │    - Pedestrians                        │
          │    - Weather/lighting                   │
          └────────────────────────────────────────┘

Control Loop:
  1. LIDAR + Speed Sensor → provide feedback about the controlled process
  2. RV32IM Firmware → computes TTC, makes braking decision (control action)
  3. Safety Monitor → independently verifies the control action
  4. RSC → can override the control action (safety shutdown)
  5. Actuators → execute the control action on the physical process
  6. Vehicle Dynamics → responds to actuation; sensors measure the response
```

#### B.3 Unsafe Control Actions (UCAs)

Per the STPA methodology, Unsafe Control Actions are classified into four types:
1. **Not Providing** — A required control action is not provided
2. **Providing** — An unsafe control action is provided (when not needed)
3. **Wrong Timing/Order** — A control action is provided too early, too late, or out of sequence
4. **Stopped Too Soon / Applied Too Long** — A correct control action has incorrect duration

**UCA Analysis for ADAS Braking Controller (RV32IM Firmware → Servo PWM):**

| UCA ID | Type | Control Action | Context | Hazard | ASIL | Safety Constraint |
|--------|------|---------------|---------|--------|------|-------------------|
| UCA-01 | Not Providing | Apply Brake (PWM: 500–2500 µs) | Collision threat exists (TTC < 2.0 s, ego > 5 km/h, threat-relevant object) | Failure to brake → collision (HAZ-03, SG-02) | ASIL-D | SC-U01: The braking command shall be issued within 5 ms of collision threat detection per REQ-017. |
| UCA-02 | Providing | Apply Brake (PWM: 500–2500 µs) | No collision threat exists (TTC ≥ 2.0 s OR ego ≤ 5 km/h OR no threat object) | Unintended braking (HAZ-01, SG-01) | ASIL-D | SC-U02: The braking command shall NOT be issued when TTC ≥ 2.0 s AND ego speed ≤ 5 km/h AND object is not threat-relevant. Dual-confirmed by Safety Monitor. |
| UCA-03 | Providing | Apply Maximum Brake Force | Collision threat exists but partial brake sufficient | Excessive braking → wheel lock (HAZ-06, SG-01) | ASIL-A | SC-U03: Brake force shall be proportional to TTC: (2.0 − TTC) / 2.0 × 100%, clamped to [0%, 100%]. |
| UCA-04 | Wrong Timing | Apply Brake | Collision threat exists | Brake applied too late (delayed > 100 ms beyond FTTI after threat detection) → HAZ-04 | ASIL-C | SC-U04: Brake actuation shall commence within 5 ms per REQ-017. Detection-to-actuation total ≤ 100 ms per FTTI. |
| UCA-05 | Wrong Timing | Apply Brake | Collision threat exists | Brake applied too early (TTC still > 2.0 s but firmware misjudges scenario) → premature braking | ASIL-A | SC-U05: Brake shall ONLY be applied when TTC < 2.0 s. TTC computation verified by Safety Monitor. |
| UCA-06 | Stopped Too Soon | Release Brake (PWM → 1000 µs) | Collision threat still exists (obstacle still present, ego speed still > 5 km/h) | Premature brake release → residual collision (HAZ-03) | ASIL-D | SC-U06: Brake shall remain engaged while TTC < 2.0 s AND ego speed > 0 km/h. Release only when TTC ≥ 2.0 s or ego speed = 0 km/h. |
| UCA-07 | Applied Too Long | Maintain Brake Force | Collision threat has passed (obstacle cleared, ego speed = 0 km/h) | Brake stuck engaged → vehicle cannot resume motion | QM(A) | SC-U07: Brake shall release when TTC ≥ 2.0 s for 500 ms (debounce) and ego speed = 0 km/h. Driver override may release brake. |

**UCA Analysis for Safety Monitor (HW → RSC → Actuators):**

| UCA ID | Type | Control Action | Context | Hazard | ASIL | Safety Constraint |
|--------|------|---------------|---------|--------|------|-------------------|
| UCA-08 | Not Providing | Trigger Safety Shutdown | RV32IM commands unsafe brake (disagrees with Safety Monitor) | Failure to override unsafe command (HAZ-01, HAZ-03) | ASIL-D | SC-U08: Safety Monitor shall trigger shutdown within 2 consecutive mismatch cycles if brake decision disagrees with RV32IM. |
| UCA-09 | Providing | Trigger Safety Shutdown | RV32IM commands correct brake (agrees with Safety Monitor); Safety Monitor's independent check has a false positive | Unnecessary safe state → system out of service (nuisance shutdown) | QM | SC-U09: Safety Monitor shall require 2 consecutive mismatch cycles before triggering shutdown (debounce). Single-cycle mismatches shall increment counter but not trigger shutdown. |
| UCA-10 | Not Providing | Detect and Report Fault | Fault condition exists (lockstep mismatch, ECC error, WDT timeout) but fault aggregator fails to latch it | Silent failure → fault becomes latent (HAZ-14, HAZ-15) | ASIL-D | SC-U10: Fault aggregator shall latch ALL fault sources combinatorially. No software involvement in fault detection path. Fault register shall persist across warm reset. |
| UCA-11 | Wrong Timing | Trigger Safety Shutdown | Fault detected but RSC propagation delayed beyond FTTI | Delayed safe state → hazard window exceeds 100 ms | ASIL-C | SC-U11: Safety shutdown signal shall propagate to PWM outputs within 1 ms per REQ-014. RSC is pure combinatorial logic. |

**UCA Analysis for Window Watchdog Timer (WDT → RSC):**

| UCA ID | Type | Control Action | Context | Hazard | ASIL | Safety Constraint |
|--------|------|---------------|---------|--------|------|-------------------|
| UCA-12 | Not Providing | Trigger WDT Fault | Processor hung (firmware not servicing WDT within window) | Undetected system hang → stale braking state (HAZ-16) | ASIL-C | SC-U12: WDT shall timeout if not serviced within closed window period. Timeout period configurable 5–100 ms. |
| UCA-13 | Providing | Trigger WDT Fault | Processor operating normally but WDT was serviced outside the timing window due to transient timing jitter | Nuisance reset/shutdown → system out of service | QM | SC-U13: WDT open window shall be at least 1 ms to accommodate worst-case timing jitter. Test: verify no false triggers at ±100 µs jitter per REQ-017. |
| UCA-14 | Not Providing | Operate from Independent Clock | System clock fails; WDT shares the failed clock | WDT cannot timeout → undetected system failure | ASIL-C | SC-U14: WDT shall operate from independent ring oscillator clock (wdt_clk). The ring oscillator shall remain active even when sys_clk is absent. |

**UCA Analysis for Sensor Data Path (LIDAR/SPI → RV32IM):**

| UCA ID | Type | Control Action | Context | Hazard | ASIL | Safety Constraint |
|--------|------|---------------|---------|--------|------|-------------------|
| UCA-15 | Providing | Provide Sensor Data | Sensor data is corrupted (CRC mismatch, stuck bits, out-of-range values) | Corrupted data fed to TTC algorithm (HAZ-07, HAZ-08, HAZ-09) | ASIL-D | SC-U15: SPI frames with CRC mismatch shall be discarded. Out-of-range values (distance < 0 or > 200m, |velocity| > 400 km/h) shall be flagged and not used. |
| UCA-16 | Not Providing | Provide Sensor Data | LIDAR sensor disconnected, SPI timeout | No sensor data → system blind (HAZ-10) | QM(A) | SC-U16: SPI timeout (> 3 frame periods without valid data) shall trigger sensor fault and transition to safe state (brake released, alert driver). |

#### B.4 Causal Scenarios

For each identified UCA, causal scenarios describe how the unsafe control action could occur. Scenarios are grouped by causal factor type.

**CS-1: Firmware Logic Error (UCA-01, UCA-02)**
- **Scenario:** A firmware bug in the TTC threshold comparison causes the brake command to be issued when TTC > 2.0 s, or NOT issued when TTC < 2.0 s.
- **Causal Factors:** Incorrect inequality operator; threshold value loaded from corrupted memory; variable overflow/underflow in TTC calculation.
- **Prevention:** Lockstep core checking (REQ-011) detects computational divergence; Safety Monitor (REQ-015) independently computes TTC and cross-checks decision.
- **Detection:** Lockstep mismatch (within 3 cycles); Safety Monitor mismatch (within 2 cycles).

**CS-2: Sensor Data Corruption (UCA-01, UCA-02 via input path)**
- **Scenario:** EMI-induced glitch on SPI bus causes LIDAR distance to read 0 cm → TTC computed as 0 → immediate braking command. Or distance reads 65535 cm (max) → TTC computed as large → no braking.
- **Causal Factors:** Automotive EMI environment (ignition noise, motor drive PWM); insufficient SPI signal integrity; missing or failed CRC check.
- **Prevention:** CRC-8 per frame (REQ-018); ECC on SPI FIFO (REQ-012); glitch filter on speed sensor input (REQ-004).
- **Detection:** CRC mismatch → frame discarded; Safety Monitor independently reads raw sensor data.

**CS-3: AI Classification Error (UCA-01, UCA-02 via classification path)**
- **Scenario:** A pedestrian at 15 m distance is misclassified as "stationary-obstacle" (threshold 1.2 s) instead of "pedestrian" (threshold 2.5 s). At 50 km/h (13.9 m/s), TTC = 1.08 s. This exceeds the obstacle threshold (1.2 s) so braking is NOT triggered, but falls below the pedestrian threshold (2.5 s) so braking SHOULD be triggered.
- **Causal Factors:** Insufficient AI training data for pedestrian at oblique angles; INT8 quantization error in weight representation; adversarial input pattern.
- **Prevention:** Safety Monitor uses independent simplified algorithm (no AI dependency) — it checks raw TTC against a conservative threshold (2.5 s) regardless of object class.
- **Detection:** Safety Monitor detects that TTC < 2.5 s but brake not commanded → mismatch alarm.

**CS-4: Lockstep Comparator Failure (UCA-10)**
- **Scenario:** The lockstep comparator's XOR tree develops a stuck-at-0 fault on one bit position. The RV32IM core produces an incorrect brake command due to an ALU bit-flip, but the comparator fails to detect the divergence because the stuck-at bit masks the mismatch.
- **Causal Factors:** Manufacturing defect; aging-related gate oxide breakdown; single-event damage.
- **Prevention:** Comparator self-test — periodic forced mismatch injection verifies comparator functionality. Trikarenos methodology (Rogenmoser et al., 2025).
- **Detection:** Self-test FSM detects comparator failure; Safety Monitor provides independent second check.

**CS-5: Timing Interaction — Sensor Update vs. Brake Decision (UCA-04)**
- **Scenario:** The firmware polling loop reads the LIDAR at 100 Hz (10 ms period) but a brake decision computed at t=0 uses sensor data from t=-15 ms (stale data from a missed SPI frame). The object has moved 21 cm at 50 km/h, potentially changing the TTC classification.
- **Causal Factors:** SPI frame drop; firmware scheduling jitter; interrupt latency from concurrent UART debug output.
- **Prevention:** Data freshness timestamp on each sensor reading; firmware checks `timestamp < 10 ms` before using data. WDT detects firmware hang.
- **Detection:** Stale data flag in sensor register; Safety Monitor uses direct sensor reading (bypasses firmware buffer).

**CS-6: Common-Mode Clock Failure (UCA-14)**
- **Scenario:** The system PLL loses lock and sys_clk stops. The WDT shares sys_clk (no independent clock). The processor hangs silently; WDT also stops; no fault is detected; system is frozen in whatever braking state was last commanded.
- **Causal Factors:** PLL unlock due to supply voltage droop; crystal oscillator failure; clock tree short-circuit.
- **Prevention:** Independent ring oscillator wdt_clk — per Trikarenos (Rogenmoser et al., 2025) and ISO 26262-5:2018 Table D.3. REQ-013 mandates this.
- **Detection:** WDT timeout on wdt_clk; combinatorial shutdown path (RSC) does not depend on sys_clk.

**CS-7: Redundant Shutdown Path Contention (UCA-11)**
- **Scenario:** The RSC OR-gate correctly detects a fault (lockstep mismatch) and asserts shutdown. Simultaneously, the firmware attempts to command a brake application (normal operation, unaware of fault). The PWM output could see a glitch during the transition.
- **Causal Factors:** Timing of RSC assertion relative to PWM update register write.
- **Prevention:** RSC shutdown is fed directly to PWM output enable (async, combinatorial). PWM register writes are gated by `!safety_shutdown`. REQ-014 §(1) mandates PWM output low within 1 ms.
- **Detection:** Testbench scenario: simultaneous fault injection + PWM write; verify PWM output is low.

**CS-8: ECC Error Accumulation (UCA-10, latent)**
- **Scenario:** A single-bit error occurs in SRAM at time t₁. The ECC corrects it transparently, and an interrupt is logged. However, the firmware does not process the interrupt (due to higher-priority task or ISR disabled). A second single-bit error occurs on the same word at t₂ → uncorrectable double-bit error.
- **Causal Factors:** High SEU rate in automotive radiation environment; firmware ISR latency; no background scrubbing.
- **Prevention:** Background memory scrubber (SRAM) periodically reads and corrects all addresses; scrubber operates on independent clock domain.
- **Detection:** ECC double-bit error detected; unrecoverable fault → safety shutdown.

#### B.5 Safety Constraints Derived from STPA

The following table consolidates all safety constraints derived from the STPA analysis. These map to existing requirements and identify new requirements where gaps exist:

| Constraint ID | Constraint | Mapped Requirement | Status |
|---------------|------------|--------------------|--------|
| SC-U01 | Braking shall be commanded within 5 ms of collision threat detection | REQ-017 (5 ms latency) | ✅ Covered |
| SC-U02 | Braking shall NOT be commanded when TTC ≥ 2.0 s AND ego ≤ 5 km/h AND no threat object, dual-confirmed by Safety Monitor | REQ-010, REQ-015 | ✅ Covered |
| SC-U03 | Brake force shall be proportional to TTC: (2.0 − TTC) / 2.0 × 100% | REQ-005 (500–2500 µs range), REQ-010 | ⚠️ Partially covered — REQ-010 specifies binary engage/disengage. Proportional braking is a P2 enhancement. |
| SC-U04 | Brake actuation shall commence within 5 ms; total detection-to-actuation ≤ 100 ms | REQ-017 (5 ms), §4.7.4 (FTTI ≤ 100 ms) | ✅ Covered |
| SC-U05 | Brake shall ONLY be applied when TTC < 2.0 s, verified by Safety Monitor | REQ-010, REQ-015 | ✅ Covered |
| SC-U06 | Brake shall remain engaged while TTC < 2.0 s; release only when TTC ≥ 2.0 s | REQ-010 | ✅ Covered |
| SC-U07 | Brake shall release when TTC ≥ 2.0 s for 500 ms debounce; driver may override | REQ-010 (logic), REQ-005 (PWM control) | ⚠️ Debounce period not explicitly specified |
| SC-U08 | Safety Monitor shall trigger shutdown on 2 consecutive mismatch cycles | REQ-015 §(c) | ✅ Covered |
| SC-U09 | Safety Monitor shall require 2 consecutive mismatches before shutdown (debounce) | REQ-015 §(c) | ✅ Covered |
| SC-U10 | Fault aggregator shall latch ALL fault sources combinatorially; fault register persists across warm reset | REQ-015 §(d)(e) | ✅ Covered |
| SC-U11 | Safety shutdown shall propagate to PWM outputs within 1 ms; RSC is combinatorial | REQ-014 §(1)(4) | ✅ Covered |
| SC-U12 | WDT shall timeout if not serviced within closed window period (5–100 ms configurable) | REQ-013 §(b)(d) | ✅ Covered |
| SC-U13 | WDT open window ≥ 1 ms to accommodate timing jitter | REQ-013 §(b) | ✅ Covered |
| SC-U14 | WDT shall operate from independent ring oscillator clock; active when sys_clk absent | REQ-013 §(f) | ✅ Covered |
| SC-U15 | Corrupted SPI frames (CRC mismatch, out-of-range values) shall be discarded | REQ-018 §(h) | ✅ Covered |
| SC-U16 | SPI timeout (> 3 frame periods without valid data) → sensor fault → safe state | REQ-003 (FIFO), REQ-016 (safe state) | ⚠️ SPI timeout threshold not explicitly quantified in requirements |

**New Requirements Identified by STPA:**

| ID | Gap | Recommendation | Priority |
|----|-----|---------------|----------|
| GAP-01 | Proportional brake force (SC-U03): REQ-010 specifies binary engage/disengage. STPA identifies that proportional braking improves controllability. | Add REQ-020: "Brake force shall be proportional to TTC per mapping (2.0 − TTC)/2.0 × 100%." | P2 (enhancement) |
| GAP-02 | Brake release debounce (SC-U07): No debounce period specified to prevent chatter. | Add debounce requirement to REQ-010: "Brake release requires TTC ≥ 2.0 s sustained for 500 ms." | P1 (strongly recommended) |
| GAP-03 | SPI timeout quantification (SC-U16): No quantified timeout for sensor loss detection. | Add to REQ-003: "SPI timeout threshold = 3 × frame period (30 ms at 100 Hz)." | P1 (safety-critical) |
| GAP-04 | Comparator self-test interval (CS-4): No requirement for periodic comparator self-test. | Add REQ-021: "Lockstep comparator shall undergo automated self-test at interval ≤ 10,000 cycles." | P0 (critical per professor's P0-5) |

#### B.6 STPA Summary

The STPA analysis identified:
- **16 Unsafe Control Actions** across four controllers (RV32IM firmware, Safety Monitor, WDT, SPI sensor path)
- **8 Causal Scenarios** covering firmware bugs, sensor corruption, AI errors, timing interactions, clock failures, and error accumulation
- **16 Safety Constraints**, of which 11 are fully covered by existing requirements and 4 identify gaps

Compared to the component-level FMEA implicit in REQ-011 through REQ-016, STPA identified the following interaction hazards that the FMEA would miss:
1. **CS-5 (Stale sensor data timing interaction):** A correct SPI and correct firmware can still produce a wrong brake decision if the polling schedule and SPI frame rate interact badly. FMEA would classify both components as "functioning correctly."
2. **CS-7 (RSC-PWM contention):** A correctly operating RSC and correctly operating PWM can interact to produce a glitch. FMEA would show both modules functioning.
3. **CS-3 (AI-to-Safety Monitor gap):** The AI classifier may be "correct" per its training but still unsafe per the Safety Monitor's independent check. The interaction between these two correct components is the hazard.

#### B.7 References for STPA

- Abdulkhaleq, A., et al. "A Systematic Approach Based on STPA for Developing a Dependable Architecture for Fully Automated Driving Vehicles." *Procedia Engineering* 179:41–51, 2017. DOI: 10.1016/j.proeng.2017.03.094
- Leveson, N. G. *Engineering a Safer World: Systems Thinking Applied to Safety.* MIT Press, 2012.
- ISO 26262-3:2018 §7 — Hazard Analysis and Risk Assessment
- ISO 21448:2022 — Safety of the Intended Functionality (SOTIF) — for interaction hazards between correct components

---

*End of SRS-ADAS-V2-001*
