.section .text
.globl _start
_start:
    li x1, 90
    csrrw x2, mscratch, x1
    bnez x2, fail

    csrr x3, mscratch
    li x4, 90
    bne x3, x4, fail

    csrrci x5, mscratch, 26
    bne x5, x4, fail

    csrr x6, mscratch
    li x7, 64
    bne x6, x7, fail

    csrr x8, cycle
    beqz x8, fail

pass:
    li t0, 1
    la t1, tohost
    sw t0, 0(t1)
1:
    j 1b

fail:
    li t0, 3
    la t1, tohost
    sw t0, 0(t1)
2:
    j 2b
