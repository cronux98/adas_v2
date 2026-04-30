/*
 * crt0.s — ADAS v2 SoC Bare-Metal C Runtime Startup
 * ===================================================
 * Target:    RV32IM (rv32im_zicsr_zifencei) | sky130hs | 100 MHz
 * Tool:      riscv32-unknown-elf-gcc 14.2.1 (GNU AS)
 * SDK:       adas_v2_firmware_sdk v0.1.0-dev
 *
 * Boot sequence:
 *   1. 32-entry vector table (vectored mode at mtvec)
 *   2. Disable interrupts (mie=0, mip=0)
 *   3. Set up mtvec → vector_table (vectored mode)
 *   4. Initialize stack pointer from linker-defined _stack_top
 *   5. Clear gp, tp registers
 *   6. Copy .data section from ITCM (LMA) to DTCM (VMA)
 *   7. Zero .bss section in DTCM
 *   8. Jump to main()
 *   9. Trap handlers (default: save context + WFI loop)
 *
 * MATCHES: REGISTER_MAP.md §1 — Address Map
 *          ARCH-IF-001 §3 — RV32IM Core Interface
 */

.section .text.vector_table, "ax", @progbits
.balign 256                         /* Vector table aligned to 256 bytes */

/* ========================================================================
 * VECTOR TABLE — 32 entries for RV32 interrupt model
 *
 * mtvec.MODE = 1 (vectored): PC = BASE + 4 × exception_code
 *
 * IRQ mapping (matches adas_platform.h):
 *   IRQ 0:  SPI RX            IRQ 8:  UART TX
 *   IRQ 1:  SPI TX            IRQ 9:  GPIO
 *   IRQ 2:  SPI Error         IRQ 10: AI Done
 *   IRQ 3:  Servo Fault       IRQ 11: AI Error
 *   IRQ 4:  Speed Pulse       IRQ 12: WDT Pre-warn
 *   IRQ 5:  Speed Overflow    IRQ 13: Lockstep Mismatch (CRITICAL)
 *   IRQ 6:  Buzzer Done       IRQ 14: Fault Aggregator (CRITICAL)
 *   IRQ 7:  UART RX           IRQ 15: Timer
 * ======================================================================== */

.global vector_table
vector_table:

    /* Entry 0: Reset handler */
    j _start
    .balign 4

    /* Entries 1–15: Peripheral interrupts (vectored) */
    /* IRQ 0:  SPI RX */
    j trap_default
    .balign 4
    /* IRQ 1:  SPI TX */
    j trap_default
    .balign 4
    /* IRQ 2:  SPI Error */
    j trap_default
    .balign 4
    /* IRQ 3:  Servo Fault */
    j trap_default
    .balign 4
    /* IRQ 4:  Speed Pulse */
    j trap_default
    .balign 4
    /* IRQ 5:  Speed Overflow */
    j trap_default
    .balign 4
    /* IRQ 6:  Buzzer Done */
    j trap_default
    .balign 4
    /* IRQ 7:  UART RX */
    j trap_default
    .balign 4
    /* IRQ 8:  UART TX */
    j trap_default
    .balign 4
    /* IRQ 9:  GPIO */
    j trap_default
    .balign 4
    /* IRQ 10: AI Done */
    j trap_default
    .balign 4
    /* IRQ 11: AI Error */
    j trap_default
    .balign 4
    /* IRQ 12: WDT Pre-warn */
    j trap_default
    .balign 4
    /* IRQ 13: Lockstep Mismatch — CRITICAL */
    j trap_critical
    .balign 4
    /* IRQ 14: Fault Aggregator — CRITICAL */
    j trap_critical
    .balign 4
    /* IRQ 15: Timer */
    j trap_default
    .balign 4

    /* Entries 16–31: Reserved / standard exceptions */
    .rept 16
    j trap_default
    .balign 4
    .endr

/* ========================================================================
 * RESET HANDLER (_start)
 * ======================================================================== */

.section .text._start, "ax", @progbits
.global _start
.type _start, @function

_start:
    /* ---- Disable interrupts during boot ---- */
    csrw mie, zero
    csrw mip, zero

    /* ---- Set up mtvec to vector table (vectored mode) ---- */
    la t0, vector_table
    ori t0, t0, 1              /* mtvec.MODE = 1 (vectored) */
    csrw mtvec, t0

    /* ---- Initialize stack pointer ---- */
    la sp, _stack_top

    /* ---- Initialize global pointer (gp) to zero ---- */
    mv gp, zero

    /* ---- Initialize thread pointer (tp) to zero ---- */
    mv tp, zero

    /* ---- Copy .data section from ITCM (LMA) to DTCM (VMA) ---- */
    la t0, _data_start          /* destination (DTCM) */
    la t1, _data_load_start     /* source (ITCM)       */
    la t2, _data_end            /* end of .data (VMA)  */
    beq t0, t2, 2f              /* skip if .data is empty */

1:  lw t3, 0(t1)                /* load from LMA (ITCM) */
    sw t3, 0(t0)                /* store to VMA (DTCM)  */
    addi t0, t0, 4
    addi t1, t1, 4
    bltu t0, t2, 1b

2:  /* ---- Zero .bss section ---- */
    la t0, _bss_start
    la t1, _bss_end
    beq t0, t1, 2f
    mv t2, zero

1:  sw t2, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b

2:  /* ---- Boot sequence complete, jump to C runtime ---- */
    call main

    /* ---- main() returned — trap ---- */
_halt:
    j trap_default

/* ========================================================================
 * DEFAULT TRAP HANDLER
 *
 * Saves caller-saved registers to stack, reads mcause/mepc for
 * debugging, then enters infinite WFI loop.
 * ======================================================================== */

trap_default:
    /* Save caller-saved registers to stack */
    addi sp, sp, -64
    sw ra,  0(sp)
    sw t0,  4(sp)
    sw t1,  8(sp)
    sw t2,  12(sp)
    sw t3,  16(sp)
    sw t4,  20(sp)
    sw t5,  24(sp)
    sw t6,  28(sp)
    sw a0,  32(sp)
    sw a1,  36(sp)
    sw a2,  40(sp)
    sw a3,  44(sp)
    sw a4,  48(sp)
    sw a5,  52(sp)
    sw a6,  56(sp)
    sw a7,  60(sp)

    /* Read mcause and mepc for post-mortem analysis */
    csrr a0, mcause
    csrr a1, mepc

    /* Infinite loop with WFI — debugger can inspect a0/a1 */
trap_loop:
    wfi
    j trap_loop

/* ========================================================================
 * CRITICAL TRAP HANDLER
 *
 * For lockstep mismatch (IRQ 13) and fault aggregator (IRQ 14).
 * Immediately asserts safety GPIO pins and enters unrecoverable halt.
 * Recovery requires external reset (SAFETY_RESET_CTRL or POR).
 * ======================================================================== */

trap_critical:
    /* Disable all interrupts */
    csrw mie, zero

    /* Assert GPIO safety pins: ALERT_OUT, SHUTDOWN_A, SHUTDOWN_B
     * GPIO_BASE = 0x00007000, GPIO_SET = BASE + 0x10            */
    li t0, 0x00007010
    li t1, 0x00000007          /* GPIO[2:0] — all safety pins */
    sw t1, 0(t0)

    /* Infinite loop — only external reset can recover */
critical_loop:
    wfi
    j critical_loop

.size _start, . - _start
