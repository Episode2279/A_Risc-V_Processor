OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
  DMEM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K

  /* Dummy load region to avoid LMA overlap in the ELF image */
  DLOAD (rx) : ORIGIN = 0x00010000, LENGTH = 64K
}

SECTIONS {
  .text : {
    *(.init)
    *(.text*)
  } > IMEM

  /*
   * VMA in DMEM (0x0...), but LMA in DLOAD (0x10000...).
   * Keep .rodata here because the core has separate instruction/data
   * memories, and C string literals are read through the data port.
   */
  .data : ALIGN(4) {
    __data_start = .;
    *(.rodata*)
    *(.data*) *(.sdata*)
    __data_end = .;
  } > DMEM AT > DLOAD

  .bss (NOLOAD) : ALIGN(4) {
    __bss_start = .;
    *(.bss*) *(COMMON)
    __bss_end = .;
  } > DMEM

  PROVIDE(uart_tx  = 0x0000FFE0);
  PROVIDE(fromhost = 0x0000FFF0);
  PROVIDE(tohost   = 0x0000FFF8);

  __stack_top = ORIGIN(DMEM) + LENGTH(DMEM) - 0x40;
}
