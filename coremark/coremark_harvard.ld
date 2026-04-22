OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
  DMEM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS {
  .text : {
    *(.init)
    *(.text*)
    *(.rodata*)
  } > IMEM

  .data : ALIGN(4) {
    __data_start = .;
    *(.data*) *(.sdata*)
    __data_end = .;
  } > DMEM AT > IMEM
  __data_load = LOADADDR(.data);

  .bss (NOLOAD) : ALIGN(4) {
    __bss_start = .;
    *(.bss*) *(COMMON)
    __bss_end = .;
  } > DMEM

  /* Keep the MMIO map aligned with coremark/link.ld */
  PROVIDE(uart_tx  = 0x0000FFE0);
  PROVIDE(fromhost = 0x0000FFF0);
  PROVIDE(tohost   = 0x0000FFF8);

  /* Stack below MMIO area */
  __stack_top = ORIGIN(DMEM) + LENGTH(DMEM) - 0x40;
}
