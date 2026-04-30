#!/bin/bash
# ============================================================================
# run_cocotb.sh — cocotb + Icarus Verilog Regression Runner
# ============================================================================
# Project: ADAS v2 — Safety-Critical RISC-V SoC
# Usage:
#   chmod +x scripts/run_cocotb.sh
#   ./scripts/run_cocotb.sh          # Run all tests
#   ./scripts/run_cocotb.sh safety   # Run only safety tests
#   ./scripts/run_cocotb.sh --cov    # Run with coverage
#
# Prerequisites:
#   - cocotb >= 2.0 (pip install cocotb)
#   - Icarus Verilog (iverilog / vvp)
#   - Python 3.8+
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TB_DIR="$PROJECT_DIR/tb"
RTL_DIR="$PROJECT_DIR/rtl"

# Source all RTL files
RTL_FILES=""
for f in "$RTL_DIR"/*.v; do
    RTL_FILES="$RTL_FILES $(basename "$f")"
done

cd "$PROJECT_DIR"

# Ensure cocotb is installed
if ! python3 -c "import cocotb" 2>/dev/null; then
    echo "ERROR: cocotb not installed. Run: pip install cocotb"
    exit 1
fi

# Build args
COCOTB_ARGS=""
TEST_FILTER="${1:-}"

if [ "$TEST_FILTER" = "--cov" ]; then
    COCOTB_ARGS="--cov=rtl --cov-report=term"
    TEST_FILTER=""
elif [ "$TEST_FILTER" = "--help" ] || [ "$TEST_FILTER" = "-h" ]; then
    echo "Usage: $0 [test_filter|--cov]"
    echo "  test_filter  Run tests matching pattern (e.g., safety, axi, peripheral)"
    echo "  --cov        Run with Python coverage"
    echo ""
    echo "Available test files in tb/tests/:"
    ls -1 "$TB_DIR/tests/test_"*.py 2>/dev/null | while read f; do
        echo "  $(basename "$f")"
    done
    exit 0
fi

echo "============================================================"
echo " ADAS v2 — cocotb + Icarus Verilog Regression"
echo "============================================================"
echo ""

# Set environment for cocotb
export COCOTB_REDUCED_LOG_FMT=1
export MODULE=adas_soc_tb_wrapper
export TOPLEVEL=adas_soc_tb_wrapper
export TOPLEVEL_LANG=verilog

# Run make in tb/ directory
cd "$TB_DIR"

if [ -n "$TEST_FILTER" ]; then
    echo "[INFO] Filter: tests matching '*$TEST_FILTER*'"
    pytest -v tests/ -k "$TEST_FILTER" $COCOTB_ARGS
else
    echo "[INFO] Running all tests..."
    pytest -v tests/ $COCOTB_ARGS
fi

echo ""
echo "[DONE] cocotb regression complete."
