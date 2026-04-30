# ADAS v2 — Regression Framework Specification

**Document:** VER-REG-001 | **Version:** 1.0 | **Date:** 2026-04-29  
**Author:** Rahul Sharma, Verification Lead  
**Framework:** pytest + cocotb + CI/CD  
**Target:** Millions of randomized cycles, zero faults, 100% coverage  

---

## Table of Contents

1. [Framework Overview](#1-framework-overview)
2. [Directory Structure and Configuration](#2-directory-structure-and-configuration)
3. [Test Organization and Discovery](#3-test-organization-and-discovery)
4. [Parallel Execution Strategy](#4-parallel-execution-strategy)
5. [Randomized Test Management](#5-randomized-test-management)
6. [Regression Execution Modes](#6-regression-execution-modes)
7. [Result Aggregation and Reporting](#7-result-aggregation-and-reporting)
8. [Coverage Flow](#8-coverage-flow)
9. [Continuous Integration Setup](#9-continuous-integration-setup)
10. [Bug Tracking Integration](#10-bug-tracking-integration)

---

## 1. Framework Overview

### 1.1 Architecture

```
┌────────────────────────────────────────────────────────────┐
│                   REGRESSION ORCHESTRATOR                   │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  pytest      │  │  Makefile    │  │  CI Script   │     │
│  │  runner      │  │  targets     │  │  (GitHub)    │     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │
│         │                 │                 │               │
│         └─────────────────┼─────────────────┘               │
│                           │                                  │
│              ┌────────────▼────────────┐                    │
│              │    Test Scheduler        │                    │
│              │  (pytest-xdist -n 8)     │                    │
│              └────────────┬────────────┘                    │
│                           │                                  │
│       ┌───────────────────┼───────────────────┐            │
│       │                   │                   │            │
│  ┌────▼─────┐       ┌────▼─────┐       ┌────▼─────┐       │
│  │ Worker 1 │       │ Worker 2 │  ...  │ Worker 8 │       │
│  │ cocotb   │       │ cocotb   │       │ cocotb   │       │
│  │ Icarus   │       │ Icarus   │       │ Icarus   │       │
│  └────┬─────┘       └────┬─────┘       └────┬─────┘       │
│       │                   │                   │            │
│       └───────────────────┼───────────────────┘            │
│                           │                                  │
│              ┌────────────▼────────────┐                    │
│              │   Result Aggregator     │                    │
│              │  (JUnit XML + HTML)     │                    │
│              └────────────┬────────────┘                    │
│                           │                                  │
│              ┌────────────▼────────────┐                    │
│              │   Coverage Merger       │                    │
│              │  (merge → report)       │                    │
│              └────────────┬────────────┘                    │
│                           │                                  │
│              ┌────────────▼────────────┐                    │
│              │   Dashboard / Notify    │                    │
│              │  (Slack/Email/Web)      │                    │
│              └─────────────────────────┘                    │
└────────────────────────────────────────────────────────────┘
```

### 1.2 Design Principles

1. **Reproducible**: Every test run logs its seed, hash, and environment for exact replay.
2. **Parallel**: Tests are independent and parallelizable across workers.
3. **Incremental**: Changed RTL → runs only affected tests (via dependency map).
4. **Comprehensive**: Nightly full regression with maximum randomization.
5. **Actionable**: Failures include waveform dump, log, and seed for immediate debug.

---

## 2. Directory Structure and Configuration

### 2.1 Complete Verification Directory Tree

```
adas_v2/
├── rtl/                           # RTL source (digital_design delivers here)
├── tb/                            # Testbench root
│   ├── pytest.ini                 # Pytest configuration
│   ├── conftest.py                # Shared fixtures
│   ├── Makefile                   # Top-level simulation make
│   ├── requirements.txt           # Python dependencies
│   ├── bfm/                       # Bus Functional Models
│   ├── scoreboard/                # Scoreboards and checkers
│   ├── golden/                    # Golden reference models
│   ├── coverage/                  # Coverage model definitions
│   ├── tests/                     # Test cases
│   │   ├── unit/                  # Module-level
│   │   ├── integration/           # Integration
│   │   ├── system/                # System-level
│   │   └── fault/                 # Fault injection
│   ├── utils/                     # Utilities
│   └── logs/                      # Output (gitignored)
│       ├── regression_results/
│       │   └── <run_id>/          # Dated run directory
│       │       ├── junit.xml      # Test results
│       │       ├── seeds.log      # Seed log
│       │       ├── coverage/      # Coverage data
│       │       ├── waves/         # Waveform dumps (failures only)
│       │       └── report.html    # HTML report
│       └── coverage_reports/
├── ci/                            # CI scripts
│   ├── run_regression.sh          # Nightly regression
│   ├── run_smoke.sh               # Smoke test (pre-commit)
│   └── check_coverage.sh          # Coverage gate check
└── deliverables/
    └── verif_lead/                # Verification documentation
```

### 2.2 pytest.ini

```ini
[pytest]
# Test discovery
testpaths = tests/
python_files = test_*.py
python_classes = Test*
python_functions = test_*

# Markers
markers =
    unit: Module-level unit tests
    integration: Integration tests
    system: System-level tests
    fault: Fault injection tests
    smoke: Quick smoke tests (pre-commit)
    directed: Directed test vectors
    random: Randomized test loops
    coverage: Tests focused on coverage closure
    slow: Tests running > 60 seconds
    nightly: Nightly regression only

# Parallel execution
addopts = -n auto --dist loadscope --timeout 300

# Logging
log_cli = true
log_cli_level = INFO
log_cli_format = %(asctime)s [%(levelname)s] %(name)s: %(message)s

# Reporting
junit_family = xunit2
```

### 2.3 conftest.py

```python
# conftest.py — Shared pytest fixtures for ADAS v2 verification

import pytest
import os
import json
import random
import time
import hashlib
from pathlib import Path

# =========================================================================
# Command-line options
# =========================================================================

def pytest_addoption(parser):
    parser.addoption("--seed", type=int, default=None,
                     help="Master random seed (default: timestamp-based)")
    parser.addoption("--cycles", type=int, default=100000,
                     help="Default random test cycles")
    parser.addoption("--waves", action="store_true",
                     help="Enable VCD/FST waveform dumping")
    parser.addoption("--waves-on-failure", action="store_true", default=True,
                     help="Dump waveforms only on test failure")
    parser.addoption("--coverage", action="store_true", default=True,
                     help="Enable coverage collection")
    parser.addoption("--run-id", type=str, default=None,
                     help="Regression run identifier")
    parser.addoption("--rtl-dir", type=str,
                     default=os.environ.get("RTL_DIR", "../rtl"),
                     help="RTL source directory")

# =========================================================================
# Session-level fixtures
# =========================================================================

@pytest.fixture(scope="session")
def run_id(request):
    """Unique identifier for this regression run."""
    rid = request.config.getoption("--run-id")
    if rid is None:
        rid = time.strftime("%Y%m%d_%H%M%S")
    return rid

@pytest.fixture(scope="session")
def master_seed(request):
    """Master seed for the regression run."""
    seed = request.config.getoption("--seed")
    if seed is None:
        seed = int(os.environ.get("SEED", int(time.time() * 1000) % (2**32)))
    random.seed(seed)
    return seed

@pytest.fixture(scope="session")
def results_dir(run_id):
    """Create and return results directory for this run."""
    d = Path(f"logs/regression_results/{run_id}")
    d.mkdir(parents=True, exist_ok=True)
    return d

@pytest.fixture(scope="session")
def seed_log(results_dir, master_seed):
    """Log the master seed."""
    log_path = results_dir / "seeds.log"
    with open(log_path, 'w') as f:
        f.write(f"master_seed: {master_seed}\n")
        f.write(f"timestamp: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"hostname: {os.uname().nodename}\n")
    return log_path

# =========================================================================
# Function-level fixtures
# =========================================================================

@pytest.fixture
def test_seed(master_seed, request):
    """Derive a deterministic per-test seed from master + test name."""
    test_name = request.node.name
    hash_input = f"{master_seed}:{test_name}"
    derived = int(hashlib.sha256(hash_input.encode()).hexdigest()[:8], 16)
    return derived

@pytest.fixture
def random_cycles(request):
    """Number of random cycles for this test."""
    return request.config.getoption("--cycles")

@pytest.fixture
def enable_waves(request):
    """Whether to enable waveform dumping."""
    if request.config.getoption("--waves"):
        return True
    return False

@pytest.fixture
def enable_coverage(request):
    """Whether to enable coverage collection."""
    return request.config.getoption("--coverage")

# =========================================================================
# Hooks
# =========================================================================

def pytest_runtest_setup(item):
    """Setup before each test."""
    # Set per-test random seed
    if hasattr(item, 'funcargs') and 'test_seed' in item.funcargs:
        seed = item.funcargs['test_seed']
        random.seed(seed)
        item.user_properties.append(('seed', seed))

def pytest_runtest_teardown(item, nextitem):
    """Teardown after each test."""
    # Copy waveforms on failure
    if hasattr(item, 'rep_call') and item.rep_call.failed:
        _copy_failure_waveforms(item)

def pytest_sessionfinish(session, exitstatus):
    """Generate aggregate report at end of session."""
    _generate_html_report(session)

# =========================================================================
# Helpers
# =========================================================================

def _copy_failure_waveforms(item):
    """Copy waveform files for failed tests to results directory."""
    # Implementation: locate .vcd/.fst files and copy to results/failures/
    pass

def _generate_html_report(session):
    """Generate HTML regression report."""
    # Parse junit.xml, coverage data, seed log
    # Generate interactive HTML dashboard
    pass
```

### 2.4 Makefile

```makefile
# Makefile — ADAS v2 Verification Regression

SHELL := /bin/bash
RTL_DIR ?= ../rtl
TB_DIR  ?= .
JOBS    ?= 8
SEED    ?= $(shell date +%s)

# Simulation tool
SIM ?= icarus  # icarus | verilator | vcs

.PHONY: help smoke unit integration system fault regression nightly coverage clean

help:
	@echo "ADAS v2 Verification Regression"
	@echo ""
	@echo "Targets:"
	@echo "  smoke        Quick smoke test (~2 min)"
	@echo "  unit         All unit tests"
	@echo "  integration  Integration tests"
	@echo "  system       System-level tests"
	@echo "  fault        Fault injection tests"
	@echo "  regression   Full regression (directed + random)"
	@echo "  nightly      Nightly: regression + 10M random cycles"
	@echo "  coverage     Generate coverage report"
	@echo "  clean        Clean build artifacts"

# =========================================================================
# Quick smoke test — runs on every git commit
# =========================================================================
smoke:
	@echo "=== SMOKE TEST ==="
	python -m pytest tests/unit/test_ai_accel.py::test_smoke -v
	python -m pytest tests/unit/test_spi_master.py::test_smoke -v
	python -m pytest tests/unit/test_servo_pwm.py::test_smoke -v
	python -m pytest tests/unit/test_safety_monitor.py::test_smoke -v
	python -m pytest tests/unit/test_window_wdt.py::test_smoke -v
	python -m pytest tests/unit/test_rv32im.py::test_smoke -v
	@echo "=== SMOKE PASSED ==="

# =========================================================================
# Unit tests — all module-level directed tests
# =========================================================================
unit:
	@echo "=== UNIT TESTS ($(JOBS) workers) ==="
	python -m pytest tests/unit/ -v --tb=short \
		-m "not random and not slow" \
		-n $(JOBS) \
		--junitxml=logs/regression_results/$$(date +%Y%m%d_%H%M%S)/junit_unit.xml
	@echo "=== UNIT TESTS COMPLETE ==="

# =========================================================================
# Integration tests
# =========================================================================
integration:
	@echo "=== INTEGRATION TESTS ==="
	python -m pytest tests/integration/ -v --tb=short \
		-n $(JOBS) \
		--junitxml=logs/regression_results/$$(date +%Y%m%d_%H%M%S)/junit_int.xml
	@echo "=== INTEGRATION TESTS COMPLETE ==="

# =========================================================================
# System tests — ADAS scenarios
# =========================================================================
system:
	@echo "=== SYSTEM TESTS ==="
	python -m pytest tests/system/ -v --tb=short \
		-n 4 \
		--junitxml=logs/regression_results/$$(date +%Y%m%d_%H%M%S)/junit_sys.xml
	@echo "=== SYSTEM TESTS COMPLETE ==="

# =========================================================================
# Fault injection tests
# =========================================================================
fault:
	@echo "=== FAULT INJECTION TESTS ==="
	python -m pytest tests/fault/ -v --tb=short \
		-n $(JOBS) \
		--timeout 600 \
		--junitxml=logs/regression_results/$$(date +%Y%m%d_%H%M%S)/junit_fault.xml
	@echo "=== FAULT INJECTION COMPLETE ==="

# =========================================================================
# Full regression (directed + random)
# =========================================================================
regression:
	@echo "=== FULL REGRESSION (seed=$(SEED)) ==="
	RUN_ID=$$(date +%Y%m%d_%H%M%S) && \
	mkdir -p logs/regression_results/$$RUN_ID && \
	python -m pytest tests/ -v --tb=short \
		-n $(JOBS) \
		--seed=$(SEED) \
		--run-id=$$RUN_ID \
		--cycles=500000 \
		--junitxml=logs/regression_results/$$RUN_ID/junit.xml \
		--html=logs/regression_results/$$RUN_ID/report.html \
		--self-contained-html 2>&1 | tee logs/regression_results/$$RUN_ID/regression.log
	@echo "=== REGRESSION COMPLETE: logs/regression_results/$$RUN_ID ==="

# =========================================================================
# Nightly regression — extended random soak
# =========================================================================
nightly:
	@echo "=== NIGHTLY REGRESSION (extended random soak) ==="
	RUN_ID=nightly_$$(date +%Y%m%d) && \
	mkdir -p logs/regression_results/$$RUN_ID && \
	python -m pytest tests/ -v --tb=line \
		-n $(JOBS) \
		--seed=$$(date +%s) \
		--run-id=$$RUN_ID \
		--cycles=2000000 \
		--timeout=7200 \
		--junitxml=logs/regression_results/$$RUN_ID/junit.xml \
		-k "not smoke" 2>&1 | tee logs/regression_results/$$RUN_ID/nightly.log
	@echo "=== NIGHTLY COMPLETE: logs/regression_results/$$RUN_ID ==="

# =========================================================================
# Coverage report generation
# =========================================================================
coverage:
	@echo "=== COVERAGE REPORT ==="
	python -m pytest tests/ -v --tb=line \
		-n $(JOBS) \
		--coverage \
		--cycles=100000 \
		-k "not slow" 2>&1 | tee logs/coverage_reports/coverage_run.log
	python utils/report_generator.py --mode coverage \
		--output logs/coverage_reports/
	@echo "=== COVERAGE REPORT: logs/coverage_reports/ ==="

# =========================================================================
# Clean
# =========================================================================
clean:
	rm -rf sim_build/
	rm -rf __pycache__/
	rm -rf tests/**/__pycache__/
	rm -rf bfm/__pycache__/
	rm -rf scoreboard/__pycache__/
	rm -rf golden/__pycache__/
	rm -rf coverage/__pycache__/
	rm -rf utils/__pycache__/
	find . -name '*.vcd' -delete
	find . -name '*.fst' -delete
	find . -name '*.pyc' -delete
	@echo "Clean complete"
```

---

## 3. Test Organization and Discovery

### 3.1 Test Categories

| Category | Marker | Typical Duration | When Run |
|----------|--------|-----------------|----------|
| Smoke | `@pytest.mark.smoke` | 1-3 min | Every git commit |
| Unit Directed | `@pytest.mark.unit` + `directed` | 5-30 sec each | Nightly + on-demand |
| Unit Random | `@pytest.mark.unit` + `random` | 1-10 min each | Nightly |
| Integration | `@pytest.mark.integration` | 1-5 min each | Nightly |
| System | `@pytest.mark.system` | 5-30 min each | Nightly |
| Fault Injection | `@pytest.mark.fault` | 1-60 min each | Weekly or per milestone |
| Coverage Closure | `@pytest.mark.coverage` | Variable | On-demand |
| Nightly Soak | `@pytest.mark.nightly` | Hours | Nightly |

### 3.2 Test Naming Convention

```
test_<module>_<category>_<description>.py

Examples:
  test_ai_accel_smoke.py           — Quick smoke test
  test_ai_accel_directed_regs.py   — Directed register access tests
  test_ai_accel_directed_matmul.py — Directed matrix multiply tests
  test_ai_accel_random.py          — Constrained random test
  test_ai_accel_coverage.py        — Coverage closure test
```

### 3.3 Test Pattern with Markers

```python
# tests/unit/test_ai_accel_random.py

import pytest
import cocotb
from cocotb.triggers import ClockCycles

@cocotb.test()
@pytest.mark.unit
@pytest.mark.random
@pytest.mark.slow  # Takes 2+ minutes
async def test_random_matmul_million_cycles(dut):
    """
    Randomized AI accelerator test: 1,000,000 cycles.
    
    Each iteration: random weights, random inputs, random activation,
    random bias. Compare against golden model.
    """
    # ... implementation ...

@cocotb.test()
@pytest.mark.unit
@pytest.mark.random
@pytest.mark.coverage
async def test_random_coverage_bins(dut):
    """
    Coverage-driven random test: targets uncovered bins only.
    """
    # ... implementation ...
```

---

## 4. Parallel Execution Strategy

### 4.1 Parallelization Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Master Process                          │
│  ┌─────────────────────────────────────────────────┐    │
│  │              pytest-xdist Scheduler               │    │
│  │         (--dist loadscope: group by module)       │    │
│  └──────────────┬──────────┬──────────┬─────────────┘    │
│                 │          │          │                    │
│  ┌──────────────▼─┐ ┌─────▼────┐ ┌──▼──────────────┐    │
│  │ Worker 1       │ │ Worker 2 │ │ Worker 8        │    │
│  │                │ │          │ │                 │    │
│  │ cocotb process │ │ cocotb   │ │ cocotb          │    │
│  │ iverilog sim   │ │ iverilog │ │ iverilog        │    │
│  │ DUT instance   │ │ DUT      │ │ DUT             │    │
│  └────────────────┘ └──────────┘ └─────────────────┘    │
│                                                           │
│  ┌─────────────────────────────────────────────────┐    │
│  │           Per-worker resource limits              │    │
│  │    CPU: 2 cores  |  RAM: 4 GB  |  Disk: 50 GB   │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

### 4.2 Parallelization Rules

| Rule | Implementation |
|------|---------------|
| No shared DUT state | Each worker gets independent simulator process |
| No file conflicts | Each worker writes to unique log directory |
| Module grouping | Tests for same module run on same worker (loadscope) |
| Coverage merging | Coverage data merged after all workers complete |
| Resource limits | `ulimit -v 4194304` (4 GB RAM per worker) |

### 4.3 Worker Management

```bash
#!/bin/bash
# ci/run_parallel_regression.sh

NUM_WORKERS=${1:-8}
RTL_DIR=${2:-../rtl}
SEED=${3:-$(date +%s)}

echo "Starting parallel regression with ${NUM_WORKERS} workers"
echo "Seed: ${SEED}"
echo "RTL: ${RTL_DIR}"

# Check resources
echo "System resources:"
free -h | head -2
nproc

# Run regression
python -m pytest tests/ \
    -v \
    -n ${NUM_WORKERS} \
    --dist loadscope \
    --seed=${SEED} \
    --rtl-dir=${RTL_DIR} \
    --timeout=1800 \
    --maxfail=10 \
    --junitxml=logs/regression_results/$(date +%Y%m%d_%H%M%S)/junit.xml \
    2>&1 | tee logs/regression_results/$(date +%Y%m%d_%H%M%S)/regression.log

exit_code=$?
echo "Regression exit code: ${exit_code}"
exit ${exit_code}
```

---

## 5. Randomized Test Management

### 5.1 Randomized Test Infrastructure

```python
# utils/random_stimulus.py

import random
import struct

class ConstrainedRandom:
    """
    Constrained random stimulus generator.
    
    Generates randomized but valid stimulus within hardware constraints.
    Supports deterministic replay via seed.
    """
    
    def __init__(self, seed=None):
        self.rng = random.Random(seed)
    
    # --- AXI Transactions ---
    def axi_random_address(self, valid_regions=None):
        """Generate random AXI address within valid peripheral regions."""
        if valid_regions is None:
            valid_regions = [
                (0x00001000, 0x00001FFF),  # AI Accelerator
                (0x00002000, 0x00002FFF),  # SPI
                (0x00003000, 0x00003FFF),  # Servo PWM
                (0x00004000, 0x00004FFF),  # Speed Sensor
                (0x00005000, 0x00005FFF),  # Buzzer PWM
                (0x00006000, 0x00006FFF),  # UART
                (0x00007000, 0x00007FFF),  # GPIO
                (0x0000F000, 0x0000F0FF),  # Safety Ctrl
                (0x0000F100, 0x0000F1FF),  # Window WDT
            ]
        region = self.rng.choice(valid_regions)
        addr = self.rng.randint(region[0], region[1])
        return addr & ~0x3  # Word-aligned
    
    def axi_random_data(self, width=32):
        """Generate random AXI data."""
        return self.rng.randint(0, (1 << width) - 1)
    
    def axi_random_strobe(self):
        """Generate random byte strobe (1-4 bytes valid)."""
        patterns = [0x1, 0x2, 0x4, 0x8, 0x3, 0xC, 0xF]
        return self.rng.choice(patterns)
    
    # --- AI Accelerator ---
    def ai_random_weight(self):
        """Random INT8 weight value."""
        return self.rng.randint(-128, 127)
    
    def ai_random_input(self):
        """Random INT8 input activation."""
        return self.rng.randint(-128, 127)
    
    def ai_random_bias(self):
        """Random INT16 bias value."""
        return self.rng.randint(-32768, 32767)
    
    def ai_random_activation(self):
        """Random activation function selection."""
        return self.rng.choice(['NONE', 'RELU', 'SIGMOID', 'TANH'])
    
    # --- SPI ---
    def spi_random_data_byte(self):
        """Random SPI data byte."""
        return self.rng.randint(0, 255)
    
    def spi_random_divider(self):
        """Random valid SPI clock divider."""
        return self.rng.choice([2, 4, 5, 8, 10, 16, 20, 25, 32, 50, 64, 100, 128, 200, 256])
    
    def spi_random_frame(self):
        """
        Generate random LIDAR sensor frame.
        Returns: (distance_cm, relative_velocity_cm_s, object_class, timestamp)
        """
        distance = self.rng.randint(0, 10000)  # 0-100 meters
        rel_vel = self.rng.randint(-3000, 3000)  # -30 to +30 m/s
        obj_class = self.rng.choice([0, 1, 2, 3])  # CAR, PED, OBS, NONE
        timestamp = self.rng.randint(0, 2**32 - 1)
        return distance, rel_vel, obj_class, timestamp
    
    # --- PWM ---
    def servo_random_duty_us(self):
        """Random servo duty cycle (500–2500 µs)."""
        return self.rng.randint(500, 2500)
    
    def buzzer_random_freq_hz(self):
        """Random buzzer frequency (1–10 kHz)."""
        return self.rng.randint(1000, 10000)
    
    # --- Sensor ---
    def speed_random_kmh(self):
        """Random vehicle speed (0-200 km/h)."""
        return self.rng.uniform(0, 200)
    
    def lidar_random_distance_m(self):
        """Random LIDAR distance (0-200 m)."""
        return self.rng.uniform(0, 200)
    
    # --- Timing ---
    def random_delay_cycles(self, min_cycles=0, max_cycles=100):
        """Random delay in clock cycles."""
        return self.rng.randint(min_cycles, max_cycles)
    
    # --- Fault Injection ---
    def random_bit_position(self, width=32):
        """Random bit position for fault injection."""
        return self.rng.randint(0, width - 1)
    
    def random_injection_cycle(self, max_cycle=10000):
        """Random injection cycle."""
        return self.rng.randint(10, max_cycle)
```

### 5.2 Randomized Test Template

```python
# Template for a randomized test

@pytest.mark.unit
@pytest.mark.random
async def test_random_spi_million_cycles(dut, test_seed, random_cycles):
    """
    SPI controller: randomized test with configurable cycle count.
    
    Usage:
        pytest test_spi_master.py::test_random_spi_million_cycles --cycles=1000000
    """
    rng = ConstrainedRandom(test_seed)
    axi = Axi4LiteMaster(dut, "s_axi_")
    spi_slave = SpiSlave(dut)
    scoreboard = DataScoreboard()
    coverage = SpiCoverage()
    
    await ClockReset(dut).init()
    await spi_slave.connect()
    
    # Configure SPI
    await axi.write(0x08, rng.spi_random_divider())  # CLKDIV
    await axi.write(0x00, 0x00401)  # CTRL: enable, master mode
    
    for i in range(random_cycles // 1000):  # ~1000 cycles per iteration
        # Randomly choose: TX byte or RX wait or config change
        action = rng.rng.choice(['tx', 'rx', 'config', 'idle'])
        
        if action == 'tx':
            tx_byte = rng.spi_random_data_byte()
            await axi.write(0x0C, tx_byte)
            spi_slave.prepare_response([~tx_byte & 0xFF])  # Loopback with inversion
        
        elif action == 'rx':
            status = await axi.read(0x04)
            if status & 0x4:  # RX not empty
                rx_byte = await axi.read(0x10)
                scoreboard.compare(f"rx_byte_{i}", rx_byte & 0xFF, ~(rx_byte >> 8) & 0xFF)
        
        elif action == 'config':
            new_div = rng.spi_random_divider()
            await axi.write(0x08, new_div)
        
        coverage.sample(...)
    
    scoreboard.report()
    assert scoreboard.all_passed()
```

---

## 6. Regression Execution Modes

### 6.1 Mode: Smoke (Pre-Commit)

```
Trigger: git commit / pre-commit hook
Scope: 6 critical smoke tests
Duration: ~2 minutes
Workers: 1 (sequential)
Output: PASS/FAIL

Tests:
  1. AI accelerator: register R/W + single matmul
  2. SPI controller: register R/W + single TX
  3. Servo PWM: enable + single period measure
  4. Safety monitor: register R/W + single fault check
  5. Window WDT: enable + kick
  6. RV32IM: basic instruction execution (ADD, LW, SW, JAL)
```

### 6.2 Mode: Unit Directed (Post-Commit / Nightly)

```
Trigger: Nightly / on-demand
Scope: All unit-directed tests for all modules
Duration: ~15 minutes
Workers: 8
Output: JUnit XML, coverage baseline

Command:
  make unit
```

### 6.3 Mode: Full Regression (Nightly)

```
Trigger: Nightly cron job
Scope: ALL tests (unit + integration + system)
Duration: ~2 hours
Workers: 8
Random cycles: 500,000 per module (default)
Output: JUnit XML, HTML report, coverage data

Command:
  make regression
```

### 6.4 Mode: Extended Soak (Weekly)

```
Trigger: Weekend cron
Scope: Extended randomized tests
Duration: 8-48 hours
Random cycles: 2,000,000+ per module, 10,000,000+ system
Output: Coverage closure report, stability metrics

Command:
  make nightly CYCLES=10000000
```

### 6.5 Mode: Fault Injection (Milestone Gate)

```
Trigger: Before P&R gate
Scope: All fault injection tests
Duration: ~2 days (full campaign)
Output: Diagnostic coverage report

Command:
  make fault
```

### 6.6 Regression Triggers and Frequency

| Trigger | Mode | Frequency |
|---------|------|-----------|
| `git commit` | Smoke | Every commit |
| `git push` | Smoke + unit directed | Every push |
| Nightly cron (2 AM) | Full regression | Daily |
| Weekend cron (Sat 00:00) | Extended soak | Weekly |
| Milestone gate | Fault injection + coverage | Per milestone |
| Pre-P&R signoff | ALL modes + manual review | Once before P&R |

---

## 7. Result Aggregation and Reporting

### 7.1 JUnit XML Output

Each regression run produces a JUnit XML file parsed by CI systems:

```xml
<!-- Example junit.xml snippet -->
<testsuite name="ADAS v2 Verification" tests="156" failures="2" errors="0" skipped="0" time="423.5">
  <testcase classname="tests.unit.test_ai_accel" name="test_directed_matmul" time="2.34">
    <properties>
      <property name="seed" value="12345678"/>
      <property name="cycles" value="100000"/>
    </properties>
  </testcase>
  <testcase classname="tests.unit.test_spi_master" name="test_random_million_cycles" time="45.2">
    <failure message="Scoreboard mismatch at cycle 45231" type="AssertionError">
      Field: rx_byte_45231
      Actual: 0xAB
      Expected: 0x54
      Delta: 0xFF
    </failure>
  </testcase>
</testsuite>
```

### 7.2 HTML Dashboard

```python
# utils/report_generator.py

def generate_html_report(results_dir, output_path):
    """
    Generate interactive HTML regression report.
    
    Includes:
    - Overall pass/fail/skip pie chart
    - Per-module test results table
    - Coverage progress bar per module
    - Failed test details with seed for reproduction
    - Execution time per test
    - Historical trend (if previous runs available)
    """
    
    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>ADAS v2 — Regression Report</title>
        <style>
            body {{ font-family: monospace; max-width: 1200px; margin: auto; padding: 20px; }}
            .pass {{ color: green; }}
            .fail {{ color: red; }}
            .coverage-bar {{ background: #ddd; height: 20px; border-radius: 3px; }}
            .coverage-fill {{ background: #4CAF50; height: 100%; border-radius: 3px; }}
            table {{ border-collapse: collapse; width: 100%; }}
            th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
            th {{ background: #f2f2f2; }}
        </style>
    </head>
    <body>
        <h1>ADAS v2 — Verification Regression Report</h1>
        <p>Run ID: {run_id} | Date: {date} | Seed: {seed}</p>
        
        <h2>Summary</h2>
        <table>
            <tr><th>Metric</th><th>Value</th></tr>
            <tr><td>Total Tests</td><td>{total}</td></tr>
            <tr><td>Passed</td><td class="pass">{passed}</td></tr>
            <tr><td>Failed</td><td class="fail">{failed}</td></tr>
            <tr><td>Total Cycles</td><td>{total_cycles:,}</td></tr>
            <tr><td>Coverage</td><td>{overall_coverage:.1f}%</td></tr>
        </table>
        
        <h2>Module Results</h2>
        <!-- Module result table -->
        
        <h2>Coverage</h2>
        <!-- Coverage bars per module -->
        
        <h2>Failures</h2>
        <!-- Failed test details with reproduction command -->
    </body>
    </html>
    """
    
    with open(output_path, 'w') as f:
        f.write(html)
```

### 7.3 Failure Reproduction

Every failure log includes:

```
============================================================
FAILED: test_random_spi_million_cycles
============================================================
Test: tests/unit/test_spi_master.py::test_random_spi_million_cycles
Seed: 987654321
Failure: Scoreboard mismatch at cycle 45231
  Field: rx_byte_45231
  Actual: 0xAB
  Expected: 0x54

TO REPRODUCE:
  SEED=987654321 pytest tests/unit/test_spi_master.py::test_random_spi_million_cycles -v --waves

Waveform: logs/regression_results/nightly_20260429/failures/test_random_spi_million_cycles.vcd
============================================================
```

---

## 8. Coverage Flow

### 8.1 Coverage Collection per Test

```python
# coverage/coverage_collector.py

class CoverageCollector:
    """
    Per-test coverage collector.
    
    Collects code coverage from simulator and functional coverage
    from Python coverage model, merges across tests.
    """
    
    def __init__(self, module_name):
        self.module = module_name
        self.code_cov = {
            'line': {},
            'branch': {},
            'fsm': {},
            'toggle': {}
        }
        self.func_cov = {}  # Per-covergroup bin hits
        self.cross_cov = {}  # Per-crossgroup bin hits
    
    def sample_func_cov(self, covergroup_name, bin_name, value=1):
        """Record a functional coverage bin hit."""
        key = f"{covergroup_name}.{bin_name}"
        self.func_cov[key] = self.func_cov.get(key, 0) + value
    
    def merge(self, other):
        """Merge another collector's data (OR for bins, MAX for counts)."""
        for metric in self.code_cov:
            for sig, val in other.code_cov[metric].items():
                self.code_cov[metric][sig] = max(
                    self.code_cov[metric].get(sig, 0),
                    val
                )
        for key, count in other.func_cov.items():
            self.func_cov[key] = self.func_cov.get(key, 0) + count
    
    def report(self):
        """Generate coverage report for this module."""
        # Code coverage
        total_lines = sum(1 for _ in self._get_all_lines())
        covered_lines = len(self.code_cov['line'])
        
        # Functional coverage
        total_bins = self._get_total_bins()
        covered_bins = sum(1 for v in self.func_cov.values() if v > 0)
        
        return {
            'line': covered_lines / total_lines * 100 if total_lines else 0,
            'functional': covered_bins / total_bins * 100 if total_bins else 0,
        }
```

### 8.2 Coverage Merging Across Runs

```bash
#!/bin/bash
# ci/merge_coverage.sh

# Merge all coverage databases from regression runs
COV_DIR="logs/coverage_reports"
MERGED_DIR="${COV_DIR}/merged_$(date +%Y%m%d)"

mkdir -p ${MERGED_DIR}

# Copy coverage data from latest regression
cp logs/regression_results/nightly_*/coverage/* ${MERGED_DIR}/

# Merge Icarus coverage
iverilog_cov_merge -o ${MERGED_DIR}/merged.cov ${MERGED_DIR}/*.cov

# Generate report
iverilog_cov_report -html ${MERGED_DIR}/report/ ${MERGED_DIR}/merged.cov

echo "Coverage report: ${MERGED_DIR}/report/index.html"
```

### 8.3 Coverage Gate Check

```python
# ci/check_coverage.py

import sys
import json

# Minimum coverage thresholds
THRESHOLDS = {
    'ai_accel_4x4': {'line': 100, 'branch': 100, 'fsm': 100, 'func': 100},
    'spi_master': {'line': 100, 'branch': 100, 'fsm': 100, 'func': 100},
    'servo_pwm': {'line': 100, 'branch': 100, 'fsm': 100, 'func': 100},
    'speed_sensor': {'line': 100, 'branch': 100, 'fsm': 100, 'func': 100},
    'buzzer_pwm': {'line': 100, 'branch': 100, 'fsm': 100, 'func': 100},
    'uart_16550': {'line': 95, 'branch': 95, 'fsm': 95, 'func': 100},
    'gpio_32bit': {'line': 100, 'branch': 100, 'fsm': 100, 'func': 100},
    'tcm_8kb': {'line': 100, 'branch': 100, 'fsm': 100, 'func': 100},
    'axi4lite_xbar': {'line': 100, 'branch': 100, 'fsm': 100, 'func': 100},
    'safety_monitor': {'line': 100, 'branch': 100, 'fsm': 100, 'func': 100},
    'window_wdt': {'line': 100, 'branch': 100, 'fsm': 100, 'func': 100},
    'redundant_shutdown': {'line': 100, 'branch': 100, 'fsm': 100, 'func': 100},
    'rv32im_core': {'line': 95, 'branch': 95, 'fsm': 95, 'func': 100},
    'adas_v2_top': {'line': 90, 'branch': 90, 'fsm': 90, 'func': 100},
}

def check_coverage(coverage_data):
    """Check coverage against thresholds. Exit non-zero if any fail."""
    failed = []
    for module, thresholds in THRESHOLDS.items():
        cov = coverage_data.get(module, {})
        for metric, threshold in thresholds.items():
            actual = cov.get(metric, 0)
            if actual < threshold:
                failed.append(f"{module}.{metric}: {actual:.1f}% < {threshold}%")
    
    if failed:
        print("COVERAGE GATE FAILED:")
        for f in failed:
            print(f"  - {f}")
        sys.exit(1)
    else:
        print("COVERAGE GATE PASSED — all modules meet thresholds")
        sys.exit(0)

if __name__ == '__main__':
    with open(sys.argv[1]) as f:
        data = json.load(f)
    check_coverage(data)
```

---

## 9. Continuous Integration Setup

### 9.1 GitHub Actions Workflow

```yaml
# .github/workflows/verification.yml

name: ADAS v2 Verification

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM UTC
  workflow_dispatch:      # Manual trigger with parameters
    inputs:
      mode:
        description: 'Regression mode'
        type: choice
        options: [smoke, unit, regression, nightly]
        default: regression
      cycles:
        description: 'Random cycles per module'
        type: string
        default: '500000'

jobs:
  smoke:
    name: Smoke Tests
    if: github.event_name == 'pull_request' || github.event_name == 'push'
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'
      
      - name: Install dependencies
        run: |
          pip install cocotb pytest pytest-xdist pytest-html
          sudo apt-get install -y iverilog
      
      - name: Run smoke tests
        run: |
          cd tb
          make smoke
      
      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: smoke-results
          path: tb/logs/

  regression:
    name: Full Regression
    if: github.event_name == 'schedule' || github.event_name == 'workflow_dispatch'
    runs-on: ubuntu-22.04-16core  # Custom runner with 16 cores
    timeout-minutes: 360
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup environment
        run: |
          pip install cocotb pytest pytest-xdist pytest-html
          sudo apt-get install -y iverilog verilator
      
      - name: Check resources
        run: |
          free -h
          nproc
          df -h .
      
      - name: Run regression
        run: |
          cd tb
          if [ "${{ github.event_name }}" == "schedule" ]; then
            make nightly
          else
            make ${{ inputs.mode }} CYCLES=${{ inputs.cycles }}
          fi
      
      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: regression-results
          path: tb/logs/regression_results/
      
      - name: Coverage gate check
        if: success()
        run: |
          cd tb
          python ci/check_coverage.py logs/coverage_reports/merged/latest.json
      
      - name: Notify on failure
        if: failure()
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "⚠️ ADAS v2 regression FAILED!\nRun: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
            }
```

### 9.2 Nightly Cron Setup

```bash
#!/bin/bash
# ci/nightly_cron.sh — intended for crontab
# 0 2 * * * /path/to/ci/nightly_cron.sh

cd /home/smdadmin/vlsi-team/shared/projects/adas_v2/tb

# Check disk space (need at least 10 GB free)
AVAILABLE=$(df -h . | tail -1 | awk '{print $4}' | sed 's/G//')
if (( $(echo "$AVAILABLE < 10" | bc -l) )); then
    echo "ERROR: Less than 10 GB free disk space ($AVAILABLE GB). Aborting."
    exit 1
fi

# Check available memory (need at least 16 GB free)
FREE_MEM=$(free -g | awk '/^Mem:/{print $7}')
if [ "$FREE_MEM" -lt 16 ]; then
    echo "ERROR: Less than 16 GB free memory (${FREE_MEM} GB). Aborting."
    exit 1
fi

# Run nightly regression
echo "=== NIGHTLY START: $(date) ==="
make nightly 2>&1 | tee logs/nightly_$(date +%Y%m%d).log
EXIT_CODE=$?

# Notify
if [ $EXIT_CODE -eq 0 ]; then
    echo "=== NIGHTLY PASSED: $(date) ==="
else
    echo "=== NIGHTLY FAILED ($EXIT_CODE): $(date) ==="
fi

exit $EXIT_CODE
```

---

## 10. Bug Tracking Integration

### 10.1 Bug Report Format

```
┌─────────────────────────────────────────────────────────────┐
│ BUG REPORT: ADAS-V2-VER-XXX                                 │
│                                                              │
│ Title: [Module] Brief description of the failure             │
│ Severity: CRITICAL / HIGH / MEDIUM / LOW                    │
│ Found By: [Test name]                                       │
│ Seed: [Reproduction seed]                                    │
│ Cycle: [Approximate cycle of first failure]                  │
│                                                              │
│ Observed:                                                    │
│   [What the RTL actually did]                                │
│                                                              │
│ Expected:                                                    │
│   [What the golden model / spec says it should do]           │
│                                                              │
│ Reproduction:                                                │
│   SEED=12345 pytest tests/unit/test_module.py -v --waves    │
│                                                              │
│ Waveform: logs/regression_results/<run>/failures/<name>.vcd │
│                                                              │
│ Assigned To: digital_design                                 │
│ Status: OPEN                                                │
└─────────────────────────────────────────────────────────────┘
```

### 10.2 Bug Lifecycle

```
OPEN ──→ ASSIGNED ──→ FIXED ──→ VERIFIED ──→ CLOSED
  │         │           │           │
  │         │           │           └── Not fixed, re-open
  │         │           └── Fix ready, re-test
  │         └── digital_design investigating
  └── verif_lead files bug
```

### 10.3 Bug Database Integration

```python
# utils/bug_reporter.py

import json
import os
from pathlib import Path

BUGS_FILE = Path("../shared/open_bugs.md")

def file_bug(module, title, severity, test_name, seed, observed, expected):
    """File a bug report and update open_bugs.md."""
    
    bug_id = _next_bug_id()
    
    bug = {
        'id': bug_id,
        'module': module,
        'title': title,
        'severity': severity,
        'found_by': test_name,
        'seed': seed,
        'observed': observed,
        'expected': expected,
        'status': 'OPEN',
        'assigned_to': 'digital_design',
        'date_found': time.strftime('%Y-%m-%d %H:%M:%S'),
    }
    
    # Save detailed bug report
    bug_file = Path(f"logs/bugs/bug_{bug_id}.json")
    bug_file.parent.mkdir(parents=True, exist_ok=True)
    with open(bug_file, 'w') as f:
        json.dump(bug, f, indent=2)
    
    # Update open_bugs.md
    _update_shared_bugs(bug)
    
    return bug_id

def _next_bug_id():
    """Auto-increment bug ID."""
    bugs_dir = Path("logs/bugs")
    existing = list(bugs_dir.glob("bug_*.json"))
    if not existing:
        return 1
    return max(int(f.stem.split('_')[1]) for f in existing) + 1

def _update_shared_bugs(bug):
    """Append bug to shared/open_bugs.md."""
    with open(BUGS_FILE, 'a') as f:
        f.write(f"\n## BUG-{bug['id']:03d}: {bug['title']}\n")
        f.write(f"- **Severity:** {bug['severity']}\n")
        f.write(f"- **Module:** {bug['module']}\n")
        f.write(f"- **Found By:** {bug['found_by']} (seed={bug['seed']})\n")
        f.write(f"- **Status:** {bug['status']}\n")
        f.write(f"- **Assigned:** {bug['assigned_to']}\n")
        f.write(f"- **Observed:** {bug['observed']}\n")
        f.write(f"- **Expected:** {bug['expected']}\n")
        f.write("\n")
```

---

## Revision History

| Version | Date | Author | Description |
|---------|------|--------|-------------|
| 1.0 | 2026-04-29 | Rahul Sharma | Initial regression framework specification |

---

*"The regression is the heartbeat of verification. Run it. Trust it. Never ship without a green dashboard."*  
*— Rahul Sharma, Verification Lead*
