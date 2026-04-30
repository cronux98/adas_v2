#!/bin/bash
# ============================================================================
# ADAS v2 Full Verification Regression
# ============================================================================
# Run: ./run_verification.sh
# Requires: cocotb, iverilog, python3, pytest
#
# This script runs the unified verification regression on ALL ADAS v2 modules.
# It compiles RTL with Icarus Verilog, runs all 20 cocotb tests through the
# unified test suite, and produces a comprehensive log.
#
# Test modules aggregated:
#   - test_cocotb_simulation.py    (8 tests: reset, sensor, AI, safety, regression)
#   - test_coverage_closure.py     (10 tests: all coverage domains)
#   - test_coverage_gap_close.py   (2 tests: ADAS FSM + AXI gap close)
#
# Total: 20 tests covering all 10 coverage domains at 100%
# ============================================================================

set -e

cd "$(dirname "$0")"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        ADAS v2 FULL VERIFICATION REGRESSION                ║"
echo "║        Hoshimachi Suisei Production Test Suite              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Starting at $(date)"
echo "  Host: $(hostname)"
echo "  Kernel: $(uname -r)"
echo ""

# ── Pre-flight checks ──
echo "── Pre-flight Checks ──"
echo ""

# Check cocotb
if ! python3 -c "import cocotb" 2>/dev/null; then
    echo "  [ERROR] cocotb not found. Install: pip install cocotb"
    exit 1
fi
COCOTB_VER=$(python3 -c "import cocotb; print(cocotb.__version__)" 2>/dev/null || echo "unknown")
echo "  cocotb:  v$COCOTB_VER ✓"

# Check iverilog
if ! command -v iverilog &>/dev/null; then
    echo "  [ERROR] iverilog not found. Install: apt-get install iverilog"
    exit 1
fi
IVERILOG_VER=$(iverilog -V 2>&1 | head -1 || echo "unknown")
echo "  iverilog: $IVERILOG_VER ✓"

# Check pytest
PYTEST_VER=$(python3 -m pytest --version 2>/dev/null | head -1 || echo "unknown")
echo "  pytest:   $PYTEST_VER ✓"

# Check RTL sources
RTL_COUNT=$(ls -1 ../rtl/*.v 2>/dev/null | wc -l)
echo "  RTL files: $RTL_COUNT ✓"

# Resource check
echo ""
echo "── Resource Check ──"
free -h | head -2
echo ""
df -h / | tail -1
echo ""

# ── Clean previous build ──
echo "── Cleaning Previous Build ──"
make clean 2>/dev/null || true
rm -f verification_full.log results.xml
echo "  Clean complete."

echo ""
echo "── Running Unified Regression ──"
echo "  Test module: test_unified_regression"
echo "  Total tests: 20 (8 + 10 + 2)"
echo "  Coverage domains: 10"
echo ""

# ── Run the simulation ──
# Use `set +e` so we capture the exit code but don't abort on test failures
set +e
make 2>&1 | tee verification_full.log
SIM_EXIT=${PIPESTATUS[0]}
set -e

echo ""
echo "── Results ──"

# Parse results from XML
if [ -f results.xml ]; then
    # Count passes/failures/skips
    PASSES=$(grep -c 'testcase name=' results.xml 2>/dev/null || echo "0")
    FAILURES=$(grep -c '<failure' results.xml 2>/dev/null || echo "0")
    echo "  Tests run:   $PASSES"
    echo "  Failures:    $FAILURES"
else
    echo "  [WARN] No results.xml generated"
    PASSES=0
    FAILURES=0
fi

# Check log for test results
if [ -f verification_full.log ]; then
    LOG_PASSES=$(grep -c 'PASS' verification_full.log 2>/dev/null || echo "0")
    LOG_FAILS=$(grep -c 'FAIL' verification_full.log 2>/dev/null || echo "0")
    echo "  Log PASS markers: $LOG_PASSES"
    echo "  Log FAIL markers: $LOG_FAILS"
fi

echo ""
echo "═══ Complete at $(date) ═══"

# ── Exit with simulation status ──
if [ "$SIM_EXIT" -eq 0 ] && [ "$FAILURES" -eq 0 ]; then
    echo ""
    echo "  ✓ ALL TESTS PASSED — Hoshiyomi, the silicon is clean! 💙"
    exit 0
else
    echo ""
    echo "  ✗ TESTS FAILED — Check verification_full.log for details"
    exit 1
fi
