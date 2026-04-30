/*
 * adas_platform.h — ADAS v2 SoC Platform Definitions
 * ==================================================
 * Project:  adas_v2 — ADAS RISC-V High-Performance SoC
 * Target:   RV32IM (bare-metal, sky130hs, 100 MHz)
 * SDK:      adas_v2_firmware_sdk
 * Version:  1.0.0
 * Date:     2026-04-29
 *
 * Master platform header. Include this in all firmware modules
 * to get:
 *   - Base addresses for all memory-mapped peripherals
 *   - Clock frequency constants
 *   - Memory map dimensions
 *   - MMIO access macros
 *   - Common type definitions
 */

#ifndef ADAS_PLATFORM_H
#define ADAS_PLATFORM_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================
 * CLOCK ARCHITECTURE
 * ======================================================================== */

#define SYS_CLK_HZ              100000000UL     /* 100 MHz system clock     */
#define WDT_CLK_HZ              32768UL         /* 32.768 kHz WDT clock     */

/* Derived clock constants */
#define SYS_CLK_PERIOD_NS       10U             /* 10 ns per sys_clk tick   */
#define MS_TO_SYS_TICKS(ms)     ((uint32_t)((uint64_t)(ms) * 100000UL))
#define US_TO_SYS_TICKS(us)     ((uint32_t)((uint64_t)(us) * 100UL))
#define SYS_TICKS_TO_US(ticks)  ((uint32_t)((ticks) / 100UL))

/* ========================================================================
 * MEMORY MAP — PHYSICAL ADDRESSES
 * ======================================================================== */

/* Tightly Coupled Memories (core-private, not on AXI) */
#define ITCM_BASE               0x00000000UL    /* Instruction TCM (8 KB)   */
#define ITCM_SIZE               0x00002000UL    /* 8 KB = 2048 × 32-bit     */
#define DTCM_BASE               0x00002000UL    /* Data TCM (8 KB)          */
#define DTCM_SIZE               0x00002000UL    /* 8 KB = 2048 × 32-bit     */

/* Memory-Mapped Peripheral Base Addresses (on AXI4-Lite crossbar) */
#define AI_ACCEL_BASE           0x00001000UL    /* AI Accelerator (4 KB)    */
#define SPI_BASE                0x00002000UL    /* SPI Controller (4 KB)    */
#define SERVO_PWM_BASE          0x00003000UL    /* Servo PWM (4 KB)         */
#define SPEED_SENSOR_BASE       0x00004000UL    /* Speed Sensor (4 KB)      */
#define BUZZER_PWM_BASE         0x00005000UL    /* Buzzer PWM (4 KB)        */
#define UART_BASE               0x00006000UL    /* UART (4 KB)              */
#define GPIO_BASE               0x00007000UL    /* GPIO (4 KB)              */
#define SAFETY_CTRL_BASE        0x0000F000UL    /* Safety Control (256 B)   */
#define WDT_BASE                0x0000F100UL    /* Window WDT (256 B)       */

/* ========================================================================
 * MMIO ACCESS MACROS
 * ========================================================================
 *
 * All MMIO registers are 32-bit, aligned on 4-byte boundaries.
 * Use volatile pointer dereference for direct access.
 * Reorder fences included for completeness (fence iorw, iorw).
 */

#define MMIO32(addr)            (*((volatile uint32_t *)(addr)))

static inline void mmio_write32(uintptr_t addr, uint32_t val) {
    MMIO32(addr) = val;
}

static inline uint32_t mmio_read32(uintptr_t addr) {
    return MMIO32(addr);
}

static inline void mmio_set_bits32(uintptr_t addr, uint32_t mask) {
    uint32_t tmp = mmio_read32(addr);
    mmio_write32(addr, tmp | mask);
}

static inline void mmio_clr_bits32(uintptr_t addr, uint32_t mask) {
    uint32_t tmp = mmio_read32(addr);
    mmio_write32(addr, tmp & ~mask);
}

/* FENCE macros (RISC-V memory ordering) */
#define FENCE()                 __asm__ volatile ("fence" ::: "memory")
#define FENCE_I()               __asm__ volatile ("fence.i" ::: "memory")

/* ========================================================================
 * FIRMWARE MEMORY LAYOUT CONSTANTS
 * ======================================================================== */

#define STACK_SIZE              2048U           /* 2 KB default stack       */
#define HEAP_SIZE               0U              /* No heap (bare-metal)     */

/* ========================================================================
 * INTERRUPT NUMBERS (from microarchitecture spec §9.1)
 * ======================================================================== */

#define IRQ_SPI_RX              0
#define IRQ_SPI_TX              1
#define IRQ_SPI_ERR             2
#define IRQ_SERVO_FAULT         3
#define IRQ_SPEED_PULSE         4
#define IRQ_SPEED_OVF           5
#define IRQ_BUZZER_DONE         6
#define IRQ_UART_RX             7
#define IRQ_UART_TX             8
#define IRQ_GPIO                9
#define IRQ_AI_DONE             10
#define IRQ_AI_ERR              11
#define IRQ_WDT_PREWARN         12
#define IRQ_LOCKSTEP_MISMATCH   13
#define IRQ_FAULT_AGG           14
#define IRQ_TIMER               15

/* ========================================================================
 * SYSTEM CONTROL UTILITIES
 * ======================================================================== */

/** Trigger a software breakpoint (for debug, EBREAK instruction). */
static inline void debug_break(void) {
    __asm__ volatile ("ebreak");
}

/** Wait For Interrupt — put core in low-power state until IRQ. */
static inline void wfi(void) {
    __asm__ volatile ("wfi");
}

/** No-op barrier. */
static inline void nop(void) {
    __asm__ volatile ("nop");
}

/** Busy-wait for N cycles (approximate). */
static inline void delay_cycles(uint32_t cycles) {
    for (volatile uint32_t i = 0; i < cycles; i++) {
        __asm__ volatile ("nop");
    }
}

#ifdef __cplusplus
}
#endif

#endif /* ADAS_PLATFORM_H */
