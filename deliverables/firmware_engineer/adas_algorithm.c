/*
 * adas_algorithm.c — ADAS Emergency Braking Algorithm Implementation
 * ==================================================================
 * Project:  adas_v2 — ADAS RISC-V High-Performance SoC
 * Target:   RV32IM (bare-metal, no FPU, no libc)
 * Author:   Aiden Nakamura (firmware_engineer)
 * Version:  1.0.0
 * Date:     2026-04-29
 *
 * IMPLEMENTATION NOTES:
 *   - All arithmetic is fixed-point Q16.16. NO FLOATING-POINT.
 *   - Division uses int64_t intermediates (RV32IM M-extension supports
 *     mul/div on 32-bit; 64-bit mul/div is emulated by compiler).
 *   - The state machine is cycle-accurate with hysteresis.
 *   - Safety monitor is intentionally simple for deterministic
 *     verification against the Python golden reference.
 *
 * GOLDEN REFERENCE: reference_model.py
 *   Every behavioral decision here MUST match the Python model.
 *   Discrepancies are bugs.
 *
 * LICENSE: Proprietary — ADAS Safety-Critical Firmware
 */

#include "adas_algorithm.h"

/* ========================================================================
 * INTERNAL HELPERS
 * ======================================================================== */

/**
 * Fixed-point multiply with saturation. Returns min/max on overflow.
 */
static inline q16_t q16_mul_sat(q16_t a, q16_t b) {
    int64_t result = ((int64_t)a * (int64_t)b) >> 16;
    if (result > (int64_t)INT32_MAX)  return INT32_MAX;
    if (result < (int64_t)INT32_MIN)  return INT32_MIN;
    return (q16_t)result;
}

/**
 * Fixed-point divide with zero-guard.
 * Returns Q16_MAX (+inf) if denominator is zero and numerator > 0.
 * Returns Q16_MIN (-inf) if denominator is zero and numerator <= 0.
 */
static inline q16_t q16_div_safe(q16_t a, q16_t b) {
    if (b == 0) {
        return (a > 0) ? Q16_MAX : Q16_MIN;
    }
    /* (a << 16) / b */
    int64_t num = ((int64_t)a) << 16;
    int64_t result = num / (int64_t)b;
    if (result > (int64_t)INT32_MAX)  return INT32_MAX;
    if (result < (int64_t)INT32_MIN)  return INT32_MIN;
    return (q16_t)result;
}

/**
 * Clamp a Q16.16 value to [min, max].
 */
static inline q16_t q16_clamp(q16_t val, q16_t lo, q16_t hi) {
    if (val < lo) return lo;
    if (val > hi) return hi;
    return val;
}

/* ========================================================================
 * PUBLIC API IMPLEMENTATION
 * ======================================================================== */

void adas_init(adas_controller_t *ctrl) {
    if (ctrl == NULL) return;
    ctrl->state = ADAS_STATE_IDLE;
    ctrl->consecutive_no_threat = 0;
    ctrl->consecutive_threat = 0;
    /* Zero out last_output */
    ctrl->last_output.state = ADAS_STATE_IDLE;
    ctrl->last_output.should_brake = false;
    ctrl->last_output.pwm_duty_q16 = PWM_OFF_Q16;
    ctrl->last_output.buzzer_active = false;
    ctrl->last_output.shutdown_triggered = false;
    ctrl->last_output.ttc_q16 = Q16_MAX;
    ctrl->last_output.decision_reason = ADAS_REASON_IDLE;
    ctrl->last_output.required_decel_q16 = 0;
    ctrl->last_output.warning_active = false;
}

void adas_safety_init(adas_safety_monitor_t *sm) {
    if (sm == NULL) return;
    sm->monitoring = false;
    sm->brake_decision_time_ms = 0;
    sm->brake_engaged = false;
    sm->timeout_triggered = false;
    sm->frame_count = 0;
}

q16_t adas_threshold_for_class(adas_obj_class_t obj_class) {
    switch (obj_class) {
    case ADAS_OBJ_CAR:
        return THRESHOLD_CAR_Q16;
    case ADAS_OBJ_PEDESTRIAN:
        return THRESHOLD_PEDESTRIAN_Q16;
    case ADAS_OBJ_OBSTACLE:
        return THRESHOLD_OBSTACLE_Q16;
    case ADAS_OBJ_NONE:
    default:
        /* "Never brake" — return a very large threshold */
        return Q16_MAX;
    }
}

bool adas_validate_frame(const adas_sensor_frame_t *frame) {
    if (frame == NULL) return false;

    /* Object class must be a valid enum value */
    if (frame->object_class > ADAS_OBJ_NONE) return false;

    /* Ego speed must not be negative (speed sensor fault) */
    if (frame->ego_speed_q16 < 0) return false;

    /* Object distance sanity: not more than 1m behind sensor */
    if (frame->object_distance_q16 < INT_TO_Q16(-1)) return false;

    /* Relative speed sanity: not exceeding ±100 m/s (360 km/h) */
    if (frame->object_rel_speed_q16 > INT_TO_Q16(100) ||
        frame->object_rel_speed_q16 < -INT_TO_Q16(100)) {
        return false;
    }

    return true;
}

q16_t adas_compute_ttc(q16_t distance_q16, q16_t rel_speed_q16) {
    /* Guard: negative distance (behind us) → no collision possible */
    if (distance_q16 < 0) {
        return Q16_MIN;  /* -infinity */
    }

    /* Guard: distance zero → collision already occurred */
    if (distance_q16 == 0) {
        return Q16_ZERO;
    }

    /* Guard: relative speed zero or negative */
    if (rel_speed_q16 <= 0) {
        if (rel_speed_q16 == 0) {
            return Q16_MAX;  /* +infinity — stationary/matched speed */
        } else {
            return Q16_MIN;  /* -infinity — moving away */
        }
    }

    /* TTC = distance / relative_speed */
    return q16_div_safe(distance_q16, rel_speed_q16);
}

bool adas_pre_brake_warn(q16_t ttc_q16, q16_t threshold_q16,
                         q16_t ego_speed_q16) {
    /* Ego stopped → no threat */
    if (ego_speed_q16 <= 0) {
        return false;
    }

    /* TTC is zero, negative, or infinite → no collision possible */
    if (ttc_q16 <= 0 || ttc_q16 == Q16_MAX || ttc_q16 == Q16_MIN) {
        return false;
    }

    /* Warn when TTC < 1.3 × threshold */
    q16_t warn_threshold = q16_mul_sat(threshold_q16, WARNING_MULT_Q16);
    return (ttc_q16 < warn_threshold);
}

bool adas_braking_decision(q16_t ttc_q16, q16_t threshold_q16,
                           q16_t ego_speed_q16,
                           q16_t *pwm_out, uint8_t *reason_out) {
    /* Already stopped — no braking needed */
    if (ego_speed_q16 <= 0) {
        if (pwm_out)  *pwm_out = PWM_OFF_Q16;
        if (reason_out) *reason_out = ADAS_REASON_EGO_STOPPED;
        return false;
    }

    /* No collision threat — moving away or stationary */
    if (ttc_q16 <= 0 || ttc_q16 == Q16_MAX || ttc_q16 == Q16_MIN) {
        if (pwm_out)  *pwm_out = PWM_OFF_Q16;
        if (reason_out) *reason_out = ADAS_REASON_NO_THREAT;
        return false;
    }

    /* TTC above threshold — no braking needed */
    if (ttc_q16 >= threshold_q16) {
        if (pwm_out)  *pwm_out = PWM_OFF_Q16;
        if (reason_out) *reason_out = ADAS_REASON_TTC_ABOVE_THRESHOLD;
        return false;
    }

    /* ============================================================
     * URGENCY-BASED PWM CALCULATION
     * ============================================================
     * urgency = 1 - (TTC / threshold)    range [0, 1] in Q16
     *
     * urgency_q16 = Q16_ONE - Q16_DIV(TTC, threshold)
     *            = Q16_ONE - ((ttc << 16) / threshold)
     *
     * pwm = PWM_MIN + urgency × (PWM_MAX − PWM_MIN)
     *
     * Clamp urgency to [0, 1] to handle rounding.
     */
    q16_t urgency_q16 = Q16_ONE - q16_div_safe(ttc_q16, threshold_q16);
    urgency_q16 = q16_clamp(urgency_q16, Q16_ZERO, Q16_ONE);

    /* pwm_range = PWM_MAX − PWM_MIN */
    q16_t pwm_range_q16 = PWM_MAX_DUTY_Q16 - PWM_MIN_DUTY_Q16;
    q16_t pwm = PWM_MIN_DUTY_Q16 + q16_mul_sat(urgency_q16, pwm_range_q16);
    pwm = q16_clamp(pwm, PWM_MIN_DUTY_Q16, PWM_MAX_DUTY_Q16);

    if (pwm_out) *pwm_out = pwm;
    if (reason_out) *reason_out = ADAS_REASON_BRAKE_URGENCY;
    return true;
}

q16_t adas_required_deceleration(q16_t ego_speed_q16, q16_t ttc_q16) {
    if (ttc_q16 <= 0) {
        return Q16_MAX;  /* infinite decel needed */
    }
    return q16_div_safe(ego_speed_q16, ttc_q16);
}

adas_output_t adas_process_frame(adas_controller_t *ctrl,
                                 const adas_sensor_frame_t *frame) {
    adas_output_t out;
    /* Default-initialize output */
    out.state = ADAS_STATE_IDLE;
    out.should_brake = false;
    out.pwm_duty_q16 = PWM_OFF_Q16;
    out.buzzer_active = false;
    out.shutdown_triggered = false;
    out.ttc_q16 = Q16_MAX;
    out.decision_reason = ADAS_REASON_IDLE;
    out.required_decel_q16 = 0;
    out.warning_active = false;

    /* NULL guards */
    if (ctrl == NULL || frame == NULL) {
        out.state = ADAS_STATE_FAULT;
        out.decision_reason = ADAS_REASON_SENSOR_FAULT;
        return out;
    }

    /* ---- Sensor fault check ---- */
    if (!adas_validate_frame(frame)) {
        ctrl->state = ADAS_STATE_FAULT;
        out.state = ADAS_STATE_FAULT;
        out.decision_reason = ADAS_REASON_SENSOR_FAULT;
        ctrl->last_output = out;
        return out;
    }

    /* ---- Core computation ---- */
    q16_t ttc_q16 = adas_compute_ttc(frame->object_distance_q16,
                                      frame->object_rel_speed_q16);
    q16_t threshold_q16 = adas_threshold_for_class(
                              (adas_obj_class_t)frame->object_class);

    bool warn = adas_pre_brake_warn(ttc_q16, threshold_q16,
                                    frame->ego_speed_q16);

    q16_t pwm_q16;
    uint8_t reason;
    bool brake = adas_braking_decision(ttc_q16, threshold_q16,
                                       frame->ego_speed_q16,
                                       &pwm_q16, &reason);

    q16_t req_decel = adas_required_deceleration(frame->ego_speed_q16,
                                                  ttc_q16);

    out.ttc_q16 = ttc_q16;
    out.required_decel_q16 = req_decel;

    /* ---- SHUTDOWN hold (only manual reset exits) ---- */
    if (ctrl->state == ADAS_STATE_SHUTDOWN) {
        out.state = ADAS_STATE_SHUTDOWN;
        out.shutdown_triggered = true;
        out.decision_reason = ADAS_REASON_SHUTDOWN_HOLD;
        ctrl->last_output = out;
        return out;
    }

    /* ---- FAULT hold ---- */
    if (ctrl->state == ADAS_STATE_FAULT) {
        out.state = ADAS_STATE_FAULT;
        out.decision_reason = ADAS_REASON_FAULT_HOLD;
        ctrl->last_output = out;
        return out;
    }

    /* ---- Class NONE: immediately return IDLE ---- */
    if ((adas_obj_class_t)frame->object_class == ADAS_OBJ_NONE) {
        ctrl->state = ADAS_STATE_IDLE;
        ctrl->consecutive_threat = 0;
        ctrl->consecutive_no_threat = 0;
        out.state = ADAS_STATE_IDLE;
        out.decision_reason = ADAS_REASON_NO_OBJECT;
        ctrl->last_output = out;
        return out;
    }

    /* ---- Threat detection logic ---- */
    bool threat_detected = brake || warn;

    if (threat_detected) {
        ctrl->consecutive_threat++;
        ctrl->consecutive_no_threat = 0;
    } else {
        ctrl->consecutive_no_threat++;
        ctrl->consecutive_threat = 0;
    }

    /* ---- State transitions ---- */

    /* Clear threat → return to IDLE after hysteresis */
    if (!threat_detected &&
        ctrl->consecutive_no_threat >= HYSTERESIS_COUNT) {
        ctrl->state = ADAS_STATE_IDLE;
        out.state = ADAS_STATE_IDLE;
        out.decision_reason = ADAS_REASON_CLEAR;
    }
    /* Building threat — not yet confirmed */
    else if (threat_detected &&
             ctrl->consecutive_threat < HYSTERESIS_COUNT) {
        if (ctrl->state == ADAS_STATE_IDLE) {
            ctrl->state = ADAS_STATE_MONITORING;
        }
        out.state = ctrl->state;
        out.warning_active = warn;
        out.decision_reason = ADAS_REASON_MONITORING;
    }
    /* Confirmed threat (consecutive >= hysteresis) */
    else if (threat_detected &&
             ctrl->consecutive_threat >= HYSTERESIS_COUNT) {
        if (brake) {
            /* CRITICAL: Enter braking state */
            ctrl->state = ADAS_STATE_BRAKING;
            out.state = ADAS_STATE_BRAKING;
            out.should_brake = true;
            out.pwm_duty_q16 = pwm_q16;
            out.buzzer_active = true;
            out.decision_reason = reason;
        } else if (warn) {
            /* Pre-brake warning state */
            ctrl->state = ADAS_STATE_PRE_BRAKE;
            out.state = ADAS_STATE_PRE_BRAKE;
            out.warning_active = true;
            out.buzzer_active = true;
            out.decision_reason = ADAS_REASON_PRE_BRAKE_WARNING;
        } else {
            /* Should not reach here, but handle gracefully */
            ctrl->state = ADAS_STATE_MONITORING;
            out.state = ADAS_STATE_MONITORING;
            out.decision_reason = ADAS_REASON_MONITORING;
        }
    }
    /* No threat, still in hysteresis window — hold current state */
    else {
        out.state = ctrl->state;
        out.decision_reason = ADAS_REASON_MONITORING;
    }

    ctrl->last_output = out;
    return out;
}

bool adas_safety_monitor_tick(adas_safety_monitor_t *sm,
                              bool should_brake,
                              bool brake_engaged,
                              uint32_t timestamp_ms) {
    if (sm == NULL) return false;

    sm->frame_count++;

    /* Rising edge: brake decision just asserted */
    if (should_brake && !sm->monitoring) {
        sm->monitoring = true;
        sm->brake_decision_time_ms = timestamp_ms;
        sm->timeout_triggered = false;
        return false;
    }

    /* Steady-state: no brake decision → reset monitor */
    if (!should_brake) {
        sm->monitoring = false;
        sm->brake_decision_time_ms = 0;
        sm->brake_engaged = false;
        sm->timeout_triggered = false;
        return false;
    }

    /* Monitoring active: check engagement */
    if (sm->monitoring) {
        uint32_t elapsed_ms;
        /* Handle timer wrap-around */
        if (timestamp_ms >= sm->brake_decision_time_ms) {
            elapsed_ms = timestamp_ms - sm->brake_decision_time_ms;
        } else {
            elapsed_ms = (UINT32_MAX - sm->brake_decision_time_ms)
                         + timestamp_ms + 1;
        }

        /* Brake engaged within timeout → safe */
        if (brake_engaged) {
            sm->brake_engaged = true;
            return false;  /* no shutdown */
        }

        /* Brake not engaged, check timeout */
        if (elapsed_ms > (uint32_t)(SAFETY_TIMEOUT_CYCLES * 10)) {
            sm->timeout_triggered = true;
            return true;  /* SHUTDOWN TRIGGERED */
        }
    }

    return false;
}

void adas_reset(adas_controller_t *ctrl) {
    if (ctrl == NULL) return;
    ctrl->state = ADAS_STATE_IDLE;
    ctrl->consecutive_no_threat = 0;
    ctrl->consecutive_threat = 0;
}

void adas_safety_reset(adas_safety_monitor_t *sm) {
    if (sm == NULL) return;
    sm->monitoring = false;
    sm->brake_decision_time_ms = 0;
    sm->brake_engaged = false;
    sm->timeout_triggered = false;
    sm->frame_count = 0;
}
