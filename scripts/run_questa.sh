#!/bin/bash
# ============================================================================
# run_questa.sh — QuestaSim Coverage-Driven Verification Runner
# ============================================================================
# Project: ADAS v2 — Safety-Critical RISC-V SoC
# Usage:
#   chmod +x scripts/run_questa.sh
#   ./scripts/run_questa.sh
#
# Prerequisites:
#   - Siemens QuestaSim or ModelSim DE/PE (vsim in PATH)
#   - RTL files in rtl/
#   - Testbench in tb/
#
# Coverage Types: Branch, Condition, Statement, Toggle, FSM
# Outputs:
#   coverage_report/coverage_summary.txt    — Text coverage report
#   coverage_report/coverage_by_instance.txt— Per-module coverage
#   coverage_report/html/index.html         — Interactive HTML report
#   vsim.wlf                                 — Waveform database
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "============================================================"
echo " ADAS v2 — QuestaSim Coverage-Driven Verification"
echo "============================================================"
echo " Project dir : $PROJECT_DIR"
echo ""

# Check for QuestaSim/ModelSim
if ! command -v vsim &> /dev/null; then
    if ! command -v questa &> /dev/null; then
        echo "ERROR: QuestaSim/ModelSim not found in PATH."
        echo "       Please ensure vsim or questa is installed and in PATH."
        echo ""
        echo "       Siemens QuestaSim: https://eda.sw.siemens.com/en-US/ic/questa/"
        echo "       Intel Questa (free): https://www.intel.com/content/www/us/en/software-kit/750368/intel-questa-intel-fpgas-standard-edition-software.html"
        exit 1
    fi
fi

# Clean previous results
rm -rf work vsim.wlf cov_work coverage_report transcript

# Determine simulator executable
VSIM=$(command -v vsim 2>/dev/null || command -v questa 2>/dev/null)

echo "[INFO] Using simulator: $VSIM"
echo "[INFO] Running: $VSIM -do scripts/questa_run.tcl"
echo ""

# Run QuestaSim with TCL script
$VSIM -do scripts/questa_run.tcl -c -quiet

echo ""
echo "============================================================"
echo " Verification Complete"
echo "============================================================"
echo " Coverage report: coverage_report/coverage_summary.txt"
echo " HTML report:     coverage_report/html/index.html"
echo " Waveform:        vsim.wlf"
echo "============================================================"
