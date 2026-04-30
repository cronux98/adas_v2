/*
 * adas_algorithm.h — ADAS Emergency Braking Algorithm Header
 * ==========================================================
 * Project:  adas_v2 — ADAS RISC-V High-Performance SoC
 * Target:   RV32IM (bare-metal, no FPU, no libc)
 * Author:   Aiden Nakamura (firmware_engineer)
 * Version:  1.0.0
 * Date:     2026-04-29
 *
 * This header defines the public API for the ADAS emergency braking
 * algorithm. All arithmetic uses Q16.16 fixed-point to avoid FPU
 * dependency. The golden reference is reference_model.py.
 *
 * INTEGRATION NOTES:
 *   - Call adas_init() once at boot.
 *   - Call adas_process_frame() on each sensor interrupt (~10ms).
 *   - Read adas_get_output() for brake/buzzer/shutdown signals.
 *   - The safety monitor ISR must call adas_safety_monitor_tick()
 *     with the brake_engaged feedback signal.
 *
 * LICENSE: Proprietary — ADAS Safety-Critical Firmware
 */

#ifndef ADAS_ALGORITHM_H
#define ADAS_ALGORITHM_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================
 * FIXED-POINT ARITHMETIC (Q16.16)
 * ========================================================================
 *
 * Format:  sign (1 bit) | integer (15 bits) | fractional (16 bits)
 * Range:   -32768.0 to +32767.99998
 * Resolution: ~0.000015
 *
 * Conversion:  float_to_q16(x)  = (int32_t)(x * 65536.0 + 0.5)
 *              q16_to_float(x)  = (float)x / 65536.0
 *
 * Macros below use integer arithmetic only (no float literals).
 * RV32IM provides M extension for multiply/divide.
 */
typedef int32_t q16_t;

#define Q16_ONE         ((q16_t)65536)       /* 1.0 in Q16.16 */
#define Q16_HALF        ((q16_t)32768)       /* 0.5 */
#define Q16_ZERO        ((q16_t)0)
#define Q16_MAX         ((q16_t)0x7FFFFFFF)  /* +infinity sentinel */
#define Q16_MIN         ((q16_t)0x80000000)  /* -infinity sentinel */

/* Fixed-point multiply: (a * b) >> 16. Uses int64 intermediate to avoid overflow. */
#define Q16_MUL(a, b)   ((q16_t)(((int64_t)(a) * (int64_t)(b)) >> 16))

/* Fixed-point divide: (a << 16) / b.  Uses int64 intermediate for precision. */
#define Q16_DIV(a, b)   ((q16_t)((((int64_t)(a)) << 16) / (int64_t)(b)))

/* Convert integer to Q16.16 (uses multiply to avoid UB on negative left-shift) */
#define INT_TO_Q16(i)   ((q16_t)((int32_t)(i) * 65536))

/* ========================================================================
 * CONSTANTS (Q16.16 format)
 * ======================================================================== */

/* Braking thresholds (seconds TTC) — precomputed Q16.16 values */
#define THRESHOLD_CAR_Q16         ((q16_t)117965)    /* 1.8000 * 65536 */
#define THRESHOLD_PEDESTRIAN_Q16  ((q16_t)163840)    /* 2.5000 * 65536 */
#define THRESHOLD_OBSTACLE_Q16    ((q16_t)78643)     /* 1.2000 * 65536 */

/* Warning multiplier: 1.3× braking threshold */
#define WARNING_MULT_Q16          ((q16_t)85197)     /* 1.3000 * 65536 */

/* PWM duty cycle limits (Q16.16, range 0.0 - 1.0) */
#define PWM_MIN_DUTY_Q16          ((q16_t)19661)     /* 0.30 * 65536 */
#define PWM_MAX_DUTY_Q16          ((q16_t)65536)     /* 1.00 * 65536 */
#define PWM_OFF_Q16               ((q16_t)0)

/* Maximum deceleration (m/s²) */
#define MAX_DECEL_Q16             ((q16_t)557056)    /* 8.5 * 65536 */

/* Safety monitor timeout (milliseconds) */
#define SAFETY_TIMEOUT_CYCLES     10                  /* 100ms / 10ms_per_cycle */

/* Hysteresis: number of consecutive threat frames before braking */
#define HYSTERESIS_COUNT          2

/* ========================================================================
 * ENUMERATIONS
 * ======================================================================== */

/** Object classification (matches AI accelerator output encoding). */
typedef enum {
    ADAS_OBJ_CAR        = 0,
    ADAS_OBJ_PEDESTRIAN = 1,
    ADAS_OBJ_OBSTACLE   = 2,
    ADAS_OBJ_NONE       = 3
} adas_obj_class_t;

/** ADAS controller state machine states. */
typedef enum {
    ADAS_STATE_IDLE          = 0,
    ADAS_STATE_MONITORING    = 1,
    ADAS_STATE_PRE_BRAKE     = 2,
    ADAS_STATE_BRAKING       = 3,
    ADAS_STATE_SAFETY_CHECK  = 4,
    ADAS_STATE_SHUTDOWN      = 5,
    ADAS_STATE_FAULT         = 6
} adas_state_t;

/* ========================================================================
 * DATA STRUCTURES
 * ======================================================================== */

/** One complete sensor reading (arrives every ~10ms). */
typedef struct {
    q16_t  ego_speed_q16;            /* m/s, Q16.16 */
    q16_t  object_distance_q16;      /* m, Q16.16 */
    q16_t  object_rel_speed_q16;     /* m/s, Q16.16 (positive = closing) */
    uint8_t object_class;            /* adas_obj_class_t */
    uint32_t timestamp_ms;           /* system monotonic time in ms */
} adas_sensor_frame_t;

/** Output signals from the ADAS controller (one per sensor frame). */
typedef struct {
    adas_state_t state;
    bool    should_brake;
    q16_t   pwm_duty_q16;            /* Q16.16, 0.0 - 1.0 */
    bool    buzzer_active;
    bool    shutdown_triggered;
    q16_t   ttc_q16;                 /* seconds, Q16.16 */
    uint8_t decision_reason;         /* reason code (see below) */
    q16_t   required_decel_q16;      /* m/s², Q16.16 */
    bool    warning_active;
} adas_output_t;

/* Decision reason codes (for logging/diagnostics) */
#define ADAS_REASON_IDLE                0
#define ADAS_REASON_EGO_STOPPED         1
#define ADAS_REASON_NO_THREAT           2
#define ADAS_REASON_TTC_ABOVE_THRESHOLD 3
#define ADAS_REASON_BRAKE_URGENCY       4
#define ADAS_REASON_CLEAR               5
#define ADAS_REASON_MONITORING          6
#define ADAS_REASON_NO_OBJECT           7
#define ADAS_REASON_SENSOR_FAULT        8
#define ADAS_REASON_SHUTDOWN_HOLD       9
#define ADAS_REASON_FAULT_HOLD         10
#define ADAS_REASON_PRE_BRAKE_WARNING  11

/* Safety monitor status codes */
#define SAFETY_IDLE              0
#define SAFETY_MONITOR_START     1
#define SAFETY_BRAKE_ENGAGED     2
#define SAFETY_BRAKE_ENGAGED_LATE 3
#define SAFETY_MONITOR_WAITING   4
#define SAFETY_TIMEOUT           5

/* ========================================================================
 * SAFETY MONITOR STATE
 * ======================================================================== */

typedef struct {
    bool     monitoring;
    uint32_t brake_decision_time_ms;
    bool     brake_engaged;
    bool     timeout_triggered;
    uint32_t frame_count;
} adas_safety_monitor_t;

/* ========================================================================
 * CONTROLLER STATE (opaque — access via API)
 * ======================================================================== */

typedef struct {
    adas_state_t state;
    uint8_t consecutive_no_threat;
    uint8_t consecutive_threat;
    adas_output_t last_output;
} adas_controller_t;

/* ========================================================================
 * PUBLIC API
 * ======================================================================== */

/**
 * Initialize the ADAS controller. Must be called once at boot.
 *
 * @param ctrl  Pointer to uninitialized controller struct.
 */
void adas_init(adas_controller_t *ctrl);

/**
 * Initialize the safety monitor.
 *
 * @param sm  Pointer to uninitialized safety monitor struct.
 */
void adas_safety_init(adas_safety_monitor_t *sm);

/**
 * Process one sensor frame through the ADAS state machine.
 *
 * This is the main entry point. Called from the sensor ISR
 * at ~10ms intervals.
 *
 * @param ctrl   Initialized controller.
 * @param frame  Current sensor readings (all values Q16.16).
 * @return       Output signals for this cycle.
 */
adas_output_t adas_process_frame(adas_controller_t *ctrl,
                                 const adas_sensor_frame_t *frame);

/**
 * Run one iteration of the safety monitor.
 *
 * This must be called from a timer ISR or the main loop
 * independently of adas_process_frame, to provide true
 * redundant monitoring.
 *
 * @param sm              Initialized safety monitor.
 * @param should_brake    Brake decision from primary controller.
 * @param brake_engaged   Feedback from brake servo position sensor.
 * @param timestamp_ms    Current system time in ms.
 * @return                true if shutdown triggered (safety violation).
 */
bool adas_safety_monitor_tick(adas_safety_monitor_t *sm,
                              bool should_brake,
                              bool brake_engaged,
                              uint32_t timestamp_ms);

/**
 * Reset the controller to IDLE (e.g., after manual override or
 * shutdown recovery).
 */
void adas_reset(adas_controller_t *ctrl);

/**
 * Reset the safety monitor.
 */
void adas_safety_reset(adas_safety_monitor_t *sm);

/**
 * Compute Time-To-Collision (TTC) in Q16.16 format.
 *
 * TTC = distance / relative_speed
 *
 * Edge cases:
 *   - relative_speed <= 0:  returns Q16_MAX (+inf) if zero,
 *                            Q16_MIN (-inf) if negative.
 *   - distance <= 0:        returns Q16_MIN (behind sensor).
 *   - distance == 0:        returns 0 (collision already happened).
 *
 * @param distance_q16     Distance in meters, Q16.16.
 * @param rel_speed_q16    Relative speed in m/s, Q16.16 (positive = closing).
 * @return                 TTC in seconds, Q16.16.
 */
q16_t adas_compute_ttc(q16_t distance_q16, q16_t rel_speed_q16);

/**
 * Determine whether to brake and at what PWM duty cycle.
 *
 * @param ttc_q16          Time to collision, Q16.16.
 * @param threshold_q16    Braking threshold for object class, Q16.16.
 * @param ego_speed_q16    Ego vehicle speed, Q16.16.
 * @param pwm_out          [out] PWM duty cycle, Q16.16 (0.0 - 1.0).
 * @param reason_out       [out] Decision reason code.
 * @return                 true if brake should be asserted.
 */
bool adas_braking_decision(q16_t ttc_q16, q16_t threshold_q16,
                           q16_t ego_speed_q16,
                           q16_t *pwm_out, uint8_t *reason_out);

/**
 * Compute required deceleration to stop within available TTC.
 *
 * @param ego_speed_q16    Ego speed, Q16.16.
 * @param ttc_q16          TTC, Q16.16.
 * @return                 Required deceleration in m/s², Q16.16.
 */
q16_t adas_required_deceleration(q16_t ego_speed_q16, q16_t ttc_q16);

/**
 * Check if pre-brake warning should be active.
 *
 * @param ttc_q16          TTC, Q16.16.
 * @param threshold_q16    Braking threshold, Q16.16.
 * @param ego_speed_q16    Ego speed, Q16.16.
 * @return                 true if warning should be active.
 */
bool adas_pre_brake_warn(q16_t ttc_q16, q16_t threshold_q16,
                         q16_t ego_speed_q16);

/**
 * Validate sensor frame for physically impossible values.
 *
 * @param frame  Sensor frame to validate.
 * @return       true if the frame is valid.
 */
bool adas_validate_frame(const adas_sensor_frame_t *frame);

/**
 * Get the braking threshold for a given object class.
 *
 * @param obj_class  Object class.
 * @return           Threshold TTC in seconds, Q16.16.
 */
q16_t adas_threshold_for_class(adas_obj_class_t obj_class);

#ifdef __cplusplus
}
#endif

#endif /* ADAS_ALGORITHM_H */
