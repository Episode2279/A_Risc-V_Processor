# make -C isa RISCV_PREFIX=riscv64-unknown-elf- XLEN=32 rv32ui-p-simple
## riscv64-unknown-elf-objcopy -O binary   -j .text.init -j .text -j .rodata   isa/rv32ui-p-simple imemSimple.bin
## riscv64-unknown-elf-objcopy -O binary   -j .data -j .sdata   isa/rv32ui-p-simple dmemSimple.bin

### python3 bin2bytes.py imemSimple.bin insMemSimple.txt 0x10000
### python3 bin2words.py dmemSimple.bin dataMemSimple.hex 0x10000

#############################################

# riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -O2   -ffreestanding -nostdlib   hello.c start.s -Wl,-T,link.ld -lgcc   -o hello.elf
# (riscv64-unknown-elf-objcopy -O binary hello.elf mem.bin)
## riscv64-unknown-elf-objcopy -O binary -j .text -j .rodata hello.elf imemHello.bin
## riscv64-unknown-elf-objcopy -O binary -j .data -j .sdata hello.elf dmemHello.bin
### python3 bin2bytes.py imemHello.bin insMemHello.txt 0x10000
### python3 bin2words.py dmemHello.bin dataMemHello.hex 0x10000

#############################################

# riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -O2   -ffreestanding -nostdlib -I.   core_main.c core_list_join.c core_matrix.c core_state.c core_util.c core_portme.c   start.s   -Wl,-T,link.ld -Wl,-Map,coremark.map   -lgcc -o coremark.elf