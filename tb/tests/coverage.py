#!/usr/bin/env python3
"""
coverage.py — Functional Coverage Collection
===============================================
Implements functional coverage per coverage_model.md using cocotb-coverage.

Coverage bins for:
  - All FSM states (ADAS controller, AI accelerator control, SPI, safety)
  - All peripheral register accesses
  - All AI accelerator operations
  - All interrupt sources
  - Lockstep comparison results
  - Fault injection responses
  - AXI protocol operations
"""

import random
from collections import defaultdict
from typing import Dict, List, Set, Any, Optional

# Try importing cocotb-coverage; fall back to simple implementation
try:
    from cocotb_coverage.coverage import (
        CoverPoint, CoverCross, CoverCheck,
        coverage_db, Coverage, CovBin
    )
    HAS_COCOTB_COVERAGE = True
except ImportError:
    HAS_COCOTB_COVERAGE = False


# ============================================================================
# SIMPLE COVERAGE TRACKER (works without cocotb-coverage)
# ============================================================================

class CoverageBin:
    """Simple coverage bin implementation."""
    def __init__(self, name: str, bins: List[str] = None, values: List[Any] = None):
        self.name = name
        self.hits: Dict[str, int] = defaultdict(int)
        self._bin_names: List[str] = bins or []
        self.total_hits = 0

    def sample(self, value):
        key = str(value)
        self.hits[key] += 1
        self.total_hits += 1

    @property
    def coverage(self) -> float:
        if not self._bin_names:
            return 100.0 if self.total_hits > 0 else 0.0
        hit_count = sum(1 for b in self._bin_names if str(b) in self.hits)
        return (hit_count / len(self._bin_names)) * 100.0 if self._bin_names else 100.0

    def get_uncovered(self) -> List[str]:
        return [b for b in self._bin_names if str(b) not in self.hits]


class CoverageGroup:
    """Simple coverage group."""
    def __init__(self, name: str):
        self.name = name
        self.points: Dict[str, CoverageBin] = {}

    def add_point(self, name: str, bins: List[str] = None):
        self.points[name] = CoverageBin(name, bins)

    def sample(self, name: str, value):
        if name in self.points:
            self.points[name].sample(value)

    @property
    def coverage(self) -> float:
        if not self.points:
            return 100.0
        return sum(p.coverage for p in self.points.values()) / len(self.points)


class CoverageTracker:
    """Master coverage tracker for the verification campaign."""

    def __init__(self):
        self.groups: Dict[str, CoverageGroup] = {}

    def add_group(self, name: str) -> CoverageGroup:
        cg = CoverageGroup(name)
        self.groups[name] = cg
        return cg

    @property
    def coverage(self) -> float:
        if not self.groups:
            return 100.0
        return sum(g.coverage for g in self.groups.values()) / len(self.groups)

    def summary(self) -> str:
        lines = [f"\n{'='*60}",
                 f"  COVERAGE SUMMARY",
                 f"{'='*60}"]
        for name, cg in self.groups.items():
            lines.append(f"  {name}: {cg.coverage:.1f}%")
        lines.append(f"  {'─'*58}")
        lines.append(f"  TOTAL: {self.coverage:.1f}%")
        lines.append(f"{'='*60}")
        return "\n".join(lines)

    def detail_report(self) -> str:
        lines = [f"\n{'='*70}",
                 f"  COVERAGE DETAIL REPORT",
                 f"{'='*70}"]
        for gname, cg in self.groups.items():
            lines.append(f"\n  [{gname}] {cg.coverage:.1f}%")
            for pname, point in cg.points.items():
                uncovered = point.get_uncovered()
                status = "✓" if point.coverage >= 100.0 else "✗"
                lines.append(f"    {status} {pname}: {point.coverage:.1f}% "
                           f"({point.total_hits} hits)")
                if uncovered:
                    lines.append(f"       Uncovered: {uncovered}")
        return "\n".join(lines)

    def all_covered(self) -> bool:
        return self.coverage >= 100.0


# ============================================================================
# COVERAGE MODEL DEFINITIONS
# ============================================================================

def create_coverage_model() -> CoverageTracker:
    """Create the complete functional coverage model per coverage_model.md."""

    tracker = CoverageTracker()

    # --- ADAS Controller FSM Coverage ---
    cg_adas = tracker.add_group("adas_controller_fsm")
    cg_adas.add_point("adas_state", [
        "IDLE", "MONITORING", "PRE_BRAKE", "BRAKING",
        "SAFETY_CHECK", "SHUTDOWN", "FAULT"
    ])
    cg_adas.add_point("adas_state_transition", [
        "IDLE→MONITORING", "MONITORING→PRE_BRAKE", "MONITORING→BRAKING",
        "PRE_BRAKE→BRAKING", "PRE_BRAKE→IDLE",
        "BRAKING→IDLE", "BRAKING→SHUTDOWN",
        "ANY→FAULT", "FAULT→IDLE",
        "BRAKING→SAFETY_CHECK", "SAFETY_CHECK→IDLE", "SAFETY_CHECK→SHUTDOWN"
    ])
    cg_adas.add_point("object_class_seen", ["CAR", "PEDESTRIAN", "OBSTACLE", "NONE"])
    cg_adas.add_point("brake_decision", ["engaged", "not_engaged"])
    cg_adas.add_point("pwm_range", [
        "off_0.00", "min_0.30", "mid_0.30-0.65", "high_0.65-0.99", "max_1.00"
    ])
    cg_adas.add_point("buzzer_active", ["on", "off"])
    cg_adas.add_point("ttc_range", [
        "negative", "zero", "0-0.5s", "0.5-1.0s", "1.0-1.8s",
        "1.8-2.5s", "2.5-5.0s", "5.0s+", "infinite"
    ])

    # --- AI Accelerator Coverage ---
    cg_ai = tracker.add_group("ai_accelerator")
    cg_ai.add_point("ai_fsm_state", ["IDLE", "LOAD_WEIGHTS", "LOAD_INPUT", "COMPUTE", "DONE"])
    cg_ai.add_point("ai_operation_type", ["MAC", "BIAS_ADD", "RELU", "SIGMOID", "TANH", "SCALE"])
    cg_ai.add_point("ai_weight_range", [
        "all_neg", "mixed", "all_pos",
        "min_INT8", "max_INT8", "zero_weight"
    ])
    cg_ai.add_point("ai_input_range", [
        "all_neg", "mixed", "all_pos",
        "min_INT8", "max_INT8", "zero_input"
    ])
    cg_ai.add_point("ai_output_overflow", ["none", "positive", "negative", "both"])
    cg_ai.add_point("ai_interrupt", ["done", "error", "none"])

    # --- AXI Protocol Coverage ---
    cg_axi = tracker.add_group("axi_protocol")
    cg_axi.add_point("axi_write_completed", ["yes", "no"])
    cg_axi.add_point("axi_read_completed", ["yes", "no"])
    cg_axi.add_point("axi_bresp", ["OKAY"])
    cg_axi.add_point("axi_rresp", ["OKAY"])
    cg_axi.add_point("axi_address_range", [
        "0x0000_0000", "0x0000_1000", "0x0000_2000", "0x0000_3000",
        "0x0000_4000", "0x0000_5000", "0x0000_6000", "0x0000_7000",
        "0x0000_F000", "0x0000_F100"
    ])

    # --- Peripheral Coverage ---
    cg_periph = tracker.add_group("peripherals")
    cg_periph.add_point("spi_operation", ["read", "write", "idle", "error"])
    cg_periph.add_point("spi_cs_active", ["cs0", "cs1", "cs2", "cs3", "none"])
    cg_periph.add_point("servo_pwm_duty", [
        "off", "low_0.01-0.30", "mid_0.30-0.65", "high_0.65-0.99", "max_1.00"
    ])
    cg_periph.add_point("speed_sensor_pulses", ["0", "1-10", "11-100", "100+", "overflow"])
    cg_periph.add_point("buzzer_pwm", ["off", "on"])
    cg_periph.add_point("uart_operation", ["tx", "rx", "tx_rx", "idle"])
    cg_periph.add_point("gpio_direction", ["input", "output", "mixed"])
    cg_periph.add_point("gpio_value_seen", [
        "all_zeros", "all_ones", "mixed", "walking_ones", "walking_zeros"
    ])

    # --- Interrupt Coverage ---
    cg_irq = tracker.add_group("interrupts")
    cg_irq.add_point("irq_source", [
        "SPI_RX", "SPI_TX", "SPI_ERR", "SERVO_FAULT",
        "SPEED_PULSE", "SPEED_OVF", "BUZZER_DONE",
        "UART_RX", "UART_TX", "GPIO",
        "AI_DONE", "AI_ERROR", "WDT_PREWARN",
        "LOCKSTEP", "FAULT_AGG"
    ])
    cg_irq.add_point("irq_masked", ["masked", "unmasked"])

    # --- Safety Coverage ---
    cg_safety = tracker.add_group("safety")
    cg_safety.add_point("lockstep_result", ["match", "mismatch"])
    cg_safety.add_point("fault_source", [
        "lockstep", "wdt", "servo", "ai", "spi", "speed",
        "itcm_parity", "dtcm_parity", "none"
    ])
    cg_safety.add_point("fault_response", [
        "captured", "irq_asserted", "core_halted", "none"
    ])
    cg_safety.add_point("wdt_state", [
        "idle", "counting", "prewarn", "timeout", "fault"
    ])
    cg_safety.add_point("shutdown_path", ["active", "inactive"])
    cg_safety.add_point("shutdown_redundant", ["both_deasserted", "both_asserted"])

    # --- Register Coverage ---
    cg_reg = tracker.add_group("registers")
    cg_reg.add_point("register_access_type", ["read", "write", "read_back", "reserved_read"])
    cg_reg.add_point("register_reset_value", ["verified"])

    # --- Sensor Input Ranges ---
    cg_sensor = tracker.add_group("sensor_inputs")
    cg_sensor.add_point("ego_speed_range", [
        "stopped_0", "urban_1-50", "highway_51-120", "autobahn_120-300"
    ])
    cg_sensor.add_point("object_distance_range", [
        "imminent_0-10", "critical_10-30", "warning_30-60", "safe_60-200"
    ])
    cg_sensor.add_point("relative_speed_range", [
        "approaching_fast_neg100_to_neg50", "approaching_slow_neg50_to_0",
        "stationary_0", "moving_away_0_to_50", "moving_away_fast_50_to_100"
    ])

    return tracker


# ============================================================================
# COVERAGE SAMPLING HELPERS
# ============================================================================

def sample_adas_coverage(tracker: CoverageTracker, state_name: str,
                         should_brake: bool, pwm_duty: float, buzzer: bool,
                         ttc: float, obj_class: str):
    """Sample ADAS controller coverage bins."""
    cg = tracker.groups.get("adas_controller_fsm")
    if not cg:
        return
    cg.sample("adas_state", state_name)
    cg.sample("brake_decision", "engaged" if should_brake else "not_engaged")
    cg.sample("buzzer_active", "on" if buzzer else "off")
    cg.sample("object_class_seen", obj_class)

    # PWM range
    if pwm_duty < 0.01:
        cg.sample("pwm_range", "off_0.00")
    elif pwm_duty < 0.31:
        cg.sample("pwm_range", "min_0.30")
    elif pwm_duty < 0.66:
        cg.sample("pwm_range", "mid_0.30-0.65")
    elif pwm_duty < 0.99:
        cg.sample("pwm_range", "high_0.65-0.99")
    else:
        cg.sample("pwm_range", "max_1.00")

    # TTC range
    if ttc < 0:
        cg.sample("ttc_range", "negative")
    elif ttc == 0:
        cg.sample("ttc_range", "zero")
    elif ttc < 0.5:
        cg.sample("ttc_range", "0-0.5s")
    elif ttc < 1.0:
        cg.sample("ttc_range", "0.5-1.0s")
    elif ttc < 1.8:
        cg.sample("ttc_range", "1.0-1.8s")
    elif ttc < 2.5:
        cg.sample("ttc_range", "1.8-2.5s")
    elif ttc < 5.0:
        cg.sample("ttc_range", "2.5-5.0s")
    elif ttc < float('inf'):
        cg.sample("ttc_range", "5.0s+")
    else:
        cg.sample("ttc_range", "infinite")


def sample_ai_coverage(tracker: CoverageTracker, fsm_state: str,
                       operation: str, weights_all_neg: bool,
                       weights_all_pos: bool, inputs_all_neg: bool,
                       inputs_all_pos: bool, overflow: str,
                       interrupt: str):
    """Sample AI accelerator coverage bins."""
    cg = tracker.groups.get("ai_accelerator")
    if not cg:
        return
    cg.sample("ai_fsm_state", fsm_state)
    cg.sample("ai_operation_type", operation)
    cg.sample("ai_interrupt", interrupt)
    cg.sample("ai_output_overflow", overflow)

    if weights_all_neg:
        cg.sample("ai_weight_range", "all_neg")
    elif weights_all_pos:
        cg.sample("ai_weight_range", "all_pos")
    else:
        cg.sample("ai_weight_range", "mixed")

    if inputs_all_neg:
        cg.sample("ai_input_range", "all_neg")
    elif inputs_all_pos:
        cg.sample("ai_input_range", "all_pos")
    else:
        cg.sample("ai_input_range", "mixed")


def sample_safety_coverage(tracker: CoverageTracker, lockstep_match: bool,
                           fault_source: str, fault_response: str,
                           wdt_state: str, shutdown_active: bool):
    """Sample safety subsystem coverage bins."""
    cg = tracker.groups.get("safety")
    if not cg:
        return
    cg.sample("lockstep_result", "match" if lockstep_match else "mismatch")
    cg.sample("fault_source", fault_source)
    cg.sample("fault_response", fault_response)
    cg.sample("wdt_state", wdt_state)
    cg.sample("shutdown_path", "active" if shutdown_active else "inactive")


def sample_irq_coverage(tracker: CoverageTracker, irq_source: str, masked: bool):
    """Sample interrupt coverage bins."""
    cg = tracker.groups.get("interrupts")
    if not cg:
        return
    cg.sample("irq_source", irq_source)
    cg.sample("irq_masked", "masked" if masked else "unmasked")


def sample_periph_coverage(tracker: CoverageTracker, spi_op: str = None,
                           spi_cs: str = None, servo_duty: str = None,
                           speed_pulses: str = None, buzzer: str = None,
                           uart_op: str = None, gpio_dir: str = None,
                           gpio_val: str = None):
    """Sample peripheral coverage bins."""
    cg = tracker.groups.get("peripherals")
    if not cg:
        return
    if spi_op:
        cg.sample("spi_operation", spi_op)
    if spi_cs:
        cg.sample("spi_cs_active", spi_cs)
    if servo_duty:
        cg.sample("servo_pwm_duty", servo_duty)
    if speed_pulses:
        cg.sample("speed_sensor_pulses", speed_pulses)
    if buzzer:
        cg.sample("buzzer_pwm", buzzer)
    if uart_op:
        cg.sample("uart_operation", uart_op)
    if gpio_dir:
        cg.sample("gpio_direction", gpio_dir)
    if gpio_val:
        cg.sample("gpio_value_seen", gpio_val)


def sample_sensor_coverage(tracker: CoverageTracker, ego_speed: float,
                           distance: float, rel_speed: float):
    """Sample sensor input range coverage bins."""
    cg = tracker.groups.get("sensor_inputs")
    if not cg:
        return

    # Ego speed
    speed_kmh = ego_speed * 3.6
    if speed_kmh == 0:
        cg.sample("ego_speed_range", "stopped_0")
    elif speed_kmh <= 50:
        cg.sample("ego_speed_range", "urban_1-50")
    elif speed_kmh <= 120:
        cg.sample("ego_speed_range", "highway_51-120")
    else:
        cg.sample("ego_speed_range", "autobahn_120-300")

    # Object distance
    if distance <= 10:
        cg.sample("object_distance_range", "imminent_0-10")
    elif distance <= 30:
        cg.sample("object_distance_range", "critical_10-30")
    elif distance <= 60:
        cg.sample("object_distance_range", "warning_30-60")
    else:
        cg.sample("object_distance_range", "safe_60-200")

    # Relative speed
    rel_kmh = rel_speed * 3.6
    if rel_kmh < -50:
        cg.sample("relative_speed_range", "approaching_fast_neg100_to_neg50")
    elif rel_kmh < 0:
        cg.sample("relative_speed_range", "approaching_slow_neg50_to_0")
    elif rel_kmh == 0:
        cg.sample("relative_speed_range", "stationary_0")
    elif rel_kmh <= 50:
        cg.sample("relative_speed_range", "moving_away_0_to_50")
    else:
        cg.sample("relative_speed_range", "moving_away_fast_50_to_100")
