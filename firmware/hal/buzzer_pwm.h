/*
 * hal/buzzer_pwm.h — Buzzer PWM Hardware Abstraction Layer
 * =========================================================
 * Base: 0x0000_5000 | Block: Audible Alert Buzzer PWM
 * Source: REGISTER_MAP.md §6
 */

#ifndef HAL_BUZZER_PWM_H
#define HAL_BUZZER_PWM_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Base Address ---- */
#define BUZZER_HAL_BASE         0x00005000UL

/* ---- Register Offsets (32-bit aligned) ---- */
#define BUZZER_CTRL_OFFSET      0x00U
#define BUZZER_PERIOD_OFFSET    0x04U
#define BUZZER_DUTY_OFFSET      0x08U
#define BUZZER_BURST_ON_OFFSET  0x0CU
#define BUZZER_BURST_OFF_OFFSET 0x10U
#define BUZZER_BURST_COUNT_OFFSET 0x14U
#define BUZZER_STATUS_OFFSET    0x18U
#define BUZZER_INTR_MASK_OFFSET 0x1CU
#define BUZZER_INTR_STATUS_OFFSET 0x20U

/* ---- Absolute Register Addresses ---- */
#define BUZZER_CTRL             (BUZZER_HAL_BASE + BUZZER_CTRL_OFFSET)
#define BUZZER_PERIOD           (BUZZER_HAL_BASE + BUZZER_PERIOD_OFFSET)
#define BUZZER_DUTY             (BUZZER_HAL_BASE + BUZZER_DUTY_OFFSET)
#define BUZZER_BURST_ON         (BUZZER_HAL_BASE + BUZZER_BURST_ON_OFFSET)
#define BUZZER_BURST_OFF        (BUZZER_HAL_BASE + BUZZER_BURST_OFF_OFFSET)
#define BUZZER_BURST_COUNT      (BUZZER_HAL_BASE + BUZZER_BURST_COUNT_OFFSET)
#define BUZZER_STATUS           (BUZZER_HAL_BASE + BUZZER_STATUS_OFFSET)
#define BUZZER_INTR_MASK        (BUZZER_HAL_BASE + BUZZER_INTR_MASK_OFFSET)
#define BUZZER_INTR_STATUS      (BUZZER_HAL_BASE + BUZZER_INTR_STATUS_OFFSET)

/* ---- BUZZER_CTRL Bits ---- */
#define BUZZER_CTRL_ENABLE      (1U << 0)
#define BUZZER_CTRL_BURST_EN    (1U << 1)
#define BUZZER_CTRL_INVERT      (1U << 2)
#define BUZZER_CTRL_CLK_EN      (1U << 8)
#define BUZZER_CTRL_SOFT_RST    (1U << 9)

/* ---- Tone Frequencies in sys_clk cycles @ 100 MHz ---- */
#define BUZZER_TONE_1KHZ        100000UL
#define BUZZER_TONE_2KHZ        50000UL
#define BUZZER_TONE_4KHZ        25000UL
#define BUZZER_TONE_8KHZ        12500UL
#define BUZZER_PERIOD_DEFAULT   10000UL

/* ---- Inline MMIO Helpers ---- */
static inline void buzzer_hal_write(uint32_t offset, uint32_t value) {
    *((volatile uint32_t *)(BUZZER_HAL_BASE + offset)) = value;
}

static inline uint32_t buzzer_hal_read(uint32_t offset) {
    return *((volatile uint32_t *)(BUZZER_HAL_BASE + offset));
}

#ifdef __cplusplus
}
#endif

#endif /* HAL_BUZZER_PWM_H */
