/*
 * hal/servo_pwm.h — Servo PWM Controller Hardware Abstraction Layer
 * ==================================================================
 * Base: 0x0000_3000 | Block: Braking Actuator PWM
 * Source: REGISTER_MAP.md §4
 */

#ifndef HAL_SERVO_PWM_H
#define HAL_SERVO_PWM_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Base Address ---- */
#define SERVO_HAL_BASE          0x00003000UL

/* ---- Register Offsets (32-bit aligned) ---- */
#define SERVO_CTRL_OFFSET       0x00U
#define SERVO_PERIOD_OFFSET     0x04U
#define SERVO_DUTY_OFFSET       0x08U
#define SERVO_SAFE_DUTY_OFFSET  0x0CU
#define SERVO_STATUS_OFFSET     0x10U
#define SERVO_FAULT_LIMIT_OFFSET 0x14U
#define SERVO_INTR_MASK_OFFSET  0x18U
#define SERVO_INTR_STATUS_OFFSET 0x1CU
#define SERVO_DUTY_US_OFFSET    0x20U

/* ---- Absolute Register Addresses ---- */
#define SERVO_CTRL              (SERVO_HAL_BASE + SERVO_CTRL_OFFSET)
#define SERVO_PERIOD            (SERVO_HAL_BASE + SERVO_PERIOD_OFFSET)
#define SERVO_DUTY              (SERVO_HAL_BASE + SERVO_DUTY_OFFSET)
#define SERVO_SAFE_DUTY         (SERVO_HAL_BASE + SERVO_SAFE_DUTY_OFFSET)
#define SERVO_STATUS            (SERVO_HAL_BASE + SERVO_STATUS_OFFSET)
#define SERVO_FAULT_LIMIT       (SERVO_HAL_BASE + SERVO_FAULT_LIMIT_OFFSET)
#define SERVO_INTR_MASK         (SERVO_HAL_BASE + SERVO_INTR_MASK_OFFSET)
#define SERVO_INTR_STATUS       (SERVO_HAL_BASE + SERVO_INTR_STATUS_OFFSET)
#define SERVO_DUTY_US           (SERVO_HAL_BASE + SERVO_DUTY_US_OFFSET)

/* ---- SERVO_CTRL Bits ---- */
#define SERVO_CTRL_ENABLE       (1U << 0)
#define SERVO_CTRL_SAFE_MODE    (1U << 1)
#define SERVO_CTRL_US_MODE      (1U << 2)
#define SERVO_CTRL_FAULT_EN     (1U << 3)
#define SERVO_CTRL_FAULT_ACTION (1U << 4)
#define SERVO_CTRL_CLK_EN       (1U << 8)
#define SERVO_CTRL_SOFT_RST     (1U << 9)

/* ---- SERVO_STATUS Bits ---- */
#define SERVO_STAT_RUNNING      (1U << 0)
#define SERVO_STAT_AT_SAFE      (1U << 1)
#define SERVO_STAT_FAULT        (1U << 2)
#define SERVO_STAT_FAULT_LATCHED (1U << 3)

/* ---- SERVO_INTR Bits ---- */
#define SERVO_INTR_FAULT        (1U << 0)
#define SERVO_INTR_PERIOD_DONE  (1U << 1)

/* ---- Pulse Widths in sys_clk cycles @ 100 MHz ---- */
#define SERVO_POS_MIN_CYCLES    50000U
#define SERVO_POS_NEUTRAL_CYCLES 150000U
#define SERVO_POS_MAX_CYCLES    250000U
#define SERVO_PERIOD_20MS_CYCLES 2000000UL
#define SERVO_PERIOD_DEFAULT    2000000UL

/* ---- Pulse Widths in microseconds (US_MODE) ---- */
#define SERVO_US_MIN            500U
#define SERVO_US_NEUTRAL        1500U
#define SERVO_US_MAX            2500U

/* ---- Inline MMIO Helpers ---- */
static inline void servo_hal_write(uint32_t offset, uint32_t value) {
    *((volatile uint32_t *)(SERVO_HAL_BASE + offset)) = value;
}

static inline uint32_t servo_hal_read(uint32_t offset) {
    return *((volatile uint32_t *)(SERVO_HAL_BASE + offset));
}

#ifdef __cplusplus
}
#endif

#endif /* HAL_SERVO_PWM_H */
