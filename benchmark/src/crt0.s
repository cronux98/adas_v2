.section .text.startup,"ax",@progbits
.globl _start
_start:
    la sp, _stack_top
    call main
    ebreak
.size _start, .-_start

.section .bss
.align 4
_stack_bottom:
.zero 4096
_stack_top:
