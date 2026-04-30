# ============================================================================
# adas_v2.sdc — Synopsys Design Constraints for ADAS v2 SoC
# ============================================================================
# Project:   adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
# Author:    Marcus Osei, STA/Timing Signoff Engineer
# Date:      2026-04-29
# PDK:       sky130_fd_sc_hs (SkyWater 130nm High-Speed)
# Reference: cdc_plan.md (ARCH-CDC-001), block_interfaces.md (ARCH-IF-001)
#
# Clock Summary:
#   sys_clk : 100 MHz (10 ns period) — main functional domain
#   wdt_clk : 32.768 kHz (30.52 µs period) — independent watchdog domain
#
# Constraint Philosophy:
#   - sys_clk and wdt_clk are asynchronous (independent sources).
#     All inter-domain paths are CDC and get false-path treatment.
#   - I/O delays use 30% of period as default estimate.
#   - Hold-time margins will be analyzed post-synthesis when
#     actual interconnect delays are available.
# ============================================================================

# ============================================================================
# 1. CLOCK DEFINITIONS
# ============================================================================
# Match top-level port names from adas_soc_top.v:
#   input wire sys_clk_i
#   input wire wdt_clk_i

create_clock -name sys_clk -period 10.0 [get_ports sys_clk_i]
create_clock -name wdt_clk -period 30520 [get_ports wdt_clk_i]


# ============================================================================
# 2. CLOCK GROUPS — ASYNCHRONOUS DOMAINS
# ============================================================================
# sys_clk and wdt_clk are produced by independent oscillators with no
# known phase/frequency relationship (see cdc_plan.md §1.1).
# All inter-domain paths must be treated as false paths.
# Synchronizers handle metastability; STA does not time these paths.
set_clock_groups -asynchronous \
    -group {sys_clk} \
    -group {wdt_clk}


# ============================================================================
# 3. INPUT / OUTPUT DELAYS
# ============================================================================
# All functional I/O operates on sys_clk domain.
# Default estimate: 30% of clock period = 3.0 ns.
#
# This will be refined post-synthesis when block-level timing budgets
# and board-level constraints are fully characterized.

# --- Input Delays ---
# External inputs arrive 3.0 ns after sys_clk edge (worst-case external logic).
set_input_delay -clock sys_clk -max 3.0 [all_inputs]
set_input_delay -clock sys_clk -min 0.5 [all_inputs]

# --- Output Delays ---
# Outputs must be stable 3.0 ns before next sys_clk edge (external setup requirement).
set_output_delay -clock sys_clk -max 3.0 [all_outputs]
set_output_delay -clock sys_clk -min 1.0 [all_outputs]

# --- Clock Port Exclusions ---
# OpenSTA does not support remove_input_delay.  Exclude clock/reset
# from input_delay by constraining only non-clock inputs instead.
# Original full-port constraints above work; clock ports are already
# constrained by create_clock so input_delay on them is a no-op.


# ============================================================================
# 4. FALSE PATHS — CLOCK DOMAIN CROSSINGS
# ============================================================================
# Reference: cdc_plan.md (ARCH-CDC-001) §2.1, §7.2
#
# set_clock_groups -asynchronous (above) already makes all paths between
# sys_clk and wdt_clk false. The explicit false_path declarations below
# are documentation and serve as a cross-check against the CDC plan.
# If the clock-groups directive is ever relaxed, these remain as safety nets.
#
# CDC-01: AXI4-Lite (sys_clk) → WDT Registers (wdt_clk) — Handshake
# CDC-02: WDT fault (wdt_clk) → Fault Aggregator (sys_clk) — 2FF sync
# CDC-03: Fault Agg (sys_clk) → RSC (wdt_clk) — 3FF redundant sync [SAFETY PATH]
# CDC-04: WDT prewarn (wdt_clk) → IRQ Controller (sys_clk) — Pulse sync
# CDC-05: RSC shutdown (wdt_clk) → GPIO (sys_clk) — 2FF sync [SAFETY PATH]

# --- CDC-01: AXI → WDT (through wdt_cdc_sys2wdt handshake module) ---
# All AXI register read/write paths cross from sys_clk to wdt_clk domain.
set_false_path -from [get_clocks sys_clk] -to [get_clocks wdt_clk]

# --- CDC-02: WDT fault → Fault Aggregator (through wdt_cdc_wdt2sys 2FF) ---
set_false_path -from [get_clocks wdt_clk] -to [get_clocks sys_clk]

# --- CDC-03: Fault Aggregator → RSC (through rsc_cdc 3FF redundant) ---
# SAFETY-CRITICAL PATH — verified by dual-redundant synchronizer
set_false_path -from [get_clocks sys_clk] -to [get_clocks wdt_clk]

# --- CDC-04: WDT Prewarn → IRQ Controller (through wdt_prewarn_cdc pulse sync) ---
set_false_path -from [get_clocks wdt_clk] -to [get_clocks sys_clk]

# --- CDC-05: RSC Shutdown → GPIO (through rsc_shdn_cdc 2FF) ---
# SAFETY-CRITICAL PATH
set_false_path -from [get_clocks wdt_clk] -to [get_clocks sys_clk]

# NOTE: CDC-06 (speed_pulse_i) and CDC-07 (uart_rx_i) are primary inputs
# entering the sys_clk domain with external-to-chip timing.
# These are NOT inter-clock paths; input_delay constraints cover them.
# The internal 2FF/oversampling synchronizers handle metastability.


# ============================================================================
# 5. RESET PATHS — ASYNCHRONOUS ASSERT, SYNCHRONOUS DE-ASSERT
# ============================================================================
# Both resets (sys_rst_n_i, wdt_rst_n_i) are asynchronous-assert,
# synchronous-de-assert. No false_path needed on reset — STA will
# analyze recovery/removal if the library has those arcs defined.
# For sky130hs TT libraries, recovery/removal is typically not
# characterized; if violations appear, verify they are false.


# ============================================================================
# 6. SYNCHRONIZER PLACEMENT CONSTRAINTS
# ============================================================================
# CDC plan §7.1 Rule 3: Synchronizer FFs must be placed adjacent.
# These constraints ensure routing delay between sync FFs stays
# below 1.0 ns to preserve metastability resolution time budget.
#
# NOTE: These require post-synthesis hierarchy. The cell names below
# are placeholder patterns; actual names depend on synthesis elaboration.
# Uncomment and adjust after synthesis:
#
# set_max_delay 1.0 -from [get_pins */sync_ff1/Q] -to [get_pins */sync_ff2/D]
# set_max_delay 1.0 -from [get_pins */sync_ff2/Q] -to [get_pins */sync_ff3/D]


# ============================================================================
# 7. ASYNC_REG ATTRIBUTES (INFORMATIONAL)
# ============================================================================
# RTL must tag synchronizer flip-flops with (* ASYNC_REG = "TRUE" *)
# to prevent synthesis from disturbing the synchronizer chain
# (cdc_plan.md §7.1 Rule 2). This is an RTL attribute, not an SDC directive,
# but STA should verify that the attribute is preserved in the netlist.


# ============================================================================
# 8. CLOCK UNCERTAINTY AND TRANSITION
# ============================================================================
# Conservative estimates for 130nm (sky130hs). Will be refined
# post-synthesis when clock tree is inserted.
#
# Clock uncertainty: accounts for jitter + skew + margin
#   - Setup uncertainty: 0.3 ns (300 ps)
#   - Hold uncertainty:  0.1 ns (100 ps)
set_clock_uncertainty -setup 0.3 [get_clocks sys_clk]
set_clock_uncertainty -hold  0.1 [get_clocks sys_clk]

# WDT clock — relaxed constraints for 32 kHz slow domain
set_clock_uncertainty -setup 5.0 [get_clocks wdt_clk]
set_clock_uncertainty -hold  2.0 [get_clocks wdt_clk]

# Input transition (slew) — conservative external driver model
set_input_transition -max 0.5 [all_inputs]
set_input_transition -min 0.1 [all_inputs]

# Clock transition (slew) — ideal clock assumed pre-CTS
# Post-CTS, actual clock slew will replace this.
set_clock_transition -max 0.3 [get_clocks sys_clk]
set_clock_transition -min 0.1 [get_clocks sys_clk]


# ============================================================================
# 9. DESIGN-SPECIFIC EXCEPTIONS
# ============================================================================

# --- Test Mode Paths ---
# test_mode_i gates DFT-related logic. Set false on test paths
# for functional STA. A separate DFT STA run will cover test paths.
set_false_path -from [get_ports test_mode_i]

# --- Inout Ports (GPIO) ---
# gpio_io[31:0] is bidirectional. Constraints apply to both input and
# output timing arcs. The set_input_delay/set_output_delay above
# cover the inout port from both directions.


# ============================================================================
# END OF SDC CONSTRAINTS
# ============================================================================
