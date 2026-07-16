#ifndef A_RISCV_PROCESSOR_RVMODEL_MACROS_H
#define A_RISCV_PROCESSOR_RVMODEL_MACROS_H

#define RVMODEL_DATA_SECTION
#define STANDARD_SM_SUPPORTED
#define RVMODEL_INTERRUPT_LATENCY 10
#define RVMODEL_TIMER_INT_SOON_DELAY 100
#define RVMODEL_SET_MEXT_INT(_R1, _R2)
#define RVMODEL_CLR_MEXT_INT(_R1, _R2)
#define RVMODEL_SET_MSW_INT(_R1, _R2)
#define RVMODEL_CLR_MSW_INT(_R1, _R2)
#define RVMODEL_SET_SEXT_INT(_R1, _R2)
#define RVMODEL_CLR_SEXT_INT(_R1, _R2)
#define RVMODEL_SET_SSW_INT(_R1, _R2)
#define RVMODEL_CLR_SSW_INT(_R1, _R2)

#define RVMODEL_HALT_PASS  \
  li t0, 0x000ffff8;       \
  li t1, 1;                \
  sw t1, 0(t0);            \
1: j 1b

#define RVMODEL_HALT_FAIL  \
  li t0, 0x000ffff8;       \
  li t1, 3;                \
  sw t1, 0(t0);            \
1: j 1b

#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR) \
1: lbu _R1, 0(_STR_PTR);                            \
   beqz _R1, 3f;                                    \
   li _R2, 0x000fffe0;                              \
   sb _R1, 0(_R2);                                  \
   addi _STR_PTR, _STR_PTR, 1;                      \
   j 1b;                                             \
3:

#endif
