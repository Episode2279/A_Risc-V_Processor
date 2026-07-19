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
a branch/CSR/memory operation. It keeps a blocked memory candidate in the IQ
and may fill both integer paths with ready work; the single shared LSU still
accepts at most one memory operation per cycle. The front end uses a five-table TAGE predictor
with incremental folded direction history, independently hashed speculative
Path History, synchronous banked Tag RAM, and grouped pseudorandom allocation
over a GShare base/alternate. A compact statistical corrector combines one
PC-bias table with four GEHL components before the final direction is selected;
target prediction uses a two-way BTB and a RAS. Predictor histories recover
precisely from ROB-tagged checkpoints. Loads can pass known non-aliasing Stores
and receive forwarding from older uncommitted Stores in the LSQ. Stores become
eligible to reach memory only after ROB retirement and may drain later from the
committed Store Buffer. A Load disjoint from that buffer may pass it, while any
overlap waits for the matching committed Store to drain. Multiple branches may
remain unresolved and execute out of order; CSR/FENCE/trap-class operations
retain the serialized path.
See `rtl/backend/docs/OoO.md` for implemented invariants and remaining
performance work.

The F0 front-end request sends `PC`/`PC+4` to the BPU and a 4 KiB synchronous
I-cache in parallel; the aligned instructions and prediction metadata return in
F1. The direct-mapped I-cache has 256 sets, 16-byte lines, dual-address lookup,
and blocking four-word refills. The LSU connects to a 1 KiB, 64-set,
direct-mapped synchronous D-cache with 16-byte lines. Its elastic hit pipeline
accepts one cached Load per cycle, while a tagged single MSHR provides
critical-word-first, early restart, and different-set hit-under-miss. An
eight-entry Store Buffer decouples committed Stores. Its byte-merge query logic
is retained and tested, but the backend currently uses a correctness guard:
disjoint Loads may pass, whereas any overlap waits instead of forwarding
directly from this buffer. Non-forwarded Loads carry their ROB tag through the
D-cache, so the LSU can retain multiple pending requests and discard recovered
wrong-path responses safely. The D-cache remains write-through/no-write-allocate, and
UART/host MMIO bypasses it. Both backing memories use registered synchronous
reads rather than combinational array reads.

Under the project's CBP-style accounting, the logical conditional-direction
predictor state is 32,553 bits (4,069.125 bytes), 215 bits below the 4 KiB
limit. This is not the synthesized physical-memory total: dual-lane table
copies, multiport banking/replication, recovery checkpoints, update metadata,
BTB, and RAS remain real hardware outside that logical-capacity count. See
`SPEC.md` and `rtl/frontend/bpu/README.md` for the itemized budget.

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
- Generates `build/images/insn.mem`
- Generates `build/images/data.mem`
- Runs Verilator lint
- Builds `build/verilator/top/VtopCPU`
- Runs the simulation until `tohost` or timeout

The authoritative successful termination is:

```text
toHost=0x00000001
***** simulation result: SUCCESS *****
```

With the default short one-iteration simulation, CoreMark may also print
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
make icache-smoke    # Test I-cache hits, blocking refill, backpressure, and flush
make dcache-smoke    # Test pipelined hits, early restart, hit-under-miss, and MMIO
make cache-smoke     # Run both cache-directed smoke tests
make store-buffer-smoke # Test committed Store FIFO and byte-merge query logic
make lsu-pending-smoke # Test tagged/reordered Load responses and recovery draining
make ooo-smoke       # Test RAT/PRF/ROB/IQ/LSQ structures
make ooo-backend-smoke # Test OoO dispatch/execute/commit behavior
make build           # Build the Verilated topCPU executable
make run             # Run the existing Verilated executable
make sim             # coremark + lint + build + run
make csr-smoke       # Run a small CSR instruction/counter smoke test
make clean           # Remove Verilator outputs, waves, and sim logs
make clean-coremark  # Remove generated CoreMark ELF/bin/map/images
make clean-all       # clean + clean-coremark
make vivado-project FPGA_PART=<part> # Recreate a Vivado project under build/
make vivado-sim FPGA_PART=<part>     # Run the shared testbench with XSim
make vivado-synth FPGA_PART=<part>   # Synthesize and write reports under build/
```

Runtime options:

```sh
make run MAX_CYCLES=2000000
make sim TRACE=1
make sim MAX_CYCLES=2000000 TRACE=1
```

`TRACE=1` writes `build/traces/wave.vcd`.

## Simulation Output

CoreMark writes formatted messages through UART MMIO at `0x0000FFE0`.
The Verilator harness mirrors UART bytes to the console and to
`build/traces/simulation_output.txt`.

The simulation result is decided by `tohost` at `0x0000FFF8`:

- `tohost == 1`: success
- `tohost != 0 && tohost != 1`: failure
- no nonzero `tohost` before `MAX_CYCLES`: timeout

At shutdown, the harness also prints `CACHE I` and `CACHE D` diagnostic lines.
They expose I-cache request, hit, line-miss, refill/stall, cross-line,
backpressure, and MPKI data, plus D-cache Load/Store hit/miss, MMIO, busy,
refill, request-backpressure, Store-commit-stall, Load miss-rate, and MPKI data.
These counters are RTL debug outputs and are not software-visible CSRs.

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

The shared Vivado/RTL integration testbench is:

```text
verification/integration/core/topCPU_tb.sv
```

It writes:

- `build/traces/topCPU_tb_debug.txt`
- `build/traces/topCPU_tb_output.txt`

The structured dump can be converted to Konata format with:

```sh
make kanata
```

Portable Vivado Tcl and XDC inputs live under `fpga/vivado/`; generated `.xpr`,
`.runs`, `.cache`, reports, and IP output products live under `build/vivado/`.
The FPGA part is always supplied explicitly rather than embedding a developer's
board choice into the CPU RTL.

## Source Layout

The repository is organized by ownership rather than by generic "functional"
or "stage" buckets:

- `rtl/core`: top-level CPU composition
- `rtl/common`: shared types and interfaces
- `rtl/frontend/{fetch,decode,bpu}`: fetch window, decoder, BTB/RAS/TAGE/SC
- `rtl/backend/{dispatch,rename,scheduler,regfile,execute,retire,perf}`: OoO data
  path and control, with LSU/CSR/integer execution grouped below `execute/`
- `rtl/memory/{icache,dcache,backing,subsystem}`: cache hierarchy and backing
  SRAM/BRAM-style memories
- `config/filelists`: ordered, layered RTL manifests shared by build tools
- `verification/{unit,integration}`: testbenches separated from synthesizable RTL
- `sim/verilator`: Verilator C++ harness
- `tools/kanata`: pipeline-dump conversion tools
- `fpga/vivado`: checked-in Tcl/XDC inputs; generated products go to `build/`
- `coremark`, `test`, `compliance`: software workloads and ISA validation

## Notes

CoreMark now reads the architectural `cycle/mcycle` CSR for timing. The
reported `Total ticks` value is the real core-cycle delta seen by software.

`Total time (secs)` is derived from `CORE_CLOCK_HZ` in
`coremark/core_portme.h`, which defaults to `100_000_000` to match the current
10 ns simulation clock period. If you change the simulated/synthesized clock,
update that constant so CoreMark's seconds conversion stays consistent.
