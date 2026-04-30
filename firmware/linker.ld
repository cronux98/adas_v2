/*
 * linker.ld — ADAS v2 SoC Linker Script
 * ======================================
 * Target:   RV32IM | sky130hs | 100 MHz
 * Tool:     riscv64-unknown-elf-ld (GNU ld)
 * Memory:   ITCM 8KB @ 0x00000000 | DTCM 8KB @ 0x00002000
 *
 * MATCHES:  REGISTER_MAP.md §1 — Address Map Overview
 *           microarchitecture_spec.md §6.1 — Memory Map
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

/* ========================================================================
 * MEMORY REGIONS
 *
 * ITCM: Instruction Tightly Coupled Memory (8 KB)
 *       Contains: .text (code), .rodata (constants)
 *
 * DTCM: Data Tightly Coupled Memory (8 KB)
 *       Contains: .data, .bss, stack, heap (if any)
 *
 * Note: Peripherals at 0x00001000–0x0000FFFF are accessed via MMIO
 *       and are NOT allocated by the linker.
 * ======================================================================== */

MEMORY
{
    ITCM (rx)  : ORIGIN = 0x00000000, LENGTH = 0x2000   /*  8 KB */
    DTCM (rw)  : ORIGIN = 0x00002000, LENGTH = 0x2000   /*  8 KB */
}

/* ========================================================================
 * STACK & HEAP
 * ======================================================================== */

_stack_size = 2048;     /* 2 KB default stack */

/* ========================================================================
 * OUTPUT SECTIONS
 * ======================================================================== */

SECTIONS
{
    /* ---- Code → ITCM (code only, no data) ---- */
    .text : ALIGN(4)
    {
        _text_start = .;
        KEEP(*(.text._start))       /* startup entry point first */
        KEEP(*(.text.vector_table)) /* vector table at known offset */
        *(.text .text.*)
        *(.srodata .srodata.*)
        . = ALIGN(4);
        _text_end = .;
    } > ITCM

    /* ---- Initialized Data (LMA in ITCM, VMA in DTCM) ----
     * Includes .rodata for string literals to save ITCM space */
    .data : ALIGN(4)
    {
        _data_start = .;
        *(.rodata .rodata.*)
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        _data_end = .;
    } > DTCM AT > ITCM

    /* ---- LMA symbols for data copy ---- */
    _data_load_start = LOADADDR(.data);
    _data_load_end   = _data_load_start + (_data_end - _data_start);

    /* ---- Uninitialized Data (BSS) → DTCM ---- */
    .bss (NOLOAD) : ALIGN(4)
    {
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > DTCM

    /* ---- Heap (reserved, zero size by default) ---- */
    .heap (NOLOAD) : ALIGN(4)
    {
        _heap_start = .;
        . = . + 0;      /* No heap requested */
        _heap_end = .;
    } > DTCM

    /* ---- Stack (at top of DTCM) ---- */
    .stack (NOLOAD) : ALIGN(16)
    {
        _stack_bottom = .;
        . = . + _stack_size;
        . = ALIGN(16);
        _stack_top = .;
    } > DTCM

    /* ---- Discard unwanted sections ---- */
    /DISCARD/ :
    {
        *(.comment)
        *(.gnu*)
        *(.note*)
        *(.eh_frame*)
        *(.riscv.attributes)
    }

    /* ---- Debug info (not loaded, but useful for disasm) ---- */
    .stab        0 (NOLOAD) : { *(.stab) }
    .stabstr     0 (NOLOAD) : { *(.stabstr) }

    /* ---- End-of-image marker ---- */
    _end = .;
}
