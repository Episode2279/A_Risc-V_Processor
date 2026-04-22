.section .init
.globl _start
_start:
    la    sp, __stack_top

    /* clear .bss */
    la    t0, __bss_start
    la    t1, __bss_end
1:
    bgeu  t0, t1, 2f
    sw    zero, 0(t0)
    addi  t0, t0, 4
    j     1b
2:
    call  main

    /* if main returns: request finish */
    li    t0, 1
    la    t1, tohost
    sw    t0, 0(t1)
3:
    j     3b
