#!/usr/bin/env python3
"""
reference_model.py — ADAS Emergency Braking Golden Reference Model
===================================================================
Golden reference model for cocotb testbench integration.

Provides:
  - ADASController: cycle-accurate state machine
  - SafetyMonitor: shadow processor model
  - ADASSystem: integrated system model
  - AI Golden Reference: 4×4 INT8 systolic array model
  - Test vector generators
"""

import math
from dataclasses import dataclass, field
from enum import IntEnum, auto
from typing import List, Tuple, Optional, Dict

# ============================================================================
# CONSTANTS
# ============================================================================

class ObjectClass(IntEnum):
    CAR        = 0
    PEDESTRIAN = 1
    OBSTACLE   = 2
    NONE       = 3

BRAKING_THRESHOLD_S = {
    ObjectClass.CAR:        1.8,
    ObjectClass.PEDESTRIAN: 2.5,
    ObjectClass.OBSTACLE:   1.2,
    ObjectClass.NONE:       float('inf'),
}

PWM_MIN_DUTY       = 0.30
PWM_MAX_DUTY       = 1.00
PWM_OFF_DUTY       = 0.00
MAX_DECEL_M_S2     = 8.5
SAFETY_TIMEOUT_MS  = 100
BUZZER_FREQ_HZ     = 2400
WARNING_MULTIPLIER = 1.3

class ADASState(IntEnum):
    IDLE           = 0
    MONITORING     = 1
    PRE_BRAKE      = 2
    BRAKING        = 3
    SAFETY_CHECK   = 4
    SHUTDOWN       = 5
    FAULT          = 6

FIXED_POINT_SCALE = 65536
FIXED_POINT_FRAC  = 16


# ============================================================================
# CORE ALGORITHM
# ============================================================================

def compute_ttc(distance_m: float, relative_speed_m_s: float) -> float:
    if distance_m < 0.0:
        return float('-inf')
    if distance_m == 0.0:
        return 0.0
    if relative_speed_m_s <= 0.0:
        if relative_speed_m_s == 0.0:
            return float('inf')
        else:
            return float('-inf')
    return distance_m / relative_speed_m_s


def compute_braking_decision(ttc_s, threshold_s, ego_speed_m_s):
    if ego_speed_m_s <= 0.0:
        return (False, PWM_OFF_DUTY, "ego_stopped")
    if ttc_s < 0.0 or math.isinf(ttc_s):
        return (False, PWM_OFF_DUTY, "no_threat")
    if ttc_s >= threshold_s:
        return (False, PWM_OFF_DUTY, "ttc_above_threshold")
    urgency = max(0.0, min(1.0, 1.0 - (ttc_s / threshold_s)))
    pwm_duty = PWM_MIN_DUTY + urgency * (PWM_MAX_DUTY - PWM_MIN_DUTY)
    return (True, pwm_duty, f"brake_urgency_{urgency:.2f}")


def should_pre_brake_warn(ttc_s, threshold_s, ego_speed_m_s=0.0):
    if ego_speed_m_s <= 0.0:
        return False
    if ttc_s <= 0.0 or math.isinf(ttc_s):
        return False
    return ttc_s < threshold_s * WARNING_MULTIPLIER


# ============================================================================
# DATA TYPES
# ============================================================================

@dataclass
class SensorFrame:
    ego_speed_m_s: float
    object_distance_m: float
    object_relative_speed_m_s: float
    object_class: ObjectClass
    timestamp_ms: int = 0

    def is_valid(self) -> bool:
        if self.object_class not in ObjectClass:
            return False
        if self.ego_speed_m_s < 0.0:
            return False
        if self.object_distance_m < -1.0:
            return False
        if abs(self.object_relative_speed_m_s) > 100.0:
            return False
        return True


@dataclass
class ADASOutput:
    state: ADASState = ADASState.IDLE
    should_brake: bool = False
    pwm_duty: float = 0.0
    buzzer_active: bool = False
    shutdown_triggered: bool = False
    ttc_s: float = float('inf')
    decision_reason: str = "idle"
    required_decel_m_s2: float = 0.0
    warning_active: bool = False


# ============================================================================
# ADAS CONTROLLER STATE MACHINE
# ============================================================================

class ADASController:
    def __init__(self):
        self.state = ADASState.IDLE
        self.consecutive_no_threat = 0
        self.consecutive_threat = 0
        self.hysteresis_count = 2

    def process_frame(self, frame: SensorFrame) -> ADASOutput:
        out = ADASOutput()

        if not frame.is_valid():
            out.state = ADASState.FAULT
            out.decision_reason = "sensor_fault"
            return out

        ttc_s = compute_ttc(frame.object_distance_m, frame.object_relative_speed_m_s)
        threshold_s = BRAKING_THRESHOLD_S[frame.object_class]
        warn = should_pre_brake_warn(ttc_s, threshold_s, frame.ego_speed_m_s)
        brake, pwm, reason = compute_braking_decision(ttc_s, threshold_s, frame.ego_speed_m_s)
        req_decel = frame.ego_speed_m_s / ttc_s if ttc_s > 0 else float('inf')

        out.ttc_s = ttc_s
        out.required_decel_m_s2 = req_decel

        if self.state == ADASState.SHUTDOWN:
            out.state = ADASState.SHUTDOWN
            out.shutdown_triggered = True
            out.decision_reason = "shutdown_hold"
            return out

        if self.state == ADASState.FAULT:
            out.state = ADASState.FAULT
            out.decision_reason = "fault_hold"
            return out

        if frame.object_class == ObjectClass.NONE:
            self.state = ADASState.IDLE
            out.state = ADASState.IDLE
            out.decision_reason = "no_object"
            return out

        threat_detected = brake or warn

        if threat_detected:
            self.consecutive_threat += 1
            self.consecutive_no_threat = 0
        else:
            self.consecutive_no_threat += 1
            self.consecutive_threat = 0

        if not threat_detected and self.consecutive_no_threat >= self.hysteresis_count:
            self.state = ADASState.IDLE
            out.state = ADASState.IDLE
            out.decision_reason = "clear"
        elif threat_detected and self.consecutive_threat < self.hysteresis_count:
            if self.state == ADASState.IDLE:
                self.state = ADASState.MONITORING
            out.state = self.state
            out.warning_active = warn
            out.decision_reason = "monitoring"
        elif threat_detected and self.consecutive_threat >= self.hysteresis_count:
            if brake:
                self.state = ADASState.BRAKING
                out.state = ADASState.BRAKING
                out.should_brake = True
                out.pwm_duty = pwm
                out.buzzer_active = True
                out.decision_reason = reason
            elif warn:
                self.state = ADASState.PRE_BRAKE
                out.state = ADASState.PRE_BRAKE
                out.warning_active = True
                out.buzzer_active = True
                out.decision_reason = "pre_brake_warning"
            else:
                self.state = ADASState.MONITORING
                out.state = ADASState.MONITORING
                out.decision_reason = "monitoring_confirmed"

        return out

    def reset(self):
        self.state = ADASState.IDLE
        self.consecutive_no_threat = 0
        self.consecutive_threat = 0


# ============================================================================
# SAFETY MONITOR
# ============================================================================

@dataclass
class SafetyMonitorState:
    monitoring: bool = False
    brake_decision_time: int = -1
    brake_engaged: bool = False
    timeout_triggered: bool = False
    frame_count: int = 0


class SafetyMonitor:
    def __init__(self, timeout_ms: int = SAFETY_TIMEOUT_MS):
        self.timeout_ms = timeout_ms
        self.state = SafetyMonitorState()

    def monitor(self, should_brake, brake_engaged, timestamp_ms):
        self.state.frame_count += 1
        if should_brake and not self.state.monitoring:
            self.state.monitoring = True
            self.state.brake_decision_time = timestamp_ms
            self.state.timeout_triggered = False
            return (False, "monitor_start")
        if not should_brake:
            self.state.monitoring = False
            self.state.brake_decision_time = -1
            self.state.brake_engaged = False
            self.state.timeout_triggered = False
            return (False, "monitor_idle")
        if self.state.monitoring:
            elapsed_ms = timestamp_ms - self.state.brake_decision_time
            if brake_engaged:
                self.state.brake_engaged = True
                if elapsed_ms <= self.timeout_ms:
                    return (False, f"brake_engaged_{elapsed_ms}ms")
                else:
                    return (False, f"brake_engaged_late_{elapsed_ms}ms")
            if elapsed_ms > self.timeout_ms:
                self.state.timeout_triggered = True
                return (True, f"SAFETY_TIMEOUT_{elapsed_ms}ms")
            return (False, f"monitor_waiting_{elapsed_ms}ms")
        return (False, "monitor_unknown")

    def reset(self):
        self.state = SafetyMonitorState()


# ============================================================================
# AI ACCELERATOR GOLDEN REFERENCE (4×4 INT8 Systolic Array)
# ============================================================================

class AIGoldenReference:
    """
    Bit-exact golden reference for the 4×4 INT8 systolic array.

    Computes: result_j = sum_i (weight[i][j] * input[i]) + bias[j]
    Followed by optional activation function and scaling.
    All arithmetic uses 32-bit accumulators matching the RTL.
    """
    ACTIVATION_NONE  = 0
    ACTIVATION_RELU  = 1
    ACTIVATION_SIGMOID = 2
    ACTIVATION_TANH  = 3

    def __init__(self):
        self.weights = [[0]*4 for _ in range(4)]
        self.inputs = [0]*4
        self.biases = [0]*4

    def set_weights(self, weight_regs: List[int]):
        """Load 4 weight registers (each 32-bit = 4 INT8 values)."""
        for row in range(4):
            reg = weight_regs[row] & 0xFFFFFFFF
            for col in range(4):
                byte_shift = col * 8
                val = (reg >> byte_shift) & 0xFF
                # Sign-extend INT8
                if val & 0x80:
                    val = val - 256
                self.weights[row][col] = val

    def set_inputs(self, input_reg: int):
        """Load input activations (32-bit = 4 INT8 values)."""
        for i in range(4):
            val = (input_reg >> (i * 8)) & 0xFF
            if val & 0x80:
                val = val - 256
            self.inputs[i] = val

    def set_biases(self, bias_0_1: int, bias_2_3: int):
        """Load biases (INT16 signed)."""
        for i in range(2):
            val = (bias_0_1 >> (i * 16)) & 0xFFFF
            if val & 0x8000:
                val = val - 65536
            self.biases[i] = val
        for i in range(2):
            val = (bias_2_3 >> (i * 16)) & 0xFFFF
            if val & 0x8000:
                val = val - 65536
            self.biases[i + 2] = val

    def compute(self, activation_fn: int = 0, scale_factor: int = 0x1000) -> List[int]:
        """
        Compute systolic array outputs.

        result[j] = SUM_i(weight[i][j] * input[i]) + bias[j]
        """
        results = [0]*4
        for j in range(4):
            acc = 0
            for i in range(4):
                acc += self.weights[i][j] * self.inputs[i]
            acc += self.biases[j]
            # Clamp to INT32
            if acc > 0x7FFFFFFF:
                acc = 0x7FFFFFFF
            elif acc < -0x80000000:
                acc = -0x80000000
            results[j] = acc

        # Activation function
        results = self._apply_activation(results, activation_fn)

        # Scale (Q8.8 fixed-point)
        results = self._apply_scale(results, scale_factor)

        return results

    def _apply_activation(self, results, fn):
        if fn == self.ACTIVATION_RELU:
            return [max(0, r) for r in results]
        elif fn == self.ACTIVATION_SIGMOID:
            # Simplified sigmoid for INT32: threshold-based
            return [0x7FFFFFFF if r > 0 else (0 if r < 0 else r) for r in results]
        elif fn == self.ACTIVATION_TANH:
            # Simplified tanh: clamp to [-1, 1] in scaled
            return [max(-2147483648, min(2147483647, r)) for r in results]
        return results

    def _apply_scale(self, results, scale_factor):
        """Apply Q8.8 scaling."""
        scale = scale_factor & 0xFFFF
        if scale == 0:
            scale = 0x1000  # default 1.0 in Q8.8
        return [(r * scale) >> 8 for r in results]


# ============================================================================
# CONSTRAINED-RANDOM STIMULUS GENERATORS
# ============================================================================

import random as _random
_rand = _random.Random(42)  # Fixed seed for reproducibility

def reset_seed(seed=42):
    global _rand
    _rand = _random.Random(seed)

def random_sensor_frame() -> SensorFrame:
    """Generate a constrained-random sensor frame."""
    ego_kmh = _rand.uniform(0, 300)
    ego_m_s = ego_kmh / 3.6
    distance = _rand.uniform(0, 200)
    rel_kmh = _rand.uniform(-100, 100)
    rel_m_s = rel_kmh / 3.6
    obj_class = ObjectClass(_rand.randint(0, 3))
    ts = _rand.randint(0, 100000)
    return SensorFrame(ego_m_s, distance, rel_m_s, obj_class, ts)

def random_weight_matrix() -> List[int]:
    """Generate random 4×4 INT8 weight matrix as 4×32-bit registers."""
    weights = []
    for row in range(4):
        reg = 0
        for col in range(4):
            val = _rand.randint(-128, 127)
            reg |= ((val & 0xFF) << (col * 8))
        weights.append(reg)
    return weights

def random_input_activations() -> int:
    """Generate random 4-element INT8 input as packed 32-bit."""
    reg = 0
    for i in range(4):
        val = _rand.randint(-128, 127)
        reg |= ((val & 0xFF) << (i * 8))
    return reg

def random_biases() -> Tuple[int, int]:
    """Generate random INT16 bias pairs."""
    b0 = _rand.randint(-32768, 32767) & 0xFFFF
    b1 = _rand.randint(-32768, 32767) & 0xFFFF
    b2 = _rand.randint(-32768, 32767) & 0xFFFF
    b3 = _rand.randint(-32768, 32767) & 0xFFFF
    return (b0 | (b1 << 16), b2 | (b3 << 16))

def generate_test_vectors(num_vectors: int) -> List[Tuple[SensorFrame, ADASOutput]]:
    """Generate N constrained-random test vectors with expected outputs."""
    vectors = []
    ctrl = ADASController()
    for _ in range(num_vectors):
        frame = random_sensor_frame()
        out = ctrl.process_frame(frame)
        vectors.append((frame, out))
    return vectors

def generate_ai_test_vectors(num_vectors: int) -> List[Dict]:
    """Generate N AI accelerator test vectors with expected outputs."""
    vectors = []
    ref = AIGoldenReference()
    for _ in range(num_vectors):
        weights = random_weight_matrix()
        inputs = random_input_activations()
        b01, b23 = random_biases()
        act_fn = _rand.randint(0, 3)
        scale = _rand.randint(0x0100, 0x7FFF)
        ref.set_weights(weights)
        ref.set_inputs(inputs)
        ref.set_biases(b01, b23)
        expected = ref.compute(act_fn, scale)
        vectors.append({
            'weights': weights,
            'inputs': inputs,
            'bias_0_1': b01,
            'bias_2_3': b23,
            'activation_fn': act_fn,
            'scale': scale,
            'expected_outputs': expected
        })
    return vectors
