#!/usr/bin/env python3
"""
conftest.py — Pytest fixtures and cocotb configuration
=======================================================
Provides shared fixtures for all ADAS v2 verification tests.
"""

import os
import sys
from dataclasses import dataclass

import pytest

# Add test directory to path for imports
sys.path.insert(0, os.path.dirname(__file__))

# cocotb runner is not available in cocotb 2.0.1
# Tests are run via Makefile, not pytest runner

# Project paths
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
RTL_DIR = os.path.join(PROJECT_ROOT, "rtl")
DELIVERABLES_DIR = os.path.join(PROJECT_ROOT, "deliverables")
TB_DIR = os.path.join(PROJECT_ROOT, "tb")
TESTS_DIR = os.path.join(TB_DIR, "tests")
SIM_BUILD_DIR = os.path.join(TB_DIR, "sim_build")

# RTL source files for each DUT
RTL_FILES_ALL = sorted([
    os.path.join(RTL_DIR, f) for f in os.listdir(RTL_DIR)
    if f.endswith('.v')
]) if os.path.isdir(RTL_DIR) else []

RTL_FILES_AI_ACCEL = [
    os.path.join(RTL_DIR, f) for f in [
        'axi4_lite_decode.v', 'control_fsm.v', 'sram_buffer.v',
        'systolic_array.v', 'mac_pe.v', 'result_buffer.v',
        'ai_accelerator_top.v'
    ] if os.path.exists(os.path.join(RTL_DIR, f))
]

RTL_FILES_SOC = RTL_FILES_ALL  # All files for top-level

RTL_FILES_SAFETY = [
    os.path.join(RTL_DIR, f) for f in [
        'lockstep_comparator.v', 'fault_aggregator.v',
        'redundant_shutdown.v', 'wdt.v'
    ] if os.path.exists(os.path.join(RTL_DIR, f))
]


@pytest.fixture(scope="session")
def project_root():
    """Return the project root directory."""
    return PROJECT_ROOT


@pytest.fixture(scope="session")
def rtl_dir():
    """Return the RTL source directory."""
    return RTL_DIR


@dataclass
class SimConfig:
    """Simulation configuration for a test."""
    module: str           # Top-level module name
    toplevel: str         # Verilog top-level module
    verilog_sources: list # List of Verilog source files
    includes: list = None
    parameters: dict = None
    extra_args: list = None

    def __post_init__(self):
        if self.includes is None:
            self.includes = []
        if self.parameters is None:
            self.parameters = {}
        if self.extra_args is None:
            self.extra_args = []


def get_sim_config(dut_name: str) -> SimConfig:
    """Get simulation configuration for a specific DUT."""
    configs = {
        'ai_accel_4x4': SimConfig(
            module='ai_accel_4x4',
            toplevel='ai_accel_4x4',
            verilog_sources=RTL_FILES_AI_ACCEL,
        ),
        'adas_soc_top': SimConfig(
            module='adas_soc_top',
            toplevel='adas_soc_top',
            verilog_sources=RTL_FILES_SOC,
            extra_args=['-g2012'],
        ),
        'spi_controller': SimConfig(
            module='spi_controller',
            toplevel='spi_controller',
            verilog_sources=[os.path.join(RTL_DIR, 'spi_controller.v')],
        ),
        'servo_pwm': SimConfig(
            module='servo_pwm',
            toplevel='servo_pwm',
            verilog_sources=[os.path.join(RTL_DIR, 'servo_pwm.v')],
        ),
        'speed_sensor': SimConfig(
            module='speed_sensor',
            toplevel='speed_sensor',
            verilog_sources=[os.path.join(RTL_DIR, 'speed_sensor.v')],
        ),
        'buzzer_pwm': SimConfig(
            module='buzzer_pwm',
            toplevel='buzzer_pwm',
            verilog_sources=[os.path.join(RTL_DIR, 'buzzer_pwm.v')],
        ),
        'gpio': SimConfig(
            module='gpio',
            toplevel='gpio',
            verilog_sources=[os.path.join(RTL_DIR, 'gpio.v')],
        ),
        'uart': SimConfig(
            module='uart',
            toplevel='uart',
            verilog_sources=[os.path.join(RTL_DIR, 'uart.v')],
        ),
        'lockstep_comparator': SimConfig(
            module='lockstep_comparator',
            toplevel='lockstep_comparator',
            verilog_sources=[os.path.join(RTL_DIR, 'lockstep_comparator.v')],
        ),
        'fault_aggregator': SimConfig(
            module='fault_aggregator',
            toplevel='fault_aggregator',
            verilog_sources=[os.path.join(RTL_DIR, 'fault_aggregator.v')],
        ),
        'wdt': SimConfig(
            module='wdt',
            toplevel='wdt',
            verilog_sources=[os.path.join(RTL_DIR, 'wdt.v')],
        ),
        'redundant_shutdown': SimConfig(
            module='redundant_shutdown',
            toplevel='redundant_shutdown',
            verilog_sources=[os.path.join(RTL_DIR, 'redundant_shutdown.v')],
        ),
    }
    return configs.get(dut_name, SimConfig(
        module=dut_name,
        toplevel=dut_name,
        verilog_sources=RTL_FILES_ALL,
    ))



