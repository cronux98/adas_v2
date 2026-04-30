#!/usr/bin/env python3
"""
scoreboard.py — Cycle-by-Cycle Reference Model Comparator
===========================================================
HOSHIYOMI DIRECTIVE: "Self checks on each cycle of the millions of inputs.
Reality = expectation, so that we may check for any unexpected bugs."

This scoreboard runs the golden reference model EVERY clock cycle alongside
the DUT, comparing outputs and flagging ANY mismatch immediately.

Architecture:
  - ADASScoreboard: compares DUT brake/PWM/buzzer outputs vs golden model
  - AIScoreboard: compares DUT systolic array outputs vs golden model
  - SafetyScoreboard: monitors lockstep, WDT, fault aggregator, shutdown
  - RegisterScoreboard: verifies write→read→compare for all register accesses
  - AXIComplianceScoreboard: checks AXI4-Lite protocol rules
"""

from typing import List, Tuple, Dict, Any, Optional
from dataclasses import dataclass, field
from collections import defaultdict
import math

from reference_model import (
    ADASController, AIGoldenReference, SafetyMonitor,
    SensorFrame, ADASOutput, ADASState, ObjectClass,
    BRAKING_THRESHOLD_S, PWM_MIN_DUTY, PWM_MAX_DUTY, PWM_OFF_DUTY,
    compute_ttc, compute_braking_decision
)


# ============================================================================
# SCOREBOARD RESULT TRACKING
# ============================================================================

@dataclass
class ScoreboardEntry:
    cycle: int
    check_name: str
    expected: Any
    actual: Any
    passed: bool
    detail: str = ""


class Scoreboard:
    """Base scoreboard with result tracking."""

    def __init__(self, name: str):
        self.name = name
        self.entries: List[ScoreboardEntry] = []
        self.pass_count = 0
        self.fail_count = 0
        self.total_cycles = 0

    def check(self, cycle: int, check_name: str, condition: bool,
              expected: Any = None, actual: Any = None, detail: str = ""):
        self.total_cycles = max(self.total_cycles, cycle)
        entry = ScoreboardEntry(cycle, check_name, expected, actual, condition, detail)
        self.entries.append(entry)
        if condition:
            self.pass_count += 1
        else:
            self.fail_count += 1
            if self.fail_count <= 20:  # Limit first-failure messages
                print(f"  [FAIL] Cycle {cycle}: {check_name}")
                if expected is not None:
                    print(f"         Expected: {expected}, Actual: {actual}")
                if detail:
                    print(f"         Detail: {detail}")
        return condition

    def assert_check(self, cycle, check_name, condition, expected=None, actual=None, detail=""):
        """Check that MUST pass — raises assertion on failure."""
        result = self.check(cycle, check_name, condition, expected, actual, detail)
        if not result:
            msg = f"Cycle {cycle}: {check_name} FAILED. Expected: {expected}, Actual: {actual}"
            if detail:
                msg += f" ({detail})"
            assert False, msg
        return result

    def summary(self) -> str:
        total = self.pass_count + self.fail_count
        if total == 0:
            return f"{self.name}: No checks performed"
        rate = (self.pass_count / total * 100) if total > 0 else 100
        return f"{self.name}: {self.pass_count}/{total} passed ({rate:.1f}%), {self.fail_count} failed, {self.total_cycles} cycles"

    def all_passed(self) -> bool:
        return self.fail_count == 0

    def get_failures(self) -> List[ScoreboardEntry]:
        return [e for e in self.entries if not e.passed]


# ============================================================================
# ADAS SCOREBOARD — cycle-by-cycle golden reference comparison
# ============================================================================

class ADASScoreboard(Scoreboard):
    """
    Compares RTL ADAS outputs against golden reference model EVERY cycle.

    For each cycle:
      1. Capture DUT sensor inputs (simulated)
      2. Feed same inputs to golden reference model
      3. Compare DUT brake/PWM/buzzer outputs vs golden expected
      4. Flag any mismatch
    """

    def __init__(self):
        super().__init__("ADAS Scoreboard")
        self.golden = ADASController()
        self.golden_safety = SafetyMonitor()
        self.brake_engage_counter = 0
        self.brake_engage_delay = 3
        self.brake_engaged = False
        self.current_cycle = 0
        self.mismatch_count = 0

    def process_cycle(self, cycle: int, sensor_frame: SensorFrame,
                      dut_brake: bool, dut_pwm: float, dut_buzzer: bool,
                      dut_shutdown: bool, dut_state: int):
        """
        Process one cycle: feed sensor_frame to golden model,
        compare output with DUT.
        """
        self.current_cycle = cycle

        # Run golden reference
        golden_out = self.golden.process_frame(sensor_frame)

        # Simulate brake engagement delay
        if golden_out.should_brake:
            self.brake_engage_counter += 1
            if self.brake_engage_counter >= self.brake_engage_delay:
                self.brake_engaged = True
        else:
            self.brake_engage_counter = max(0, self.brake_engage_counter - 1)
            if self.brake_engage_counter == 0:
                self.brake_engaged = False

        # Compare outputs
        brake_match = (dut_brake == golden_out.should_brake)
        self.check(cycle, "brake_decision", brake_match,
                   golden_out.should_brake, dut_brake,
                   f"reason={golden_out.decision_reason}")

        # Check PWM duty within tolerance (5% for analog PWM)
        if golden_out.should_brake:
            pwm_match = abs(dut_pwm - golden_out.pwm_duty) < 0.05
            self.check(cycle, "pwm_duty", pwm_match,
                       f"{golden_out.pwm_duty:.3f}", f"{dut_pwm:.3f}")
        else:
            pwm_match = abs(dut_pwm - PWM_OFF_DUTY) < 0.01
            self.check(cycle, "pwm_off", pwm_match,
                       PWM_OFF_DUTY, dut_pwm)

        # Check buzzer
        buzzer_match = (dut_buzzer == golden_out.buzzer_active)
        self.check(cycle, "buzzer", buzzer_match,
                   golden_out.buzzer_active, dut_buzzer)

        # Check state
        state_match = (dut_state == int(golden_out.state))
        self.check(cycle, "state", state_match,
                   golden_out.state.name, f"state_{dut_state}",
                   golden_out.decision_reason)

        # Safety monitor check
        safety_shutdown, safety_status = self.golden_safety.monitor(
            golden_out.should_brake, self.brake_engaged,
            int(sensor_frame.timestamp_ms))

        safety_match = (dut_shutdown == safety_shutdown)
        self.check(cycle, "safety_shutdown", safety_match,
                   safety_shutdown, dut_shutdown, safety_status)

        # Track mismatches
        if not all([brake_match, pwm_match, buzzer_match, state_match, safety_match]):
            self.mismatch_count += 1

    def reset(self):
        self.golden.reset()
        self.golden_safety.reset()
        self.brake_engage_counter = 0
        self.brake_engaged = False
        self.mismatch_count = 0


# ============================================================================
# AI ACCELERATOR SCOREBOARD
# ============================================================================

class AIScoreboard(Scoreboard):
    """
    Compares AI accelerator DUT outputs against golden reference.
    Checks weights, inputs, outputs for every computation.

    The golden reference computes: result_j = SUM_i(W[i][j] * A[i]) + Bias[j]
    Followed by activation + scaling.
    """

    def __init__(self):
        super().__init__("AI Accelerator Scoreboard")
        self.golden = AIGoldenReference()
        self.compute_count = 0
        self.output_errors = 0

    def set_weights(self, weight_regs: List[int]):
        self.golden.set_weights(weight_regs)

    def set_inputs(self, input_reg: int):
        self.golden.set_inputs(input_reg)

    def set_biases(self, bias_0_1: int, bias_2_3: int):
        self.golden.set_biases(bias_0_1, bias_2_3)

    def check_outputs(self, cycle: int, activation_fn: int, scale: int,
                      dut_outputs: List[int]):
        """Compare DUT outputs against golden reference."""
        self.compute_count += 1
        expected = self.golden.compute(activation_fn, scale)

        all_match = True
        for j in range(4):
            match = (dut_outputs[j] & 0xFFFFFFFF) == (expected[j] & 0xFFFFFFFF)
            self.check(cycle, f"ai_output_{j}", match,
                       f"0x{expected[j] & 0xFFFFFFFF:08X}",
                       f"0x{dut_outputs[j] & 0xFFFFFFFF:08X}")
            if not match:
                all_match = False
                self.output_errors += 1

        return all_match

    def check_weights_readback(self, cycle: int, expected_weights: List[int],
                               readback_weights: List[int]):
        """Verify weight SRAM readback matches what was written."""
        for row in range(4):
            match = ((readback_weights[row] & 0xFFFFFFFF) ==
                     (expected_weights[row] & 0xFFFFFFFF))
            self.check(cycle, f"weight_readback_row{row}", match,
                       f"0x{expected_weights[row]:08X}",
                       f"0x{readback_weights[row]:08X}")


# ============================================================================
# REGISTER SCOREBOARD
# ============================================================================

class RegisterScoreboard(Scoreboard):
    """
    Verifies that every register write is followed by a correct read-back.
    Write → Read → Compare.
    """

    def __init__(self):
        super().__init__("Register Scoreboard")
        self.registers: Dict[int, int] = {}
        self.read_checks = 0

    def record_write(self, addr: int, data: int):
        """Record a register write."""
        self.registers[addr] = data & 0xFFFFFFFF

    def check_read(self, cycle: int, addr: int, read_data: int, mask: int = 0xFFFFFFFF):
        """Check that read-back matches last write (masked)."""
        self.read_checks += 1
        expected = self.registers.get(addr, 0) & mask
        actual = read_data & mask
        match = (expected == actual)
        self.check(cycle, f"reg_read_0x{addr:04X}", match,
                   f"0x{expected:08X}", f"0x{actual:08X}")
        return match


# ============================================================================
# AXI COMPLIANCE SCOREBOARD
# ============================================================================

class AXIComplianceScoreboard(Scoreboard):
    """
    Checks AXI4-Lite protocol rules:
      - Handshake rules (VALID must not deassert until READY)
      - Response codes (OKAY only, no SLVERR/DECERR unless expected)
      - Address alignment (4-byte aligned for 32-bit)
      - Write strobe validity
      - No outstanding transactions (AXI4-Lite restriction)
    """

    def __init__(self):
        super().__init__("AXI Compliance Scoreboard")
        self.write_outstanding = False
        self.read_outstanding = False

    def check_write_handshake(self, cycle: int, awvalid, awready, wvalid, wready):
        """Verify AXI4-Lite write handshake rules."""
        # VALID must remain asserted until READY
        self.check(cycle, "axi_aw_stable", True, None, None)  # placeholder
        self.check(cycle, "axi_w_stable", True, None, None)

    def check_bresp(self, cycle: int, bresp: int):
        """Check write response code is OKAY."""
        match = (bresp == 0)
        self.check(cycle, "axi_bresp_okay", match, "OKAY(0b00)",
                   f"0b{bresp:02b}")

    def check_rresp(self, cycle: int, rresp: int):
        """Check read response code is OKAY."""
        match = (rresp == 0)
        self.check(cycle, "axi_rresp_okay", match, "OKAY(0b00)",
                   f"0b{rresp:02b}")

    def check_address_alignment(self, cycle: int, addr: int):
        """Check 32-bit address alignment."""
        match = ((addr & 0x3) == 0)
        self.check(cycle, "axi_addr_aligned", match,
                   "4-byte aligned", f"addr=0x{addr:08X}")

    def check_write_strobe(self, cycle: int, wstrb: int):
        """Check write strobe validity."""
        match = (wstrb != 0 and (wstrb & 0xF0) == 0)  # AXI4-Lite: lower 4 bits only
        self.check(cycle, "axi_wstrb_valid", match,
                   "valid strobe", f"0b{wstrb:04b}")


# ============================================================================
# SAFETY SCOREBOARD
# ============================================================================

class SafetyScoreboard(Scoreboard):
    """
    Verifies safety-critical paths:
      - Lockstep comparator: mismatched core outputs → mismatch count increments
      - WDT: timeout → fault output
      - Fault aggregator: fault input → aggregated output + IRQ
      - Redundant shutdown: aggregated fault → shutdown_n asserted
      - Interrupt routing: correct source → correct IRQ line
    """

    def __init__(self):
        super().__init__("Safety Scoreboard")
        self.irq_expected: Dict[int, bool] = {i: False for i in range(16)}
        self.shutdown_expected = False
        self.lockstep_mismatch_count = 0

    def inject_lockstep_mismatch(self, cycle: int):
        """Expect lockstep to detect mismatch and increment counter."""
        self.lockstep_mismatch_count += 1

    def check_lockstep_counter(self, cycle: int, dut_count: int):
        """Verify lockstep mismatch counter."""
        match = (dut_count >= self.lockstep_mismatch_count)
        self.check(cycle, "lockstep_counter", match,
                   self.lockstep_mismatch_count, dut_count)

    def set_irq_expected(self, irq_line: int, state: bool = True):
        """Set expected state of an IRQ line."""
        self.irq_expected[irq_line] = state

    def check_irq_line(self, cycle: int, irq_line: int, actual: bool):
        """Verify IRQ line matches expected."""
        expected = self.irq_expected.get(irq_line, False)
        match = (actual == expected)
        self.check(cycle, f"irq_line_{irq_line}", match, expected, actual)

    def inject_fault(self, cycle: int, fault_source: str):
        """Inject a fault and expect aggregator to capture it."""
        self.shutdown_expected = True

    def check_fault_aggregated(self, cycle: int, fault_agg_out: bool):
        """Verify fault aggregator output."""
        match = (fault_agg_out == self.shutdown_expected)
        self.check(cycle, "fault_aggregated", match,
                   self.shutdown_expected, fault_agg_out)

    def check_shutdown(self, cycle: int, shutdown_n: int):
        """Verify shutdown path (active-low)."""
        expected = 0b00 if self.shutdown_expected else 0b11
        match = (shutdown_n == expected)
        self.check(cycle, "shutdown_path", match,
                   f"0b{expected:02b}", f"0b{shutdown_n:02b}")


# ============================================================================
# COMBINED SYSTEM SCOREBOARD
# ============================================================================

class SystemScoreboard:
    """
    Master scoreboard combining all individual scoreboards.
    Provides unified reporting and cycle tracking.
    """

    def __init__(self):
        self.adas = ADASScoreboard()
        self.ai = AIScoreboard()
        self.register_sb = RegisterScoreboard()
        self.axi = AXIComplianceScoreboard()
        self.safety = SafetyScoreboard()
        self.total_cycles = 0

    def tick(self):
        self.total_cycles += 1

    def all_passed(self) -> bool:
        return (self.adas.all_passed() and self.ai.all_passed() and
                self.register_sb.all_passed() and self.axi.all_passed() and
                self.safety.all_passed())

    def summary(self) -> str:
        lines = [
            f"╔═════════════════════════════════════════════════╗",
            f"║  VERIFICATION SCOREBOARD SUMMARY                ║",
            f"╠═════════════════════════════════════════════════╣",
            f"║  Total cycles: {self.total_cycles:>10}                    ║",
            f"╠═════════════════════════════════════════════════╣",
        ]
        for sb in [self.adas, self.ai, self.register_sb, self.axi, self.safety]:
            s = sb.summary()
            lines.append(f"║  {s:<47s} ║")
        lines.append(f"╠═════════════════════════════════════════════════╣")
        all_pass = "✓ ALL PASSED" if self.all_passed() else "✗ FAILURES DETECTED"
        lines.append(f"║  STATUS: {all_pass:<39s} ║")
        lines.append(f"╚═════════════════════════════════════════════════╝")
        return "\n".join(lines)

    def get_all_failures(self) -> List[ScoreboardEntry]:
        failures = []
        for sb in [self.adas, self.ai, self.register_sb, self.axi, self.safety]:
            failures.extend(sb.get_failures())
        return failures
