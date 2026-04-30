/*
 * hal/wdt.h — Window Watchdog Timer Hardware Abstraction Layer
 * =============================================================
 * Base: 0x0000_F100 | Block: Window WDT (wdt_clk domain, 32.768 kHz)
 * Source: REGISTER_MAP.md §10
 *
 * SAFETY-CRITICAL: WDT cannot be disabled once enabled (until hard reset).
 * All writes to CTRL[3:0] require KEY = 0x5A in upper byte.
 * Refresh value for WDT_KICK is 0xAC53_CAFE.
 */

#ifndef HAL_WDT_H
#define HAL_WDT_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Base Address ---- */
#define WDT_HAL_BASE            0x0000F100UL

/* ---- Register Offsets (32-bit aligned) ---- */
#define WDT_CTRL_OFFSET         0x00U
#define WDT_TIMEOUT_OFFSET      0x04U
#define WDT_WINDOW_OFFSET       0x08U
#define WDT_COUNT_OFFSET        0x0CU
#define WDT_KICK_OFFSET         0x10U
#define WDT_STATUS_OFFSET       0x14U
#define WDT_PREWARN_OFFSET      0x18U
#define WDT_INTR_MASK_OFFSET    0x1CU
#define WDT_INTR_STATUS_OFFSET  0x20U
#define WDT_LOCK_OFFSET         0x24U
#define WDT_ID_OFFSET           0x28U

/* ---- Absolute Register Addresses ---- */
#define WDT_CTRL                (WDT_HAL_BASE + WDT_CTRL_OFFSET)
#define WDT_TIMEOUT             (WDT_HAL_BASE + WDT_TIMEOUT_OFFSET)
#define WDT_WINDOW              (WDT_HAL_BASE + WDT_WINDOW_OFFSET)
#define WDT_COUNT               (WDT_HAL_BASE + WDT_COUNT_OFFSET)
#define WDT_KICK                (WDT_HAL_BASE + WDT_KICK_OFFSET)
#define WDT_STATUS              (WDT_HAL_BASE + WDT_STATUS_OFFSET)
#define WDT_PREWARN             (WDT_HAL_BASE + WDT_PREWARN_OFFSET)
#define WDT_INTR_MASK           (WDT_HAL_BASE + WDT_INTR_MASK_OFFSET)
#define WDT_INTR_STATUS         (WDT_HAL_BASE + WDT_INTR_STATUS_OFFSET)
#define WDT_LOCK                (WDT_HAL_BASE + WDT_LOCK_OFFSET)
#define WDT_ID                  (WDT_HAL_BASE + WDT_ID_OFFSET)

/* ---- Magic Values ---- */
#define WDT_KICK_MAGIC          0xAC53CAFEUL
#define WDT_CTRL_KEY            0x5A00U
#define WDT_ID_VALUE            0x57445400UL    /* "WDT\0" */

/* ---- WDT_CTRL Bits (write with KEY=0x5A in [15:8]) ---- */
#define WDT_CTRL_ENABLE         (1U << 0)
#define WDT_CTRL_WINDOW_EN      (1U << 1)
#define WDT_CTRL_PREWARN_EN     (1U << 2)
#define WDT_CTRL_RESET_EN       (1U << 3)

/* ---- WDT_STATUS Bits ---- */
#define WDT_STAT_RUNNING        (1U << 0)
#define WDT_STAT_IN_WINDOW      (1U << 1)
#define WDT_STAT_PREWARNED      (1U << 2)
#define WDT_STAT_TIMED_OUT      (1U << 3)
#define WDT_STAT_EARLY_KICK     (1U << 4)

/* ---- WDT_LOCK Bits ---- */
#define WDT_LOCK_CTRL           (1U << 0)
#define WDT_LOCK_TIMEOUT        (1U << 1)
#define WDT_LOCK_WINDOW         (1U << 2)
#define WDT_LOCK_ALL_LOCKED     (1U << 3)

/* ---- Default Timeout: ~100ms @ 32.768 kHz (3277 ticks) ---- */
#define WDT_DEFAULT_TIMEOUT     3277U
#define WDT_DEFAULT_WINDOW_PCT  75U

/* ---- Inline MMIO Helpers ---- */
static inline void wdt_hal_write(uint32_t offset, uint32_t value) {
    *((volatile uint32_t *)(WDT_HAL_BASE + offset)) = value;
}

static inline uint32_t wdt_hal_read(uint32_t offset) {
    return *((volatile uint32_t *)(WDT_HAL_BASE + offset));
}

#ifdef __cplusplus
}
#endif

#endif /* HAL_WDT_H */
