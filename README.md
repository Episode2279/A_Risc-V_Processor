# A_Risc-V_Processor

A two-wide, out-of-order RV32I processor written in SystemVerilog and
simulated with Verilator. It uses a physical register file (PRF), a reorder
buffer (ROB), and in-order retirement with precise traps.

## Features

- **Out-of-order core**: two instructions per cycle through fetch, decode,
  rename, issue, and retirement. 16-entry ROB, 48 physical registers, 16-entry
  unified issue queue, and 16-entry load/store queue (LSQ).
- **Branch prediction**: eight-table TAGE over a Bimodal base, a loop
  predictor, and a TAGE-SC-L-style statistical corrector within a 16 KiB
  logical budget, plus a 128-entry BTB and an 8-entry return-address stack.
  Several branches may be unresolved at once; a misprediction restores state
  from that branch's checkpoint.
- **Memory**: 4 KiB I-cache; 1 KiB D-cache with one MSHR, critical-word-first
  refill, and hit-under-miss; store-to-load forwarding in the LSQ; 8-entry
  Store Buffer for retired Stores.
- **ISA**: RV32I, Zicsr, and a machine-mode trap subset (ECALL, EBREAK, MRET,
  illegal-instruction and misalignment traps). No M/A/C extensions and no
  interrupts.

The default `make sim` run (one CoreMark iteration) takes 580,436 cycles for
859,534 instructions, an IPC of 1.48. See [SPEC.md](SPEC.md#current-performance).

## Requirements

Use Linux or WSL with `make`, `verilator` (tested with 5.020), `python3`, and
the `riscv64-unknown-elf-` GCC toolchain:

```sh
sudo apt update
sudo apt install make verilator gcc-riscv64-unknown-elf python3
```

## Quick start

```sh
make sim
```

This builds CoreMark, writes `build/images/insn.mem` and `data.mem`, lints the
RTL, builds the Verilator model, and runs it. A successful run ends with:

```text
***** simulation result: SUCCESS *****
```

Pass/fail is decided by the program's write to `tohost` (`0x0000FFF8`): 1 is
pass, any other nonzero value is fail, and no write before `MAX_CYCLES` is a
timeout. CoreMark also prints `Errors detected` because a simulated run is
shorter than the 10 seconds it needs for a valid score; this is expected.

Common options:

```sh
make run MAX_CYCLES=2000000   # rerun the existing model with a cycle cap
make sim TRACE=1              # also write build/traces/wave.vcd
make sim PIPE_DUMP=0          # skip the pipeline dump for a faster run
```

`ITERATIONS` in `coremark/core_portme.h` sets the CoreMark iteration count
(default 1).

## Make targets

`make help` lists every target. The main ones:

| Target | Purpose |
| --- | --- |
| `sim` | `coremark` + `lint` + `build` + `run` |
| `coremark`, `lint`, `build`, `run` | The individual steps of `sim` |
| `csr-smoke` | Run `test/csr_smoke.S`, then restore the CoreMark images |
| `kanata` | Convert the pipeline dump into a Kanata/Konata trace |
| `clean`, `clean-generated` | Remove simulation outputs / all generated files |

Unit tests (each builds its own small testbench):

| Target | Covers |
| --- | --- |
| `fetch-queue-smoke` | Fetch Queue enqueue, dequeue, flush |
| `bpu-smoke`, `loop-smoke`, `tage-smoke`, `tage-update-smoke`, `sc-smoke` | Bimodal/BTB, loop predictor, TAGE, TAGE update FIFO, statistical corrector |
| `icache-smoke`, `dcache-smoke` (`cache-smoke` runs both) | Cache hits, refills, back-pressure, flush, MMIO |
| `store-buffer-smoke`, `lsu-pending-smoke` | Store Buffer; out-of-order Load responses and wrong-path draining |
| `ooo-smoke`, `ooo-backend-smoke` | RAT/PRF/ROB/IQ/LSQ structures; end-to-end dispatch, execute, commit |
| `rv32i-compliance-smoke` | Decoder only: directed RV32I decode and trap-cause checks |

Optional flows that need downloads under the git-ignored `third_party/` and
`.tools/` directories:

- `make act4-run` runs the official ACT4 RV32I suite (39/39 tests pass). See
  [compliance/act4/README.md](compliance/act4/README.md).
- `make cbp-sample` or `make cbp-run CBP_TRACE=<trace.gz>` runs the branch
  predictor RTL on CBP2025 traces. See
  [verification/perf/cbp/README.md](verification/perf/cbp/README.md).

## Simulation output

- Bytes written to the UART address `0x0000FFE0` appear on the console and in
  `build/traces/simulation_output.txt`.
- At the end of a run the harness prints `PERF`, `BPU`, `CACHE I`, `CACHE D`,
  `SC`, and `LOOP` counter lines. These are simulation-only debug outputs, not
  software-visible CSRs.
- CoreMark reads the `cycle` CSR, so `Total ticks` is the real core cycle
  count. `Total time (secs)` assumes `CORE_CLOCK_HZ` (100 MHz) from
  `coremark/core_portme.h`.

## Documentation

| Document | Contents |
| --- | --- |
| [SPEC.md](SPEC.md) | Microarchitecture, parameters, current performance |
| [rtl/backend/docs/OoO.md](rtl/backend/docs/OoO.md) | Backend guarantees and known limitations |
| [rtl/frontend/bpu/README.md](rtl/frontend/bpu/README.md) | Branch predictor design, storage budget, A/B results |
| [rtl/memory/README.md](rtl/memory/README.md) | I-cache, D-cache, backing memories |
| [rtl/backend/execute/lsu/README.md](rtl/backend/execute/lsu/README.md) | LSQ, Store Buffer, memory ordering |

## Source layout

```text
rtl/core/           topCPU, the top level
rtl/common/         TypesPkg (shared parameters and types) and interfaces
rtl/frontend/       fetch and Fetch Queue, decode, branch prediction
rtl/backend/        dispatch, rename, scheduler, regfile, execute, retire, perf
rtl/memory/         I-cache, D-cache, backing memories, D-side wrapper
config/filelists/   ordered RTL file lists shared by all Verilator targets
verification/       unit and integration testbenches, CBP adapter
sim/verilator/      C++ simulation harness
coremark/           CoreMark port, linker scripts, image converters
test/               CSR smoke test
compliance/         ACT4 configuration and runner
tools/kanata/       pipeline-dump converters
fpga/boards/        placeholder for board integrations (none yet)
riscv-tests/        legacy hand-built test images, not used by the Makefile
```
