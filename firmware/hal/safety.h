/*
 * hal/safety.h — Safety Control Hardware Abstraction Layer
 * =========================================================
 * Base: 0x0000_F000 | Block: Safety Monitor (Lockstep + Fault Aggregator)
 * Source: REGISTER_MAP.md §9
 *
 * SAFETY-CRITICAL: Software-initiated reset via SAFETY_RESET_CTRL requires
 * writing magic key 0xA5 to SAFETY_SCRATCH first.
 */

#ifndef HAL_SAFETY_H
#define HAL_SAFETY_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Base Address ---- */
#define SAFETY_HAL_BASE         0x0000F000UL

/* ---- Register Offsets (32-bit aligned) ---- */
#define SAFETY_CTRL_OFFSET              0x00U
#define SAFETY_STATUS_OFFSET            0x04U
#define SAFETY_FAULT_MASK_OFFSET        0x08U
#define SAFETY_FAULT_STATUS_OFFSET      0x0CU
#define SAFETY_FAULT_COUNT_OFFSET       0x10U
#define SAFETY_LOCKSTEP_CTRL_OFFSET     0x14U
#define SAFETY_LOCKSTEP_MASK_OFFSET     0x18U
#define SAFETY_LOCKSTEP_MISMATCH_OFFSET 0x1CU
#define SAFETY_LOCKSTEP_LAST_PC_OFFSET  0x20U
#define SAFETY_LOCKSTEP_LAST_OUT_OFFSET 0x24U
#define SAFETY_LOCKSTEP_LAST_EXP_OFFSET 0x28U
#define SAFETY_SCRATCH_OFFSET           0x2CU
#define SAFETY_INTR_MASK_OFFSET         0x30U
#define SAFETY_INTR_STATUS_OFFSET       0x34U
#define SAFETY_RESET_CTRL_OFFSET        0x38U
#define SAFETY_ID_OFFSET                0x3CU

/* ---- Absolute Register Addresses ---- */
#define SAFETY_CTRL              (SAFETY_HAL_BASE + SAFETY_CTRL_OFFSET)
#define SAFETY_STATUS            (SAFETY_HAL_BASE + SAFETY_STATUS_OFFSET)
#define SAFETY_FAULT_MASK        (SAFETY_HAL_BASE + SAFETY_FAULT_MASK_OFFSET)
#define SAFETY_FAULT_STATUS      (SAFETY_HAL_BASE + SAFETY_FAULT_STATUS_OFFSET)
#define SAFETY_FAULT_COUNT       (SAFETY_HAL_BASE + SAFETY_FAULT_COUNT_OFFSET)
#define SAFETY_LOCKSTEP_CTRL     (SAFETY_HAL_BASE + SAFETY_LOCKSTEP_CTRL_OFFSET)
#define SAFETY_LOCKSTEP_MASK     (SAFETY_HAL_BASE + SAFETY_LOCKSTEP_MASK_OFFSET)
#define SAFETY_LOCKSTEP_MISMATCH (SAFETY_HAL_BASE + SAFETY_LOCKSTEP_MISMATCH_OFFSET)
#define SAFETY_LOCKSTEP_LAST_PC  (SAFETY_HAL_BASE + SAFETY_LOCKSTEP_LAST_PC_OFFSET)
#define SAFETY_LOCKSTEP_LAST_OUT (SAFETY_HAL_BASE + SAFETY_LOCKSTEP_LAST_OUT_OFFSET)
#define SAFETY_LOCKSTEP_LAST_EXP (SAFETY_HAL_BASE + SAFETY_LOCKSTEP_LAST_EXP_OFFSET)
#define SAFETY_SCRATCH           (SAFETY_HAL_BASE + SAFETY_SCRATCH_OFFSET)
#define SAFETY_INTR_MASK         (SAFETY_HAL_BASE + SAFETY_INTR_MASK_OFFSET)
#define SAFETY_INTR_STATUS       (SAFETY_HAL_BASE + SAFETY_INTR_STATUS_OFFSET)
#define SAFETY_RESET_CTRL        (SAFETY_HAL_BASE + SAFETY_RESET_CTRL_OFFSET)
#define SAFETY_ID                (SAFETY_HAL_BASE + SAFETY_ID_OFFSET)

/* ---- Magic Values ---- */
#define SAFETY_ID_VALUE          0x53465459UL    /* "SFTY" */
#define SAFETY_RESET_MAGIC       0xA5U

/* ---- SAFETY_CTRL Bits ---- */
#define SAFETY_CTRL_ENABLE              (1U << 0)
#define SAFETY_CTRL_LOCKSTEP_EN         (1U << 1)
#define SAFETY_CTRL_FAULT_AGG_EN        (1U << 2)
#define SAFETY_CTRL_AUTO_HALT           (1U << 3)
#define SAFETY_CTRL_AUTO_SHUTDOWN       (1U << 4)
#define SAFETY_CTRL_FORCE_FAULT         (1U << 8)
#define SAFETY_CTRL_FORCE_MISMATCH      (1U << 9)
#define SAFETY_CTRL_TEST_MODE           (1U << 10)

/* ---- SAFETY_STATUS Bits ---- */
#define SAFETY_STAT_ENABLED             (1U << 0)
#define SAFETY_STAT_LOCKSTEP_ACTIVE     (1U << 1)
#define SAFETY_STAT_ANY_FAULT           (1U << 2)
#define SAFETY_STAT_CRITICAL_FAULT      (1U << 3)
#define SAFETY_STAT_HALTED              (1U << 4)
#define SAFETY_STAT_SHUTDOWN            (1U << 5)

/* ---- Fault Source Mask Bits ---- */
#define FAULT_SRC_LOCKSTEP_MISMATCH     (1U << 0)   /* CRITICAL */
#define FAULT_SRC_WDT_TIMEOUT           (1U << 1)   /* CRITICAL */
#define FAULT_SRC_WDT_EARLY             (1U << 2)   /* HIGH     */
#define FAULT_SRC_SERVO_FAULT           (1U << 3)   /* HIGH     */
#define FAULT_SRC_AI_FAULT              (1U << 4)   /* HIGH     */
#define FAULT_SRC_SPI_FAULT             (1U << 5)   /* MEDIUM   */
#define FAULT_SRC_SPEED_STUCK           (1U << 6)   /* MEDIUM   */
#define FAULT_SRC_ITCM_PARITY           (1U << 7)   /* CRITICAL */
#define FAULT_SRC_DTCM_PARITY           (1U << 8)   /* CRITICAL */
#define FAULT_SRC_GPIO_SHUTDOWN_ACK     (1U << 9)   /* HIGH     */
#define FAULT_SRC_AXI_DECODE_ERR        (1U << 10)  /* MEDIUM   */
#define FAULT_SRC_SOFTWARE_FAULT        (1U << 11)  /* HIGH     */

/* ---- SAFETY_RESET_CTRL Bits ---- */
#define SAFETY_RESET_CPU                (1U << 0)
#define SAFETY_RESET_PERIPH             (1U << 1)
#define SAFETY_RESET_AI                 (1U << 2)

/* ---- SAFETY_LOCKSTEP_CTRL Bits ---- */
#define LOCKSTEP_CTRL_ENABLE            (1U << 0)
#define LOCKSTEP_CTRL_DELAY_EN          (1U << 1)

/* ---- Inline MMIO Helpers ---- */
static inline void safety_hal_write(uint32_t offset, uint32_t value) {
    *((volatile uint32_t *)(SAFETY_HAL_BASE + offset)) = value;
}

static inline uint32_t safety_hal_read(uint32_t offset) {
    return *((volatile uint32_t *)(SAFETY_HAL_BASE + offset));
}

#ifdef __cplusplus
}
#endif

#endif /* HAL_SAFETY_H */
