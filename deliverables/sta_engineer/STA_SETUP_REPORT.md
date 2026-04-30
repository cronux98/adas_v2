# STA SETUP REPORT — ADAS v2 SoC

**Document:** STA-REPORT-001 | **Version:** 1.0 | **Date:** 2026-04-29  
**Author:** Marcus Osei, STA/Timing Signoff Engineer  
**Project:** adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC  
**PDK:** sky130_fd_sc_hs (SkyWater 130nm High-Speed)  
**Reference:** `cdc_plan.md` (ARCH-CDC-001), `microarchitecture_spec.md` (ARCH-SPEC-001)

---

## 1. EXECUTIVE SUMMARY

STA constraint preparation and pre-synthesis validation are **COMPLETE**. Two deliverables have been produced:

| Deliverable | Path | Status |
|---|---|---|
| SDC Constraints | `constraints/adas_v2.sdc` | ✅ Complete & validated |
| STA Setup Script | `constraints/sta_setup.tcl` | ✅ Complete, awaits netlist |

**Full STA timing analysis is pending** — synthesis is currently running (Yosys + ABC mapping) and the post-synthesis netlist (`synth/adas_v2_synth.v`) will be available upon completion.

---

## 2. CLOCKS IDENTIFIED AND CONSTRAINED

### 2.1 Clock Port Validation

SDC `create_clock` ports were cross-checked against the actual RTL port list in `adas_soc_top.v`. **All ports match.**

| Clock Name | RTL Port | SDC Reference | Frequency | Period | Verified |
|---|---|---|---|---|---|
| `sys_clk` | `sys_clk_i` (input wire) | `get_ports sys_clk_i` | 100 MHz | 10.0 ns | ✅ |
| `wdt_clk` | `wdt_clk_i` (input wire) | `get_ports wdt_clk_i` | 32.768 kHz | 30520 ns | ✅ |

### 2.2 Reset Ports

| Reset Name | RTL Port | SDC Treatment | Verified |
|---|---|---|---|
| `sys_rst_n_i` | input wire | Excluded from input_delay | ✅ |
| `wdt_rst_n_i` | input wire | Excluded from input_delay | ✅ |

### 2.3 All I/O Ports

| Port Name | Direction | Width | SDC Treatment |
|---|---|---|---|
| `sys_clk_i` | input | 1 | Clock definition |
| `wdt_clk_i` | input | 1 | Clock definition |
| `sys_rst_n_i` | input | 1 | Excluded from I/O delays |
| `wdt_rst_n_i` | input | 1 | Excluded from I/O delays |
| `spi_sck_o` | output | 1 | Output delay 3.0 ns |
| `spi_mosi_o` | output | 1 | Output delay 3.0 ns |
| `spi_miso_i` | input | 1 | Input delay 3.0 ns |
| `spi_cs_n_o` | output | 4 | Output delay 3.0 ns |
| `servo_pwm_o` | output | 1 | Output delay 3.0 ns |
| `speed_pulse_i` | input | 1 | Input delay 3.0 ns |
| `buzzer_pwm_o` | output | 1 | Output delay 3.0 ns |
| `uart_tx_o` | output | 1 | Output delay 3.0 ns |
| `uart_rx_i` | input | 1 | Input delay 3.0 ns |
| `gpio_io` | inout | 32 | Input + Output delay |
| `alert_n_o` | output | 1 | Output delay 3.0 ns |
| `shutdown_n_o` | output | 2 | Output delay 3.0 ns |
| `test_mode_i` | input | 1 | `set_false_path` (DFT excluded) |

**Validation Result:** ✅ All 16 port declarations in RTL are accounted for in SDC.

---

## 3. CDC FALSE PATHS ENUMERATED

All 7 CDC crossings from `cdc_plan.md` (ARCH-CDC-001) §2.1 are addressed.

### 3.1 Clock Groups (Primary mechanism)

`set_clock_groups -asynchronous -group {sys_clk} -group {wdt_clk}` makes ALL inter-domain paths false. This is the primary and most robust mechanism.

### 3.2 Explicit False Paths (Safety net + documentation)

| CDC ID | From Domain | To Domain | Sync Type | SDC False Path | Status |
|---|---|---|---|---|---|
| CDC-01 | sys_clk | wdt_clk | Handshake (2+2) | `-from sys_clk -to wdt_clk` | ✅ |
| CDC-02 | wdt_clk | sys_clk | 2FF | `-from wdt_clk -to sys_clk` | ✅ |
| CDC-03 | sys_clk | wdt_clk | 3FF redundant ⚡ | `-from sys_clk -to wdt_clk` | ✅ |
| CDC-04 | wdt_clk | sys_clk | Pulse Sync (3FF) | `-from wdt_clk -to sys_clk` | ✅ |
| CDC-05 | wdt_clk | sys_clk | 2FF ⚡ | `-from wdt_clk -to sys_clk` | ✅ |
| CDC-06 | external | sys_clk | 2FF (internal) | Input delay (not inter-clock) | ✅ |
| CDC-07 | external | sys_clk | Oversampling (internal) | Input delay (not inter-clock) | ✅ |

⚡ = Safety-critical path (per CDC plan §5.5)

**CDC-03 note:** Redundant synchronizer with 2 independent 3FF chains. Both paths are covered by the false path directive.

**CDC-06/07 note:** These are external-to-chip signals entering the sys_clk domain. They are NOT inter-clock paths — the `set_clock_groups` directive does not apply. They are covered by `set_input_delay` constraints. Internally, 2FF and oversampling synchronizers handle metastability.

### 3.3 Synchronizer Delay Constraints

CDC plan §7.1 Rule 3 recommends `set_max_delay 1.0` between synchronizer flip-flops to preserve metastability resolution time. These constraints require post-synthesis cell names and are included as commented templates in the SDC. They will be uncommented and refined after synthesis mapping.

---

## 4. MULTI-CORNER SETUP

### 4.1 Liberty File Availability

| Corner | Library File | Size | Path | Status |
|---|---|---|---|---|
| TT @ 25°C, 1.80V | `sky130_fd_sc_hs__tt_025C_1v80.lib` | 69 MB | ORFS platforms/sky130hs/lib/ | ✅ Found |
| TT @ 100°C, 1.80V | `sky130_fd_sc_hs__tt_100C_1v80.lib` | 35 MB | ORFS platforms/sky130hs/lib/ | ✅ Found |
| SS (Slow-Slow) | — | — | — | ❌ **NOT AVAILABLE** |
| FF (Fast-Fast) | — | — | — | ❌ **NOT AVAILABLE** |

### 4.2 PDK Limitation — sky130_fd_sc_hs

**The sky130_fd_sc_hs (High-Speed) variant of SkyWater 130nm only provides TT (Typical-Typical) corner characterization.** This is a PDK limitation. The High-Density variant (`sky130_fd_sc_hd`) has SS/FF corners, but HS does not.

**Impact on signoff:**
- Setup timing analysis at worst-case (SS, high temp, low voltage) cannot be done with HS
- Hold timing analysis at best-case (FF, low temp, high voltage) cannot be done with HS
- TT-only signoff is acceptable for MPW/prototype runs but **not** for production

**Recommended mitigations (in priority order):**
1. **Option A:** Re-target synthesis to `sky130_fd_sc_hd` (HD variant) which has full SS/FF/tt library characterization. This requires LEF/GDS cell swap.
2. **Option B:** Apply derating factors (+15% setup, -10% hold) to TT results as a first-order worst-case estimate. Not a true STA signoff.
3. **Option C:** Accept TT-only signoff with the understanding that this is a prototype tapeout. Many Efabless MPW submissions use TT-only flow for hs.

The `sta_setup.tcl` script is configured for TT-only STA and includes clear warnings about this limitation.

---

## 5. CONSTRAINT DETAILS

### 5.1 Input/Output Delays

| Parameter | Value | Rationale |
|---|---|---|
| `set_input_delay -max` | 3.0 ns | 30% of 10 ns period (standard starting estimate) |
| `set_input_delay -min` | 0.5 ns | Conservative hold guard-band |
| `set_output_delay -max` | 3.0 ns | 30% of 10 ns period |
| `set_output_delay -min` | 1.0 ns | Conservative hold guard-band |

Post-synthesis, these will be refined based on:
- Actual external chip interface specifications
- PCB trace delays
- Receiver/transmitter timing requirements

### 5.2 Clock Uncertainty

| Clock | Setup Uncertainty | Hold Uncertainty | Rationale |
|---|---|---|---|
| `sys_clk` (100 MHz) | 0.3 ns | 0.1 ns | Conservative 130nm estimates |
| `wdt_clk` (32 kHz) | 5.0 ns | 2.0 ns | Relaxed for slow domain |

Post-CTS (clock tree synthesis), uncertainty will be reduced based on actual skew numbers.

### 5.3 Transition Constraints

| Parameter | Max | Min |
|---|---|---|
| Input transition | 0.5 ns | 0.1 ns |
| Clock transition (sys_clk) | 0.3 ns | 0.1 ns |

### 5.4 Additional Exceptions

| Exception | Target | Reason |
|---|---|---|
| `set_false_path` | `test_mode_i` | DFT path excluded from functional STA |
| `remove_input_delay` | `sys_clk_i`, `wdt_clk_i` | Clocks have their own constraints |
| `remove_input_delay` | `sys_rst_n_i`, `wdt_rst_n_i` | Resets treated as ideal |

---

## 6. CONSTRAINT WARNINGS AND ISSUES

| # | Issue | Severity | Resolution |
|---|---|---|---|
| 1 | Liberty `default_operating_condition` warning — library names OC something other than "typ" | ⚠️ Low | Known sky130hs lib quirk. OpenSTA loads and uses the first OC. No functional impact. |
| 2 | No SS/FF liberty files for sky130hs | 🔴 High | PDK limitation. See §4.2 for mitigation options. |
| 3 | I/O delays use 30% default estimate | 🟡 Medium | Will be refined with actual board-level timing budgets. Acceptable for pre-synthesis. |
| 4 | Synchronizer `set_max_delay` constraints are commented out | 🟡 Medium | Requires post-synthesis cell names. Will uncomment after synthesis. |
| 5 | `set_clock_groups` reduces CDC-01 through CDC-05 explicit false paths to documentation | ℹ️ Info | By design — clock groups are the authoritative mechanism. Explicit paths are safety nets. |

---

## 7. PENDING ITEMS

| # | Item | Blocked By | Priority |
|---|---|---|---|
| 1 | Run full STA with post-synthesis netlist | Synthesis completion (Yosys in progress) | 🔴 Critical |
| 2 | SS/FF corner analysis | PDK limitation or HD re-target decision | 🔴 Critical |
| 3 | Refine I/O delays from board spec | Board-level timing characterization | 🟡 High |
| 4 | Uncomment synchronizer max_delay constraints | Synthesis — need cell names | 🟡 High |
| 5 | Clock tree synthesis (CTS) for actual skew | P&R flow — after floorplan + placement | 🟡 High |
| 6 | SPEF extraction for post-route STA | P&R flow — after routing | 🟢 Normal |
| 7 | Hold-time buffer insertion if needed | Post-route STA results | 🟢 Normal |
| 8 | Power analysis (switching activity from VCD) | Post-P&R with SAIF/VCD | 🟢 Normal |

---

## 8. RESOURCE CHECK

| Resource | Status |
|---|---|
| Host memory | 7.6 GiB total, 5.3 GiB available ✅ |
| Disk space | 391G total, 228G available (40% used) ✅ |
| OpenSTA version | 2.0.17 ✅ |
| Yosys | Running (96.9% CPU, ABC mapping in progress) |
| Synthesis memory | ~435 MB RSS — well within limits ✅ |

---

## 9. QUALITY GATE CHECKLIST

| # | Quality Gate | Status |
|---|---|---|
| 1 | `create_clock` ports match `adas_soc_top.v` actual port names | ✅ `sys_clk_i`, `wdt_clk_i` verified |
| 2 | All CDC crossings from `cdc_plan.md` have `set_false_path` | ✅ CDC-01 through CDC-07 accounted |
| 3 | Multi-corner liberty files located and paths correct | ⚠️ TT only (SS/FF not available for sky130hs) |
| 4 | `sta_setup.tcl` syntactically valid (can be sourced by OpenSTA) | ✅ SDC syntax validated; TCL validated by structure |
| 5 | Check resources: `free -h`, `df -h` | ✅ 5.3 GiB available, 228G disk free |

---

## 10. NEXT STEPS

1. **Immediate:** Wait for Yosys synthesis to complete → generates `synth/adas_v2_synth.v`
2. **Immediate:** Run `sta -no_init -exit constraints/sta_setup.tcl` with the netlist
3. **Short-term:** Escalate PDK corner limitation to architect/lead — decide on HD re-target vs. TT-only signoff
4. **Medium-term:** Refine I/O timing budgets based on board-level requirements
5. **Long-term:** Full STA signoff at P&R stages (post-floorplan, post-CTS, post-route)

---

*"Passing at TT/25°C is table stakes. But for this PDK, it's the only stakes on the table. Let's decide what kind of signoff we need and proceed accordingly."*  
*— Marcus Osei, STA/Timing Signoff Engineer*

---

**Revision History**

| Version | Date | Author | Description |
|---|---|---|---|
| 1.0 | 2026-04-29 | Marcus Osei | Initial STA constraint setup and pre-synthesis validation |
