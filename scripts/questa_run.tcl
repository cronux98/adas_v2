# ============================================================================
# questa_run.tcl — QuestaSim / ModelSim Coverage-Driven Verification Script
# ============================================================================
# Project:  ADAS v2 — Safety-Critical RISC-V SoC
# Usage:
#   vsim -do scripts/questa_run.tcl
#   or:  make questa    (using the Makefile)
#
# Coverage Types Collected:
#   -b  Branch coverage
#   -c  Condition coverage
#   -s  Statement coverage
#   -t  Toggle coverage
#   -f  FSM coverage
# ============================================================================

# Suppress startup messages
quietly set NoPreferenceMsg 1

# ---- Project paths ----
set TB_TOP    adas_soc_top_tb
set RTL_DIR   ../rtl
set TB_DIR    ../tb
set WAVE_DB   vsim.wlf
set COV_DB    cov_work
set COV_RPT   coverage_report

# ---- Clean previous run ----
if {[file exists $WAVE_DB]}  { file delete -force $WAVE_DB }
if {[file exists $COV_DB]}  { file delete -force $COV_DB }
if {[file exists $COV_RPT]} { file delete -force $COV_RPT }
if {[file exists work]}     { file delete -force work }
if {[file exists transcript]} { file delete -force transcript }

echo "============================================================"
echo " ADAS v2 — QuestaSim Coverage-Driven Verification"
echo "============================================================"

# ---- Create work library ----
vlib work
vmap work work

# ---- Compile all RTL sources ----
echo "\n[COMPILE] RTL source files..."
vlog +cover=bcstf -sv -work work \
    $RTL_DIR/adas_soc_top.v \
    $RTL_DIR/rv32im_core.v \
    $RTL_DIR/dual_lockstep_top.v \
    $RTL_DIR/lockstep_comparator.v \
    $RTL_DIR/ai_accelerator_top.v \
    $RTL_DIR/systolic_array.v \
    $RTL_DIR/mac_pe.v \
    $RTL_DIR/control_fsm.v \
    $RTL_DIR/axi4_lite_interconnect.v \
    $RTL_DIR/axi4_lite_decode.v \
    $RTL_DIR/spi_controller.v \
    $RTL_DIR/servo_pwm.v \
    $RTL_DIR/speed_sensor.v \
    $RTL_DIR/buzzer_pwm.v \
    $RTL_DIR/uart.v \
    $RTL_DIR/gpio.v \
    $RTL_DIR/fault_aggregator.v \
    $RTL_DIR/redundant_shutdown.v \
    $RTL_DIR/wdt.v \
    $RTL_DIR/sram_buffer.v \
    $RTL_DIR/sram_buffer_bb.v \
    $RTL_DIR/sram_scrubber.v \
    $RTL_DIR/tcm_8kb.v \
    $RTL_DIR/result_buffer.v

# ---- Compile testbench ----
echo "\n[COMPILE] Testbench..."
vlog +cover=bcstf -sv -work work $TB_DIR/$TB_TOP.v

# ---- Check for compilation errors ----
if {[catch {vlog -version} err]} {
    echo "ERROR: vlog not found. Is QuestaSim/ModelSim in your PATH?"
    quit -code 1
}

# ---- Load design with coverage ----
echo "\n[LOAD] Elaborating design with coverage..."
vsim -coverage -voptargs="+cover=bcstf" work.$TB_TOP

# ---- Configure coverage ----
echo "\n[COVERAGE] Configuring coverage collection..."
coverage save -onexit -directive -codeAll $COV_DB/$TB_TOP.ucdb
coverage attribute -name TESTNAME -value "ADAS_v2_full_regression"

# ---- Add waves for debugging ----
echo "\n[WAVE] Adding signals to waveform..."
add wave -divider "Clocks_Resets"
add wave -hex sys_clk wdt_clk sys_rst_n wdt_rst_n

add wave -divider "SPI"
add wave -hex spi_sck spi_mosi spi_miso spi_cs_n

add wave -divider "Servo_PWM"
add wave -hex servo_pwm

add wave -divider "Speed_Sensor"
add wave -hex speed_pulse speed_pulse_count

add wave -divider "Buzzer_PWM"
add wave -hex buzzer_pwm

add wave -divider "UART"
add wave -hex uart_tx uart_rx

add wave -divider "GPIO"
add wave -hex gpio_io

add wave -divider "Safety"
add wave -hex shutdown_n alert_n

add wave -divider "Test_Status"
add wave -hex test_id pass_count fail_count

# ---- Run simulation ----
echo "\n[RUN] Starting simulation..."
run -all

# ---- Generate coverage reports ----
echo "\n[COVERAGE] Generating coverage reports..."

# Text report
coverage report -file $COV_RPT/coverage_summary.txt \
    -byfile -detail -noannotate -verbose

# HTML report
coverage report -html \
    -htmldir $COV_RPT/html \
    -verbose

# Detailed coverage by instance
coverage report -file $COV_RPT/coverage_by_instance.txt \
    -byinstance -detail

# ---- Coverage statistics ----
echo "\n============================================================"
echo " COVERAGE SUMMARY"
echo "============================================================"
echo " Reports written to: $COV_RPT/"
echo "   coverage_summary.txt      — Text summary"
echo "   coverage_by_instance.txt  — Per-instance breakdown"
echo "   html/index.html           — Interactive HTML report"
echo "============================================================"

# ---- Quit simulator ----
quit -sim
echo "\n[DONE] QuestaSim verification complete."
