# Microarchitecture Specification

This document describes the default RTL configuration. Core-wide parameters
are in `rtl/common/TypesPkg.sv` and `rtl/core/topCPU.sv`; predictor
parameters are local to the modules in `rtl/frontend/bpu/`.

## Overview

The core is a two-wide, PRF-based out-of-order RV32I processor. Instructions
are renamed and enter the ROB in program order, issue from a unified queue
when their operands are ready, and retire in program order so that
architectural state and traps stay precise.

| Property | Value |
| --- | --- |
| Data, address, and instruction width | 32 bits (no compressed instructions) |
| Fetch and decode | 2 instructions per cycle |
| Rename and dispatch | 2 uops per cycle; branches, jumps, CSR, and serializing instructions dispatch only from lane 0 |
| Issue | 2 uops per cycle: two integer, or one integer/branch plus one memory/CSR |
| Writeback | 2 results per cycle |
| Retirement | 2 uops per cycle, including at most one Store and one branch |
| Reset vector | `0x00000000` |

## Pipeline

```text
F0   PC/PC+4 request to the I-cache and BPU in parallel
F1   instructions + predictions return; next PC selected
     8-entry Fetch Queue
     Decode -> Rename + Dispatch into ROB, issue queue, LSQ
     wait in the issue queue until operands are ready
     Issue + PRF read -> Execute (2 integer paths, 1 LSU)
     Writeback, wakeup, ROB completion
     In-order retirement
```

| Stage | Main RTL | Behavior |
| --- | --- | --- |
| Fetch | `DualIfStages`, `InstructionCache`, `BranchPredictionUnit` | F0 sends the `PC`/`PC+4` pair to the synchronous I-cache and BPU. F1 returns both instructions with their predictions and selects the next PC. A Taken prediction in slot 0 drops slot 1. |
| Fetch Queue | `FetchQueue` | 8 entries, 2 in and 2 out per cycle. Decouples F1 from decode; flushed on every redirect. |
| Decode | `IdStages`, `Decoder` | Combinational. Produces register indices, immediate, memory width, branch type, CSR operation, and decode exceptions. |
| Rename and dispatch | `DispatchControl`, `RenameStage` | Checks ROB, issue-queue, LSQ, and free-register capacity, renames through the speculative RAT, and writes the ROB, issue queue, and LSQ. Shares one combinational path with decode. |
| Issue | `IssueQueue`, `PhysicalRegisterFile` | Oldest-first selection; operands are read from the PRF in the issue cycle. |
| Execute | `BackendExecuteStage`, `OoOExecutionUnit`, `LoadStoreExecutionUnit` | Two integer/branch paths and one shared LSU. Branches resolve here. |
| Writeback | Execution-unit result registers | Write the PRF, wake waiting uops, and mark ROB entries complete. Wrong-path results are dropped. |
| Retire | `BackendCommitStage`, `ReorderBuffer` | Retires a completed in-order prefix, updates the committed RAT, frees old registers, takes traps, moves Stores to the Store Buffer, and sends branch training to the BPU. |

A uop may wait in the issue queue for any number of cycles while younger,
independent uops issue ahead of it. The ROB restores program order.

## Out-of-order resources

| Parameter | Value | Notes |
| --- | ---: | --- |
| `ROB_ENTRY_NUM` | 16 | Instruction window. Each entry also has a branch checkpoint slot (RAT, free list, predictor histories). |
| `PHYS_REG_NUM` | 48 | 32 architectural plus 16 rename registers. `xN` starts mapped to `pN`; `p32`-`p47` start free. |
| `UNIFIED_IQ_ENTRY_NUM` | 16 | Shared by integer, branch, CSR, and memory uops. |
| `LSQ_ENTRY_NUM` | 16 | Loads and Stores in program order. A memory uop also holds an issue-queue entry until its address issues. |
| `STORE_BUFFER_ENTRY_NUM` | 8 | Retired cacheable Stores waiting to write the D-cache. |
| `FETCH_QUEUE_ENTRIES` | 8 | Fetched instructions waiting for decode. |

**Issue queue.** Each cycle the queue offers three candidates: the oldest
ready memory/CSR uop, the oldest ready integer/branch uop, and one more
integer uop as a backup. If the memory uop cannot enter the LSU (LSQ ordering
or D-cache back-pressure), it stays in the queue and the two integer paths
take the other two candidates. At most two uops issue per cycle, and at most
one of them is a memory operation.

**PRF.** 12 combinational read ports: 4 for rename-time ready checks, 6 for
the three issue candidates, and 2 for retirement data. Two write ports.

**LSQ.** Each Store records its address and data separately. A Store leaves
the issue queue once its base register is ready; if its data register is not
ready yet, the LSQ captures the value later from the PRF writeback buses. A
Load issues only after every older Store has a known address. It then either
reads the D-cache or takes its data from the youngest older Store that covers
all of its bytes. A partial overlap, or overlap with a Store whose data is not
ready, makes the Load wait. Stores to the MMIO range block all younger Loads.

**Stores and memory.** No Store changes memory before it retires. Retired
cacheable Stores enter the Store Buffer and drain in order through the
write-through D-cache. A Load that overlaps a buffered Store waits for that
Store to drain; direct forwarding from the Store Buffer is turned off (see
[the LSU README](rtl/backend/execute/lsu/README.md)). MMIO Stores skip the
buffer and wait at the ROB head until older buffered Stores have drained.

**Recovery.** A branch misprediction keeps the branch, removes all younger ROB,
issue-queue, and LSQ entries in one cycle, restores the RAT, free list, and
predictor histories from the branch's checkpoint, and redirects fetch.
Exceptions are recorded in the ROB and taken when the entry reaches the head;
a trap flushes the whole backend and restores the committed RAT.

**Serialization.** CSR instructions, FENCE, FENCE.I, ECALL, EBREAK, and MRET
dispatch only into an empty backend (ROB, issue queue, LSQ, and Store Buffer
empty, D-cache idle), and no other instruction dispatches until they retire.

## Branch prediction

| Structure | Size |
| --- | --- |
| Bimodal base | 1,024 two-bit counters indexed by `PC[11:2]` |
| TAGE | 8 tables of 512 entries; history lengths 4/8/16/32/64/96/128/192; tags 7 to 14 bits |
| Speculative history | 192-bit direction history, 16-bit path history |
| Loop predictor | 64 entries with 10-bit trip counts; 32-entry speculative action log |
| Statistical corrector (SC) | 18 tables of signed 6-bit counters in five families (bias, global, local, IMLI, path); 256-entry local history table; adaptive threshold |
| TAGE update queue | 4 retired branches |
| BTB | 128 entries, 64 sets of 2 ways |
| Return-address stack | 8 entries |

A prediction goes through three steps: TAGE picks a direction, a confident
loop entry may replace it, and SC may correct the result. The `topCPU`
parameters `BPU_TAGE_ENABLE`, `BPU_LOOP_ENABLE`, and `BPU_SC_ENABLE` turn each
step off for A/B tests.

Speculative state (direction and path history, IMLI counter, loop iteration
counts) advances at fetch and is restored from the branch's ROB checkpoint on
a misprediction. Prediction tables (Bimodal, TAGE, loop, SC, BTB) are updated
only at retirement, so wrong-path branches never train them. The RAS is the
exception: its committed copy is still updated when a branch resolves.

The direction predictor uses 130,483 bits (15.93 KiB) under the CBP
storage-counting convention, and elaboration fails if a change exceeds 16 KiB
(`BPU_ENFORCE_CBP_STORAGE_LIMIT`). This is not the synthesized size: the
duplicated tag RAMs, checkpoints, BTB, and RAS are extra.

Details: [rtl/frontend/bpu/README.md](rtl/frontend/bpu/README.md).

## Memory system

| Parameter | Value | Notes |
| --- | --- | --- |
| `INS_ADDR_SIZE`, `DATA_ADDR_SIZE` | 64 KiB each | Separate instruction and data backing memories with registered reads |
| `ICACHE_BYTES`, `ICACHE_LINE_BYTES` | 4 KiB, 16 B | Direct-mapped, 256 sets |
| `DCACHE_SET_COUNT`, `DCACHE_LINE_BYTES` | 64, 16 B | 1 KiB, direct-mapped, write-through, no write-allocate |
| MMIO range | `0xFFE0`-`0xFFFF` | Uncached |
| `UART_TX_ADDR` | `0xFFE0` | Byte output to the simulation console |
| `FROMHOST_ADDR`, `TOHOST_ADDR` | `0xFFF0`, `0xFFF8` | Host mailboxes; `tohost` ends the simulation |

The I-cache looks up `PC` and `PC+4` every cycle, even when they are in
different lines. A miss stops fetch until the four-word line is refilled.

The D-cache accepts one Load hit per cycle. Its single MSHR returns the
requested word first and lets Loads to other sets hit during the refill. It
has no write-back, secondary-miss merging, or prefetching.

Details: [rtl/memory/README.md](rtl/memory/README.md).

## Traps and CSRs

- **Traps**: illegal instruction, ECALL, EBREAK, instruction-address
  misalignment, and load/store-address misalignment. A trap is taken when the
  instruction reaches the ROB head; it writes `mepc`, `mcause`, `mtval`, and
  `mstatus` and jumps to `mtvec` (direct mode only). MRET restores `mstatus`
  and returns to `mepc`.
- **CSRs**: `mstatus`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`,
  `mip`, `mcycle[h]`, `minstret[h]`; read-only `cycle[h]`, `time[h]`,
  `instret[h]`, `misa`, `mhartid`.
- `mie` and `mip` are plain registers; no interrupt source is connected.

## Current performance

Default `make sim` run: one CoreMark iteration compiled with
`-march=rv32i_zicsr -O2`, simulated with Verilator 5.020.

| Metric | Value |
| --- | --- |
| Whole run | 580,436 cycles, 859,534 instructions, IPC 1.481 |
| CoreMark timed region | 520,849 cycles, 800,063 instructions, IPC 1.536 |
| Dual-issue / single-issue cycles | 369,911 / 141,431 |
| ROB-full cycles | 15,150 |
| Conditional branches / mispredictions | 235,723 / 22,234 (9.43%) |
| I-cache line misses | 1.42 per 1,000 instructions |
| D-cache Load miss rate | 1.32% (0.90 per 1,000 instructions) |

These are cycle counts from RTL simulation, not a CoreMark score: the run is
too short to be valid, and no clock frequency has been measured by synthesis.
The core has no M extension, so CoreMark multiplications call libgcc's
`__mulsi3`, whose loop has a data-dependent branch for every multiplier bit.
This raises both the instruction count and the misprediction rate.

Predictor A/B results are in [the BPU README](rtl/frontend/bpu/README.md#coremark-ab-results);
CBP2025 trace results are in
[verification/perf/cbp/README.md](verification/perf/cbp/README.md).

## Changing parameters

- `PHYS_REG_NUM - 32` limits how many destination registers can be in flight.
- A larger `ROB_ENTRY_NUM` also enlarges the checkpoint arrays and recovery
  masks. Grow the PRF, issue queue, and LSQ with it, or one of them becomes
  the limit.
- The issue-queue and LSQ sizes are independent; a memory uop uses one entry
  in each.
- Cache sizes must be powers of two, with four-word lines.
- Predictor geometry changes must stay within the 16 KiB storage check.
- After a structural change, run `make lint`, every `*-smoke` target, and
  `make sim`, and compare the CoreMark cycle count.
