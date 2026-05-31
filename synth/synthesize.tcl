# =============================================================================
# Yosys Synthesis Script — ADAS v2 SoC (MEMORY-SAFE VERSION)
# Target: sky130_fd_sc_hs (HS, 130nm), tt_025C_1v80, 100 MHz
# Tool:  Yosys 0.43 | Top: adas_soc_top
# Flow:  synth -noabc → dfflibmap → (ABC skipped — memory limit)
# Issue: Full ABC on TCM 8KB (342K inferred gates) exceeds 7.6 GB RAM → SIGKILL
# =============================================================================

# --- Load Liberty ---
read_liberty -lib ~/Desktop/openroad/OpenROAD-flow-scripts/flow/platforms/sky130hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib

# --- Read All RTL ---
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/adas_soc_top.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/ai_accelerator_top.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/axi4_lite_decode.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/axi4_lite_interconnect.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/buzzer_pwm.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/control_fsm.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/dual_lockstep_top.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/fault_aggregator.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/gpio.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/lockstep_comparator.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/mac_pe.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/redundant_shutdown.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/result_buffer.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/rv32im_core.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/servo_pwm.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/speed_sensor.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/spi_controller.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/sram_buffer.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/sram_scrubber.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/systolic_array.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/tcm_8kb.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/uart.v
read_verilog ~/vlsi-team/shared/projects/adas_v2/rtl/wdt.v

# --- Hierarchy Check ---
hierarchy -check -top adas_soc_top

# --- Generic Synthesis (NO ABC — avoid OOM on TCM 342K gates) ---
synth -top adas_soc_top -noabc

# --- Sequential Cell Mapping (light — just maps DFFs to sky130 flops) ---
dfflibmap -liberty ~/Desktop/openroad/OpenROAD-flow-scripts/flow/platforms/sky130hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib

# --- Cleanup ---
setundef -zero -params
opt_clean -purge
opt

# --- Statistics ---
stat

# --- Write Netlist ---
write_verilog -noattr ~/vlsi-team/shared/projects/adas_v2/synth/adas_v2_synth.v
