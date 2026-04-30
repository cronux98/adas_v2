/*
 * startup.s — ADAS v2 SoC Bare-Metal Startup Code
 * ================================================
 * Target:    RV32IM | sky130hs | 100 MHz
 * Assembler: GNU AS (riscv64-unknown-elf-as)
 *
 * Performs:
 *   1. Vector table (32-entry trap vector for RV32)
 *   2. Stack pointer initialization from linker-defined _stack_top
 *   3. Global pointer initialization (if needed)
 *   4. Copy .data section from ITCM (load) to DTCM (virtual)
 *   5. Zero .bss section
 *   6. Call main()
 *   7. Trap handler defaults (infinite loop with WFI)
 *
 * MATCHES: microarchitecture_spec.md §8.2 — Reset Sequence
 */

.section .text.vector_table, "ax", @progbits
.balign 256                         /* Vector table aligned to 256 bytes */

/* ========================================================================
 * VECTOR TABLE (32 entries for RV32 interrupt model)
 *
 * The RISC-V privileged spec defines:
 *   Entry 0:        Reset vector (no mtvec offset needed)
 *   Entry 1–15:     Reserved for custom use (IRQ vectors)
 *   Entry 16+:      Standard exception/trap causes
 *
 * For ADAS v2, we use direct vectored mode:
 *   mtvec = BASE | 1  (vectored mode)
 *   PC = BASE + 4 × exception_code
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

    /* Entries 16–31: Reserved / future */
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

    /* ---- Initialize global pointer (gp) if used ---- */
    /* For bare-metal without libc, gp is typically unused.
     * Set to 0 to avoid accidental usage of uninitialized gp. */
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

2:  /* ---- Boot sequence complete ---- */
    /* Set mstatus.MIE = 0 initially (leave to main to enable) */

    /* ---- Call main() ---- */
    call main

    /* ---- main() returned — trap ---- */
_halt:
    j trap_default

/* ========================================================================
 * DEFAULT TRAP HANDLER
 * Saves context, then loops with WFI.
 * ======================================================================== */

trap_default:
    /* Save caller-saved registers */
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

    /* Read mcause and mepc for debugging */
    csrr a0, mcause
    csrr a1, mepc

    /* Default: infinite loop with WFI */
trap_loop:
    wfi
    j trap_loop

/* ========================================================================
 * CRITICAL TRAP HANDLER
 * For lockstep mismatch (IRQ 13) and fault aggregator (IRQ 14).
 * Immediately enters safe shutdown sequence.
 * ======================================================================== */

trap_critical:
    /* Disable all interrupts */
    csrw mie, zero

    /* Set GPIO alert and shutdown signals (atomic) */
    /* GPIO_BASE = 0x00007000 */
    /* GPIO_SET = GPIO_BASE + 0x10 = 0x00007010 */
    li t0, 0x00007010
    li t1, 0x00000007          /* GPIO[2:0] — all safety pins */
    sw t1, 0(t0)

    /* Infinite loop — only external reset can recover */
critical_loop:
    wfi
    j critical_loop

.size _start, . - _start
