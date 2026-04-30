# NIGHT_RUN_LOG.md — ADAS v2 SoC P&R Overnight Flow
> **Backend Lead:** David Chen | **Date:** 2026-04-29 | **Iteration:** 1/3
> **Design:** ADAS v2 Safety-Critical SoC | **Technology:** sky130_fd_sc_hs

---

## PHASE 0: INITIALIZATION

| Item | Value | Timestamp |
|------|-------|-----------|
| Host RAM | 7.6 GB total, 5.9 GB available | 2026-04-29 17:03 UTC |
| Host Disk | 228 GB free (391 GB total) | 2026-04-29 17:03 UTC |
| PDK | sky130_fd_sc_hs @ c6d73a35 | verified |
| ORFS | v2.0-14726-g72ee0f9c4 | verified |
| Yosys | v0.9 (within ORFS) | verified |
| Netlist | 44,028 cells (v3, black-boxed TCM) | pre-existing |
| RTL files | 23 modules in ORFS src/ | 2026-04-29 17:10 UTC |

### Black-Box Resolution Plan
- **tcm_8kb** (×2: u_itcm, u_dtcm): Replaced with reduced-size placeholder (64×39-bit register file, ~2.5K FFs each). Original 2048×39-bit would be ~342K standard cells → OOM on 8GB. **Must be replaced with sky130 SRAM hard macro for tape-out.**
- **sram_buffer** (×1: u_sram): Synthesized as-is (16×39-bit register file, ~624 FFs). Small enough for P&R.

### ORFS Configuration
- **Config:** `designs/sky130hs/adas_v2/config.mk`
- **Die:** 2500×2500 µm, Core: 2400×2400 µm (5.76 mm²)
- **Utilization target:** 30% (PLACE_DENSITY = 0.30)
- **GPL_TIMING_DRIVEN:** 0 (OOM prevention)
- **Routing layers:** met1–met4
- **Expected cell count:** ~50K (44K logic + 2×2.5K TCM + 0.6K sram)
- **TCL patches applied:** `-force_center_initial_place` (already commented), `GPL_TIMING_DRIVEN=0` (config)

---
