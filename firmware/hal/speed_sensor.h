/*
 * hal/speed_sensor.h — Speed Sensor Hardware Abstraction Layer
 * =============================================================
 * Base: 0x0000_4000 | Block: Wheel Speed Pulse Counter with 64-bit Timestamp
 * Source: REGISTER_MAP.md §5
 */

#ifndef HAL_SPEED_SENSOR_H
#define HAL_SPEED_SENSOR_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Base Address ---- */
#define SPEED_HAL_BASE          0x00004000UL

/* ---- Register Offsets (32-bit aligned) ---- */
#define SPEED_CTRL_OFFSET       0x00U
#define SPEED_STATUS_OFFSET     0x04U
#define SPEED_COUNT_OFFSET      0x08U
#define SPEED_TIMESTAMP_L_OFFSET 0x0CU
#define SPEED_TIMESTAMP_H_OFFSET 0x10U
#define SPEED_PERIOD_L_OFFSET   0x14U
#define SPEED_PERIOD_H_OFFSET   0x18U
#define SPEED_STUCK_TIMEOUT_OFFSET 0x1CU
#define SPEED_CAPTURE_COUNT_OFFSET 0x20U
#define SPEED_INTR_MASK_OFFSET  0x24U
#define SPEED_INTR_STATUS_OFFSET 0x28U
#define SPEED_COUNT_MAX_OFFSET  0x2CU

/* ---- Absolute Register Addresses ---- */
#define SPEED_CTRL              (SPEED_HAL_BASE + SPEED_CTRL_OFFSET)
#define SPEED_STATUS            (SPEED_HAL_BASE + SPEED_STATUS_OFFSET)
#define SPEED_COUNT             (SPEED_HAL_BASE + SPEED_COUNT_OFFSET)
#define SPEED_TIMESTAMP_L       (SPEED_HAL_BASE + SPEED_TIMESTAMP_L_OFFSET)
#define SPEED_TIMESTAMP_H       (SPEED_HAL_BASE + SPEED_TIMESTAMP_H_OFFSET)
#define SPEED_PERIOD_L          (SPEED_HAL_BASE + SPEED_PERIOD_L_OFFSET)
#define SPEED_PERIOD_H          (SPEED_HAL_BASE + SPEED_PERIOD_H_OFFSET)
#define SPEED_STUCK_TIMEOUT     (SPEED_HAL_BASE + SPEED_STUCK_TIMEOUT_OFFSET)
#define SPEED_CAPTURE_COUNT     (SPEED_HAL_BASE + SPEED_CAPTURE_COUNT_OFFSET)
#define SPEED_INTR_MASK         (SPEED_HAL_BASE + SPEED_INTR_MASK_OFFSET)
#define SPEED_INTR_STATUS       (SPEED_HAL_BASE + SPEED_INTR_STATUS_OFFSET)
#define SPEED_COUNT_MAX         (SPEED_HAL_BASE + SPEED_COUNT_MAX_OFFSET)

/* ---- SPEED_CTRL Bits ---- */
#define SPEED_CTRL_ENABLE       (1U << 0)
#define SPEED_CTRL_CLR_COUNT    (1U << 1)
#define SPEED_CTRL_CLR_TIMESTAMP (1U << 2)
#define SPEED_CTRL_STUCK_DET_EN (1U << 3)
#define SPEED_CTRL_STUCK_ACTION (1U << 4)
#define SPEED_CTRL_CLK_EN       (1U << 8)
#define SPEED_CTRL_SOFT_RST     (1U << 9)

/* ---- SPEED_STATUS Bits ---- */
#define SPEED_STAT_PULSE_DETECTED (1U << 0)
#define SPEED_STAT_SENSOR_STUCK (1U << 1)
#define SPEED_STAT_COUNT_OVF    (1U << 2)

/* ---- Default Stuck Timeout ---- */
#define SPEED_STUCK_TIMEOUT_DEFAULT 0x0000FFFFUL

/* ---- Inline MMIO Helpers ---- */
static inline void speed_hal_write(uint32_t offset, uint32_t value) {
    *((volatile uint32_t *)(SPEED_HAL_BASE + offset)) = value;
}

static inline uint32_t speed_hal_read(uint32_t offset) {
    return *((volatile uint32_t *)(SPEED_HAL_BASE + offset));
}

#ifdef __cplusplus
}
#endif

#endif /* HAL_SPEED_SENSOR_H */
