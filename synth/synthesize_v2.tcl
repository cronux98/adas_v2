# =============================================================================
# Yosys Synthesis Script v2 — ADAS v2 SoC (TCM BLACK-BOXED)
# Target: sky130_fd_sc_hs (HS, 130nm), tt_025C_1v80, 100 MHz
# Tool:  Yosys 0.43 | Top: adas_soc_top
# Key:   tcm_8kb is NOT read — treated as blackbox (hard macro).
#        ABC now runs on remaining logic without the 342K-gate TCM.
# =============================================================================

# --- Load Liberty ---
read_liberty -lib /home/smdadmin/Desktop/openroad/OpenROAD-flow-scripts/flow/platforms/sky130hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib

# --- Read ALL RTL EXCEPT tcm_8kb.v (black-boxed as hard macro) ---
# tcm_8kb.v contains behavioral SRAM: reg [38:0] mem [0:2047]
# This 2048×39-bit array would expand to ~342K standard cells if mapped.
# By NOT reading it, Yosys treats tcm_8kb as a blackbox module.
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/adas_soc_top.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/rv32im_core.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/dual_lockstep_top.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/lockstep_comparator.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/axi4_lite_interconnect.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/axi4_lite_decode.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/ai_accelerator_top.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/systolic_array.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/mac_pe.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/control_fsm.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/spi_controller.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/servo_pwm.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/speed_sensor.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/buzzer_pwm.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/uart.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/gpio.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/fault_aggregator.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/wdt.v
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/redundant_shutdown.v

# sram_buffer.v: 16×39-bit reg file = 624 bits. Black-box for P&R.
# The sram_buffer_bb.v wrapper preserves ports; ORFS will substitute SRAM macro.
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/sram_buffer_bb.v
setattr -mod sram_buffer blackbox 1

# result_buffer.v: Individual registers only, no memory array. Synthesize fully.
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/result_buffer.v

# sram_scrubber.v: No memory array — logic only. Synthesize fully.
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/sram_scrubber.v

# --- tcm_8kb.v: READ but BLACK-BOX — behavioral SRAM, use as hard macro ---
read_verilog -sv /home/smdadmin/vlsi-team/shared/projects/adas_v2/rtl/tcm_8kb.v
setattr -mod tcm_8kb blackbox 1

# --- Hierarchy Check ---
hierarchy -check -top adas_soc_top

# --- Generic Synthesis ---
proc
opt

# --- Technology Mapping ---
techmap
opt

# --- Map Sequential Cells to sky130 Flip-Flops ---
dfflibmap -liberty /home/smdadmin/Desktop/openroad/OpenROAD-flow-scripts/flow/platforms/sky130hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib

# --- ABC — Technology-independent optimization + cell mapping ---
# Without the TCM's 342K-gate array, ABC should complete within 1-2 GB RAM
abc -liberty /home/smdadmin/Desktop/openroad/OpenROAD-flow-scripts/flow/platforms/sky130hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib

# --- Final Optimization ---
opt
clean

# --- Statistics with Liberty (cell count, area) ---
stat -liberty /home/smdadmin/Desktop/openroad/OpenROAD-flow-scripts/flow/platforms/sky130hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib

# --- Write Gate-Level Netlist ---
write_verilog -noattr /home/smdadmin/vlsi-team/shared/projects/adas_v2/synth/adas_v2_synth.v
