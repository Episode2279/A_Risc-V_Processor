# A_Risc-V_Processor

PRF-based, out-of-order RV32I-style RISC-V processor written in SystemVerilog.

`topCPU` now uses the out-of-order architecture as its only executable core:
dual fetch/decode feeds register rename, a unified dual-issue queue, physical
register file, reorder buffer, load/store queue, execution, and in-order retirement.
The former sequential execute/memory/writeback pipeline has been removed.

The RV32I path now performs strict illegal-instruction decoding, serializes
FENCE, and takes precise ROB-head traps for ECALL, EBREAK, instruction-address
misalignment, and load/store-address misalignment. Basic machine trap entry and
MRET are implemented. Run `make rv32i-compliance-smoke` for the directed suite.
The official ACT4 RV32I I-extension suite passes all 39 generated self-checking
tests; its configuration and runner live under `compliance/`.

The unified scheduler can issue two integer operations or pair one integer with
a branch/CSR/memory operation. The front end uses a five-table TAGE predictor
with incremental folded direction history, independently hashed speculative
Path History, synchronous banked Tag RAM, and grouped pseudorandom allocation
over a GShare base/alternate. A compact statistical corrector combines one
PC-bias table with four GEHL components before the final direction is selected;
target prediction uses a two-way BTB and a RAS. Predictor histories recover
precisely from ROB-tagged checkpoints. Loads can
pass known non-aliasing Stores and receive Store-to-Load forwarding; Stores
become externally visible only at ROB retirement. Multiple branches may remain
unresolved and execute out of order; CSR/FENCE/trap-class operations retain the
serialized path.
See `source/functional/OoO/README.md` for implemented invariants and remaining
performance work.

Under the project's CBP-style accounting, the logical conditional-direction
predictor state is 32,553 bits (4,069.125 bytes), 215 bits below the 4 KiB
limit. This is not the synthesized physical-memory total: dual-lane table
copies, multiport banking/replication, recovery checkpoints, update metadata,
BTB, and RAS remain real hardware outside that logical-capacity count. See
`SPEC.md` and `source/functional/BPU/README.md` for the itemized budget.

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

The authoritative successful termination is:

```text
toHost=0x00000001
***** simulation result: SUCCESS *****
```

With the default 10-iteration simulation, CoreMark may also print
`Errors detected`. The expected CRCs are still produced; this message is its
standard validation warning because the simulated run represents less than the
required 10 seconds. It is not a CPU-functional failure when `tohost` reports
success.

## Useful Make Targets

```sh
make help            # Show available targets
make coremark        # Rebuild CoreMark ELF and memory images only
make lint            # Verilator lint for RTL plus SV testbench
make bpu-smoke       # Test GShare/BTB behavior
make tage-smoke      # Test TAGE folds, hashes, tables, and history recovery
make tage-update-smoke # Test the retirement-training FIFO and backpressure
make sc-smoke        # Test statistical-corrector timing/training/forwarding
make ooo-smoke       # Test RAT/PRF/ROB/IQ/LSQ structures
make ooo-backend-smoke # Test OoO dispatch/execute/commit behavior
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
- `source/functional/id`: instruction decoding
- `source/functional/BPU`: GShare/TAGE/SC-Lite direction prediction, BTB, and RAS
- `source/functional/rename`: RAT, committed map, physical free list, and dispatch
- `source/functional/issue`: physical-tag issue queue and wakeup/select logic
- `source/functional/exe`: ALU, OoO execution, branch resolution, and CSR state
- `source/functional/mem`: LSQ and load/store execution mechanisms
- `source/functional/OoO`: ROB, PRF, and out-of-order architecture notes
- `source/memory`: instruction/data memories and MMIO behavior
- `source/frontEnd`: dual fetch/decode wrappers and the IF/ID register
- `source/backEnd`: OoO backend and memory/MMIO stage wrappers
- `coremark`: bare-metal CoreMark port and linker script

## Notes

CoreMark now reads the architectural `cycle/mcycle` CSR for timing. The
reported `Total ticks` value is the real core-cycle delta seen by software.

`Total time (secs)` is derived from `CORE_CLOCK_HZ` in
`coremark/core_portme.h`, which defaults to `100_000_000` to match the current
10 ns simulation clock period. If you change the simulated/synthesized clock,
update that constant so CoreMark's seconds conversion stays consistent.
