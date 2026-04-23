# A_Risc-V_Processor

RV32I-style pipelined RISC-V processor written in SystemVerilog.

The project includes a Verilator simulation flow, a Vivado-oriented SystemVerilog
testbench, CoreMark bare-metal software, memory-image generation, UART MMIO
console output, and `tohost` pass/fail reporting.

## Requirements

Run the command-line flow from WSL or Linux.

Required tools:

- `make`
- `verilator`
- `python3`
- `riscv64-unknown-elf-gcc`
- `riscv64-unknown-elf-objcopy`
- `riscv64-unknown-elf-size`

On Ubuntu/WSL, install the main tools with:

```sh
sudo apt update
sudo apt install make verilator gcc-riscv64-unknown-elf python3
```

## Quick Start

From the project root:

```sh
cd A_Risc-V_Processor
make sim
```

`make sim` does the full verified flow:

- Builds `coremark/coremark.elf`
- Generates `source/utils/insn.mem`
- Generates `source/utils/data.mem`
- Runs Verilator lint
- Builds `source/obj_dir/VtopCPU`
- Runs the simulation until `tohost` or timeout

Expected successful output includes:

```text
Correct operation validated.
toHost=0x00000001
***** simulation result: SUCCESS *****
```

## Useful Make Targets

```sh
make help            # Show available targets
make coremark        # Rebuild CoreMark ELF and memory images only
make lint            # Verilator lint for RTL plus SV testbench
make build           # Build the Verilated topCPU executable
make run             # Run the existing Verilated executable
make sim             # coremark + lint + build + run
make csr-smoke       # Run a small CSR instruction/counter smoke test
make clean           # Remove Verilator outputs, waves, and sim logs
make clean-coremark  # Remove generated CoreMark ELF/bin/map/images
make clean-all       # clean + clean-coremark
```

Runtime options:

```sh
make run MAX_CYCLES=2000000
make sim TRACE=1
make sim MAX_CYCLES=2000000 TRACE=1
```

`TRACE=1` writes `source/wave.vcd`.

## Simulation Output

CoreMark writes formatted messages through UART MMIO at `0x0000FFE0`.
The Verilator harness mirrors UART bytes to the console and to
`source/simulation_output.txt`.

The simulation result is decided by `tohost` at `0x0000FFF8`:

- `tohost == 1`: success
- `tohost != 0 && tohost != 1`: failure
- no nonzero `tohost` before `MAX_CYCLES`: timeout

## CSR Support

The core supports the standard CSR instruction forms:

- `csrrw`, `csrrs`, `csrrc`
- `csrrwi`, `csrrsi`, `csrrci`

Implemented CSR state includes common machine-mode registers and counters:

- `mstatus`, `mie`, `mtvec`, `mscratch`
- `mepc`, `mcause`, `mtval`, `mip`
- `mcycle`, `mcycleh`, `minstret`, `minstreth`
- read aliases `cycle`, `cycleh`, `time`, `timeh`, `instret`, `instreth`
- read-only IDs such as `misa` and `mhartid`

Run the CSR smoke test with:

```sh
make csr-smoke
```

The smoke test temporarily loads `test/csr_smoke.S`, verifies CSR read/write and
`cycle`, then restores the default CoreMark memory images.

## Vivado Testbench

The Vivado-oriented testbench is:

```text
testbench/topCPU_tb.sv
```

It writes:

- `source/topCPU_tb_debug.txt`
- `source/topCPU_tb_output.txt`

The structured dump can be converted to Konata format with:

```sh
python3 testbench/tb_dump_to_konata.py \
  --input source/topCPU_tb_output.txt \
  --output source/topCPU_tb_konata.trace
```

## Source Layout

Key source directories:

- `source/topCPU.sv`: top-level CPU composition
- `source/TypesPkg.sv`: shared types, widths, memory sizes, MMIO addresses
- `source/interfaces`: SystemVerilog bus interfaces/modports
- `source/functional/if`: IF-stage helper units
- `source/functional/id`: decode and hazard helper units
- `source/functional/exe`: ALU, branch, and forwarding units
- `source/functional/wb`: writeback helper units
- `source/memory`: instruction/data memories and MMIO behavior
- `source/pipeRegisters`: pipeline registers
- `source/pipeStages`: pipeline stage wrappers/adapters
- `coremark`: bare-metal CoreMark port and linker script

## Notes

CoreMark now reads the architectural `cycle/mcycle` CSR for timing. The
reported `Total ticks` value is the real core-cycle delta seen by software.

`Total time (secs)` is derived from `CORE_CLOCK_HZ` in
`coremark/core_portme.h`, which defaults to `100_000_000` to match the current
10 ns simulation clock period. If you change the simulated/synthesized clock,
update that constant so CoreMark's seconds conversion stays consistent.
