# ============================================================================
# Makefile — cocotb simulation for ADAS v2 SoC
# ============================================================================

TOPLEVEL_LANG = verilog

# Top level: test wrapper (exposes AXI master port for BFM driving)
TOPLEVEL = adas_soc_tb_wrapper

# Verilog sources: all RTL modules + test wrapper
VERILOG_SOURCES = $(PWD)/../rtl/adas_soc_top.v \
                  $(PWD)/../rtl/rv32im_core.v \
                  $(PWD)/../rtl/axi4_lite_interconnect.v \
                  $(PWD)/../rtl/axi4_lite_decode.v \
                  $(PWD)/../rtl/ai_accelerator_top.v \
                  $(PWD)/../rtl/systolic_array.v \
                  $(PWD)/../rtl/mac_pe.v \
                  $(PWD)/../rtl/sram_buffer.v \
                  $(PWD)/../rtl/result_buffer.v \
                  $(PWD)/../rtl/control_fsm.v \
                  $(PWD)/../rtl/spi_controller.v \
                  $(PWD)/../rtl/servo_pwm.v \
                  $(PWD)/../rtl/speed_sensor.v \
                  $(PWD)/../rtl/buzzer_pwm.v \
                  $(PWD)/../rtl/uart.v \
                  $(PWD)/../rtl/gpio.v \
                  $(PWD)/../rtl/fault_aggregator.v \
                  $(PWD)/../rtl/wdt.v \
                  $(PWD)/../rtl/lockstep_comparator.v \
                  $(PWD)/../rtl/redundant_shutdown.v \
                  $(PWD)/../rtl/tcm_8kb.v \
                  $(PWD)/adas_soc_tb_wrapper.v

# cocotb test module
MODULE = test_unified_regression

# Icarus Verilog compile args
COMPILE_ARGS = -g2012 -Wall

# Simulation args
SIM_ARGS = -v

# Waveform dump
PLUSARGS = -fst

include $(shell cocotb-config --makefiles)/Makefile.sim
