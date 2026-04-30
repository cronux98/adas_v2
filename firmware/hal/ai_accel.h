/*
 * hal/ai_accel.h — AI Accelerator Hardware Abstraction Layer
 * ===========================================================
 * Base: 0x0000_1000 | Block: 4×4 INT8 Systolic Array (Weight-Stationary)
 * Source: REGISTER_MAP.md §2
 */

#ifndef HAL_AI_ACCEL_H
#define HAL_AI_ACCEL_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Base Address ---- */
#define AI_ACCEL_HAL_BASE       0x00001000UL

/* ---- Register Offsets (32-bit aligned) ---- */
#define AI_CTRL_OFFSET          0x00U
#define AI_STATUS_OFFSET        0x04U
#define AI_WEIGHT_0_OFFSET      0x08U
#define AI_WEIGHT_1_OFFSET      0x0CU
#define AI_WEIGHT_2_OFFSET      0x10U
#define AI_WEIGHT_3_OFFSET      0x14U
#define AI_INPUT_OFFSET         0x18U
#define AI_BIAS_0_1_OFFSET      0x1CU
#define AI_BIAS_2_3_OFFSET      0x20U
#define AI_OUTPUT_0_OFFSET      0x24U
#define AI_OUTPUT_1_OFFSET      0x28U
#define AI_OUTPUT_2_OFFSET      0x2CU
#define AI_OUTPUT_3_OFFSET      0x30U
#define AI_ACTIVATION_OFFSET    0x34U
#define AI_SCALE_OFFSET         0x38U
#define AI_INTR_MASK_OFFSET     0x3CU

/* ---- Absolute Register Addresses ---- */
#define AI_CTRL                 (AI_ACCEL_HAL_BASE + AI_CTRL_OFFSET)
#define AI_STATUS               (AI_ACCEL_HAL_BASE + AI_STATUS_OFFSET)
#define AI_WEIGHT_0             (AI_ACCEL_HAL_BASE + AI_WEIGHT_0_OFFSET)
#define AI_WEIGHT_1             (AI_ACCEL_HAL_BASE + AI_WEIGHT_1_OFFSET)
#define AI_WEIGHT_2             (AI_ACCEL_HAL_BASE + AI_WEIGHT_2_OFFSET)
#define AI_WEIGHT_3             (AI_ACCEL_HAL_BASE + AI_WEIGHT_3_OFFSET)
#define AI_INPUT                (AI_ACCEL_HAL_BASE + AI_INPUT_OFFSET)
#define AI_BIAS_0_1             (AI_ACCEL_HAL_BASE + AI_BIAS_0_1_OFFSET)
#define AI_BIAS_2_3             (AI_ACCEL_HAL_BASE + AI_BIAS_2_3_OFFSET)
#define AI_OUTPUT_0             (AI_ACCEL_HAL_BASE + AI_OUTPUT_0_OFFSET)
#define AI_OUTPUT_1             (AI_ACCEL_HAL_BASE + AI_OUTPUT_1_OFFSET)
#define AI_OUTPUT_2             (AI_ACCEL_HAL_BASE + AI_OUTPUT_2_OFFSET)
#define AI_OUTPUT_3             (AI_ACCEL_HAL_BASE + AI_OUTPUT_3_OFFSET)
#define AI_ACTIVATION           (AI_ACCEL_HAL_BASE + AI_ACTIVATION_OFFSET)
#define AI_SCALE                (AI_ACCEL_HAL_BASE + AI_SCALE_OFFSET)
#define AI_INTR_MASK            (AI_ACCEL_HAL_BASE + AI_INTR_MASK_OFFSET)

/* ---- AI_CTRL Bit Definitions ---- */
#define AI_CTRL_GO              (1U << 0)
#define AI_CTRL_BUSY            (1U << 1)
#define AI_CTRL_DONE            (1U << 2)
#define AI_CTRL_ERROR           (1U << 3)
#define AI_CTRL_RELU_EN         (1U << 4)
#define AI_CTRL_QUANT_EN        (1U << 5)
#define AI_CTRL_CLK_EN          (1U << 8)
#define AI_CTRL_RST             (1U << 9)

/* ---- AI_ACTIVATION Bits ---- */
#define AI_ACT_NONE             (1U << 0)
#define AI_ACT_RELU             (1U << 1)
#define AI_ACT_SIGMOID          (1U << 2)
#define AI_ACT_TANH             (1U << 3)

/* ---- AI_INTR_MASK Bits ---- */
#define AI_INTR_DONE_IE         (1U << 0)
#define AI_INTR_ERROR_IE        (1U << 1)

/* ---- AI Error Codes (from STATUS[15:8]) ---- */
#define AI_ERR_NONE             0x00U
#define AI_ERR_WEIGHT_UNDERFLOW 0x01U
#define AI_ERR_OUTPUT_OVERFLOW  0x02U
#define AI_ERR_INVALID_ACT      0x03U
#define AI_ERR_INTERNAL_FAULT   0xFFU

/* ---- Output Scaling Default (Q8.8) ---- */
#define AI_SCALE_DEFAULT        0x00001000UL

/* ---- Inline MMIO Helpers ---- */
static inline void ai_accel_hal_write(uint32_t offset, uint32_t value) {
    *((volatile uint32_t *)(AI_ACCEL_HAL_BASE + offset)) = value;
}

static inline uint32_t ai_accel_hal_read(uint32_t offset) {
    return *((volatile uint32_t *)(AI_ACCEL_HAL_BASE + offset));
}

#ifdef __cplusplus
}
#endif

#endif /* HAL_AI_ACCEL_H */
