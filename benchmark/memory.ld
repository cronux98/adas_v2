MEMORY {
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 256K
}
SECTIONS {
    .text : { *(.text.startup) *(.text*) } > RAM
    .rodata : { *(.rodata*) } > RAM
    .data : { *(.data*) } > RAM
    .bss : { *(.bss*) *(COMMON) } > RAM
}
