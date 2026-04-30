/*
 * hal/gpio.h — GPIO Hardware Abstraction Layer
 * =============================================
 * Base: 0x0000_7000 | Block: 32-bit GPIO with Interrupts
 * Source: REGISTER_MAP.md §8
 */

#ifndef HAL_GPIO_H
#define HAL_GPIO_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Base Address ---- */
#define GPIO_HAL_BASE           0x00007000UL

/* ---- Register Offsets (32-bit aligned) ---- */
#define GPIO_DATA_OFFSET        0x00U
#define GPIO_DIR_OFFSET         0x04U
#define GPIO_OUT_OFFSET         0x08U
#define GPIO_IN_OFFSET          0x0CU
#define GPIO_SET_OFFSET         0x10U
#define GPIO_CLR_OFFSET         0x14U
#define GPIO_TOG_OFFSET         0x18U
#define GPIO_INT_EN_OFFSET      0x1CU
#define GPIO_INT_TYPE_OFFSET    0x20U
#define GPIO_INT_POLARITY_OFFSET 0x24U
#define GPIO_INT_STATUS_OFFSET  0x28U
#define GPIO_INT_ACK_OFFSET     0x2CU
#define GPIO_PULL_EN_OFFSET     0x30U
#define GPIO_PULL_SEL_OFFSET    0x34U
#define GPIO_DRIVE_OFFSET       0x38U
#define GPIO_SAFETY_OFFSET      0x3CU
#define GPIO_CTRL_OFFSET        0x40U

/* ---- Absolute Register Addresses ---- */
#define GPIO_DATA               (GPIO_HAL_BASE + GPIO_DATA_OFFSET)
#define GPIO_DIR                (GPIO_HAL_BASE + GPIO_DIR_OFFSET)
#define GPIO_OUT                (GPIO_HAL_BASE + GPIO_OUT_OFFSET)
#define GPIO_IN                 (GPIO_HAL_BASE + GPIO_IN_OFFSET)
#define GPIO_SET                (GPIO_HAL_BASE + GPIO_SET_OFFSET)
#define GPIO_CLR                (GPIO_HAL_BASE + GPIO_CLR_OFFSET)
#define GPIO_TOG                (GPIO_HAL_BASE + GPIO_TOG_OFFSET)
#define GPIO_INT_EN             (GPIO_HAL_BASE + GPIO_INT_EN_OFFSET)
#define GPIO_INT_TYPE           (GPIO_HAL_BASE + GPIO_INT_TYPE_OFFSET)
#define GPIO_INT_POLARITY       (GPIO_HAL_BASE + GPIO_INT_POLARITY_OFFSET)
#define GPIO_INT_STATUS         (GPIO_HAL_BASE + GPIO_INT_STATUS_OFFSET)
#define GPIO_INT_ACK            (GPIO_HAL_BASE + GPIO_INT_ACK_OFFSET)
#define GPIO_PULL_EN            (GPIO_HAL_BASE + GPIO_PULL_EN_OFFSET)
#define GPIO_PULL_SEL           (GPIO_HAL_BASE + GPIO_PULL_SEL_OFFSET)
#define GPIO_DRIVE              (GPIO_HAL_BASE + GPIO_DRIVE_OFFSET)
#define GPIO_SAFETY             (GPIO_HAL_BASE + GPIO_SAFETY_OFFSET)
#define GPIO_CTRL               (GPIO_HAL_BASE + GPIO_CTRL_OFFSET)

/* ---- GPIO_CTRL Bits ---- */
#define GPIO_CTRL_CLK_EN        (1U << 0)
#define GPIO_CTRL_SOFT_RST      (1U << 1)

/* ---- GPIO_SAFETY Bits ---- */
#define GPIO_SAFETY_LOCK_ALERT  (1U << 0)
#define GPIO_SAFETY_LOCK_SHDN_A (1U << 1)
#define GPIO_SAFETY_LOCK_SHDN_B (1U << 2)
#define GPIO_SAFETY_LOCKED      (1U << 3)

/* ---- Pin Assignments ---- */
#define GPIO_PIN_ALERT_OUT      0U
#define GPIO_PIN_SHUTDOWN_A     1U
#define GPIO_PIN_SHUTDOWN_B     2U
#define GPIO_PIN_SHUTDOWN_ACK   3U

/* ---- Inline MMIO Helpers ---- */
static inline void gpio_hal_write(uint32_t offset, uint32_t value) {
    *((volatile uint32_t *)(GPIO_HAL_BASE + offset)) = value;
}

static inline uint32_t gpio_hal_read(uint32_t offset) {
    return *((volatile uint32_t *)(GPIO_HAL_BASE + offset));
}

#ifdef __cplusplus
}
#endif

#endif /* HAL_GPIO_H */
