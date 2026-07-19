# A RISC-V Processor: Microarchitecture Specification

This document describes the current default RTL configuration. The central
size parameters are declared in `source/TypesPkg.sv`; some BPU parameters are
local to the modules under `source/functional/BPU`.

## Core overview

The core is a two-wide, PRF-based out-of-order RV32 processor. It can fetch,
decode, rename, dispatch, issue, complete, and retire up to two instructions per
cycle when resource and dependency constraints allow it. Instructions execute
out of order, while the ROB retires them in program order to maintain precise
architectural state.

| Property | Current value | Meaning |
| --- | ---: | --- |
| Datapath width | 32 bits | Integer operands, results, addresses, and PCs use `word_t`. |
| Instruction width | 32 bits | The current front end fetches uncompressed RV32 instructions. |
| Architectural registers | 32 | RISC-V `x0` through `x31`; `x0` is always zero. |
| Front-end width | 2 instructions/cycle | Two adjacent instructions can be fetched and decoded. |
| Rename/dispatch width | 2 uops/cycle | At most two uops reserve ROB, IQ, LSQ, and PRF resources each cycle. |
| Issue width | 2 uops/cycle | The unified scheduler has two issue ports. |
| Completion/writeback width | 2 uops/cycle | Up to two execution results can complete and update the PRF. |
| Retirement width | 2 uops/cycle | The ROB can retire a contiguous pair of completed uops. |

The two issue ports are not symmetric. Port 0 accepts all functional-unit
classes, while port 1 is used for ordinary integer or branch work supported by
the secondary execution path. There is one LSU, so two memory operations cannot
execute together. The current commit logic also permits at most one Store and
one branch to retire in a cycle because each has a single downstream update
path.

## Current pipeline organization

The core is best described as a sequence of logical pipeline stages separated
by a fetch-window register, queues, and execution-result registers:

```text
Fetch Request + Post-accept Fold/Hash
      |
      v
Registered TAGE Read + Prediction Response
      |
      v
Two-entry IF/ID Fetch Window
      |
      v
Decode -> Rename + Dispatch -> ROB / Unified IQ / LSQ
                                      |
                         wait until operands and port are ready
                                      |
                                      v
                          Issue + PRF Operand Read
                                      |
                                      v
                     Integer/Branch/CSR or LSU Execute
                                      |
                                      v
                       Completion + PRF Writeback/Wakeup
                                      |
                                      v
                         In-order Commit / Retirement
```

Unlike a classic five-stage in-order pipeline, an instruction may remain in the
Issue Queue for an arbitrary number of cycles, and independently executing
instructions can overtake it. ROB order, rather than a fixed sequence of
interstage registers, restores program order at retirement.

| Logical stage | Width | Main RTL | Current behavior |
| --- | ---: | --- | --- |
| 1. Fetch request and TAGE address | 2 instructions | `DualIfStages.sv`, `BranchPredictionUnit.sv`, `TageFoldedHistory.sv`, `TageHash.sv` | Reads the raw next-request `PC`/`PC+4` instructions. Post-accept or recovered GHR/Path History and precomputed folds generate the two synchronous TAGE table addresses. |
| 2. Prediction response and next PC | 2 instructions | `BranchPredictionUnit.sv`, `TageTable.sv`, `StatisticalCorrector.sv`, BTB/GShare/RAS | Registered request PC/instruction/history is aligned with the one-cycle TAGE and SC response. Provider/alternate selection produces the raw TAGE direction, SC may correct it, and target selection chooses the following request PC. A taken slot-0 response suppresses slot 1. |
| 3. Fetch window | 2 instructions | `DualIF_IDRegister.sv` | The physical IF/ID register holds the oldest two fetched instructions. It can replace both slots, slide slot 1 into slot 0 after single dispatch, stall, or flush. |
| 4. Decode | 2 instructions | `IdStages.sv`, `Decoder.sv` | Decodes RV32 control, architectural source/destination registers, immediates, memory width, branch type, CSR operation, and decode exceptions. This logic is combinational. |
| 5. Rename and dispatch | 2 uops | `BackendDispatchStage.sv`, `RenameStage.sv` | Checks ROB/IQ/LSQ/free-PRF capacity atomically, translates architectural registers through the speculative RAT, allocates physical destinations, and inserts accepted uops into the ROB and IQ; memory uops also enter the LSQ. |
| 6. Schedule, issue, and operand read | 2 uops | `BackendIssueStage.sv`, `IssueQueue.sv`, `PhysicalRegisterFile.sv` | Uops wait in the unified IQ until their sources are ready. Age-based selection chooses up to two port-compatible uops, and the PRF supplies their physical operands. |
| 7. Execute / memory access | Up to 2 uops | `BackendExecuteStage.sv`, `OoOExecutionUnit.sv`, `LoadStoreExecutionUnit.sv` | Port 0 runs integer/branch/CSR work or the single LSU; port 1 runs integer or branch work. Branches resolve here. Loads check LSQ ordering/forwarding and may read data memory; Stores record address/data without modifying memory. |
| 8. Completion, writeback, and wakeup | 2 results | Execution-unit result registers, PRF, ROB, IQ, LSQ | Registered results write the PRF, wake dependent IQ entries, and mark their ROB entries complete. Memory address/data state is written into the LSQ. Wrong-path completions are filtered during recovery. |
| 9. Commit and retirement | 2 uops | `BackendCommitStage.sv`, `ReorderBuffer.sv`, `RenameStage.sv` | Retires only a contiguous completed ROB prefix, updates the committed RAT, frees old physical registers, takes precise traps, commits Stores to memory, and enqueues retired branch training. |

### Physical boundaries versus logical stages

The BPU has an internal request/response boundary: request PC, instruction,
GHR/Path History, and synchronous TAGE table data are aligned across one clock.
The front end then has an explicit `DualIF_IDRegister`, but there is no separate
legacy ID/EX register between decode and rename. Decode, capacity checking, and
rename/dispatch form the combinational path that ends when accepted entries are
clocked into the ROB, IQ, LSQ, and PRF allocation state.

The IQ is the next major state boundary. Operand readiness determines how long
each uop remains there. Once an execution port accepts a uop, the integer and
load/store units register its completion and optional writeback result. The ROB
then records completion independently of other instructions, and the commit
stage waits until that entry reaches the head.

`MEMStages.sv` is the data-memory/MMIO wrapper rather than a conventional
in-order MEM pipeline register. Loads use the memory port during LSU execution;
Stores use it only at ROB retirement. This distinction is what guarantees that
a speculative Store cannot modify architectural memory.

### Branch flow and pipeline recovery

Prediction spans the fetch-request and registered-response stages, while branch
direction and target resolve in the execute stage. A misprediction redirects
the fetch PC, flushes the IF/ID
window, removes younger ROB/IQ/LSQ entries, restores RAT and free-list state,
and recovers the 10-bit GShare history, 64-bit TAGE direction history, and
16-bit TAGE Path History from the resolving branch's ROB-tagged checkpoints.
The resolving branch remains in the ROB and later retires normally. Tagged
tables, the GShare PHT, SC signed counters, BTB, and branch-statistics updates
occur at retirement, not on the speculative execute path.

Decode and execution exceptions are stored in the ROB. Even if a younger uop
has already completed, an exception changes architectural control flow only
when its entry reaches the ROB head, providing precise exceptions.

## Out-of-order window

| RTL parameter | Value | Derived width/capacity | Explanation |
| --- | ---: | ---: | --- |
| `ROB_ENTRY_NUM` | 16 | 4-bit ROB tag | Maximum number of in-flight instructions. Each entry records ordering, exception, destination-renaming, memory, and branch-training metadata. |
| `PHYS_REG_NUM` | 48 | 6-bit physical-register index | The PRF contains 32 initial architectural mappings plus 16 extra registers for speculative destinations. |
| `ISSUE_QUEUE_ENTRY_NUM` | 8 | See note below | Base integer scheduling capacity used when sizing the unified queue. |
| `LSQ_ENTRY_NUM` | 8 | 3-bit LSQ tag | Maximum number of in-flight Loads and Stores tracked in memory order. |

### ROB (`ROB_ENTRY_NUM`)

The 16-entry Reorder Buffer is the architectural ordering structure. Rename
allocates ROB entries in program order, execution marks them complete in any
order, and retirement removes only a completed prefix from the head. A branch
misprediction keeps the resolving branch and discards all younger entries.

Increasing the ROB allows the scheduler to look farther past cache, dependency,
or execution stalls, but it also increases the storage used by ROB entries and
the per-ROB-slot RAT, free-list, and GHR recovery checkpoints. The PRF, IQ, and
LSQ normally need to grow with the ROB, otherwise one of those structures will
become the effective window limit first.

### Physical Register File (`PHYS_REG_NUM`)

The PRF has 48 entries. At reset, architectural `xN` maps to physical `pN`, and
`p32` through `p47` form the initial free list. A destination-writing uop
allocates a new physical register; its previous mapping returns to the free list
only when the uop retires. Consequently, the current core can have at most 16
unretired destination mappings before physical-register pressure alone stops
rename.

The instantiated PRF has 10 combinational read ports and two writeback ports.
The large read-port count supplies dispatch checks, two execution lanes, and
retirement data in the current straightforward implementation; it is not an
indication of ten-wide execution.

### Unified Issue Queue

`BackendIssueStage` instantiates the unified queue with this expression:

```text
IQ depth = ISSUE_QUEUE_ENTRY_NUM + LSQ_ENTRY_NUM = 8 + 8 = 16 entries
```

Therefore, the current physical Issue Queue contains 16 entries, even though
`ISSUE_QUEUE_ENTRY_NUM` itself is 8. Memory uops occupy both the unified IQ and
the separate LSQ until they issue. The IQ can accept, wake, select, and issue up
to two uops per cycle. Selection is age-based among ready uops with a compatible
execution port; an uop leaves the IQ only when that port accepts it.

### Load/Store Queue (`LSQ_ENTRY_NUM`)

The eight-entry LSQ preserves memory ordering and retains Load/Store address and
Store-data state. Loads may bypass older Stores with known non-overlapping
addresses and may forward from the youngest covering older Store. A Load waits
if an older Store has an unknown address, unavailable data, or only a partial
overlap. Stores become externally visible only when their ROB entries retire.

## Branch prediction

The default direction path is a five-table TAGE predictor over a GShare
base/alternate, followed by a compact statistical corrector (SC-Lite). The
standalone local-history predictor and Tournament chooser have been removed.
Target prediction uses a two-way BTB, direct-JAL decoding, and a RAS.
`BPU_SC_ENABLE=0` bypasses only SC for raw-TAGE A/B testing;
`BPU_TAGE_ENABLE=0` selects pure GShare.

| Variable/module parameter | Value | Structure produced | Explanation |
| --- | ---: | ---: | --- |
| `BPU_HISTORY_WIDTH` | 10 bits | 1,024-entry GShare PHT | Defines the speculative GShare GHR length and index width. |
| `TAGE_HISTORY_WIDTH` | 64 bits | 64-bit speculative TAGE GHR | Maximum global correlation history available to the tagged tables and SC. |
| `TAGE_PATH_HISTORY_WIDTH` | 16 bits | 16-bit control-path signature | Distinguishes equal direction patterns reached through different control-flow paths. |
| `TAGE_TABLE_NUM` | 5 | Histories 4/8/16/32/64 | Number of tagged Provider tables searched in parallel. |
| `TAGE_TABLE_ENTRIES` | 256/table | 1,280 tagged entries | Every table has an 8-bit Index. |
| TAGE tag widths | 7/8/9/10/11 bits | 23,040 physical Tag-RAM bits | Two read-lane Tag replicas provide two synchronous lookups; CBP logical accounting charges one copy. |
| `TAGE_GENERATION_WIDTH` | 5 bits/entry | 6,400 generation bits | Thirty-two entry versions reject stale queued retirement updates. |
| TAGE shadow state | 6 bits/entry | 7,680 valid/counter/useful bits | Shared between the two Tag-RAM read replicas. |
| SC PC bias | 256 × signed 6-bit | 1,536 bits | PC-only residual tendency; its value is weighted by two in the score. |
| SC GEHL | 4 × 128 × signed 6-bit | 3,072 bits | Uses direction histories 3/7/15/31 plus independent PC/Path hashes. |
| SC folds | 4 × 7-bit | 28 bits | Incrementally maintained folds keep full-GHR compression off the request path. |
| `BPU_SC_LOW_CONFIDENCE_THRESHOLD` | 23 | Score interval `[-23,+23]` | Low-confidence retired predictions train SC even when correct. |
| `BPU_SC_WEAK_BASE_WEIGHT` | 20 | Signed weak TAGE vote | Protects an untrained SC from immediately overriding the base decision. |
| `BPU_SC_STRONG_BASE_WEIGHT` | 62 | Signed strong TAGE vote | Gives a non-weak tagged Provider more resistance to correction. |
| `TageUpdateQueue` depth | 4 updates | Retirement FIFO | Decouples branch retirement from the single table-training port. |
| `BTB_ENTRIES` | 128 | 64 sets × 2 ways | Caches branch and indirect-jump target addresses. |
| RAS `DEPTH` | 8 | 8 return addresses | Predicts targets of recognized function returns. |

### TAGE Provider selection

`TagePredictor.sv` searches five independent 256-entry tagged tables with
history lengths 4, 8, 16, 32, and 64. Each logical entry contains a valid bit,
a PC/direction/path tag, a three-bit saturating direction counter, a two-bit
useful counter, and a five-bit generation. The Tag RAM is physically replicated
for two prediction lanes; including both Tag copies and shared shadow state, the
five tables use 37,120 physical bits before other BPU structures. This physical
figure is deliberately distinct from the CBP logical-capacity count below.

`TageFoldedHistory.sv` incrementally maintains three direction-history folds
for each table: an 8-bit Index fold, a Tag-width fold, and a
`Tag-width-1` fold. Across the five tables these live registers use 125 bits.
For a history window of length `H` and fold width `C`, one conditional branch
rotates the existing fold, XORs the incoming direction into bit zero, and XORs
the outgoing `GHR[H-1]` into bit `H mod C`. Normal prediction therefore reads
precomputed folds rather than repeatedly folding up to 64 history bits.
Recovery reconstructs all folds from the restored full GHR.

`TageHash.sv` combines those folds with PC and the 16-bit Path History. Index
and Tag use different CRC polynomials, seeds, PC/path bit orders, and per-table
rotations. The transforms elaborate into fixed XOR matrices. Separate Index and
Tag mixing turns many Index aliases into Tag mismatches instead of correlated
false hits.

The longest matching table is the Provider. The next-shortest match is the
Alternate; if no shorter table hits, GShare is the Alternate. A new Provider
with usefulness zero and a weak direction counter may temporarily use the
Alternate. Six four-bit `useAlternateOnNew` counters group Providers by history
class and PC class. The result after Provider/Alternate/UAN selection is saved
as `tagePrediction`, the raw direction before SC.

Only a raw TAGE direction error can allocate a tagged entry:

```text
tageDirectionMispredict = tagePrediction != actualTaken
```

BTB misses, target-only errors, and harmful SC overrides therefore do not
pollute TAGE. An SC-corrected raw TAGE miss still triggers normal TAGE learning.
An eight-bit LFSR rotates allocation priority among replaceable tables longer
than the Provider, and one quarter of attempts may allocate a second distinct
entry. Grouped pressure counters and incremental aging gradually release stale
usefulness-protected entries.

Each table is split into two 128-row banks. Index bit zero selects the bank and
the remaining seven bits select the row. Each bank has one Tag-RAM copy per
fetch lane, while valid/counter/useful/generation shadow state is shared. Reads
are synchronous and registered. Allocation, Provider update, pressure, and
aging have explicit same-cycle forwarding. A saved generation must still match
at retirement, so a delayed update cannot modify a replacement occupant.

### Statistical corrector

`StatisticalCorrector.sv` contains one 256-entry PC-bias table and four
128-entry GEHL tables. All counters are signed six-bit values and reset to zero.
The GEHL histories are 3, 7, 15, and 31 directions; four incremental seven-bit
folds are maintained beside the existing TAGE folds. SC does not duplicate the
64-bit GHR or 16-bit Path History.

The four GEHL tables and PC-bias table are read synchronously in parallel with
the tagged TAGE tables. Their registered response is combined with the raw
TAGE/UAN decision in the same response cycle, so SC adds no new front-end stage:

```text
componentScore = 2*bias + gehl3 + gehl7 + gehl15 + gehl31
baseVote       = tagePrediction ? +(strong ? 62 : 20)
                                : -(strong ? 62 : 20)
finalScore     = componentScore + baseVote
```

A positive score predicts Taken, a negative score predicts Not-Taken, and zero
keeps `tagePrediction`. The post-SC result is stored in `finalPrediction`. The
decision is low-confidence when `abs(finalScore) <= 23`. At retirement, all SC
counters move one step toward the actual result when `finalPrediction` was
wrong or the saved decision was low-confidence. Same-address request/update
collisions forward the trained value. Squashed branches never reach this path.

Prediction metadata containing GHR, Path History, Provider/Alternate decisions,
Provider generation, raw `tagePrediction`, final `finalPrediction`, and SC
confidence travels through the fetch window into the ROB. Retired conditional
updates enter the four-entry FIFO and train through one shared update stream.

### Speculative history and GShare

TAGE has an independent 64-bit speculative direction history and a 16-bit
speculative Path History. Direction history advances only for conditional
branches. Path History advances for every accepted conditional branch, JAL, or
JALR. Slot 1 is queried with the virtual fall-through state after Slot 0. Each
renamed control-flow instruction receives a ROB-tagged history checkpoint.
Execute-stage recovery restores the pre-branch checkpoint and appends the
resolving control event; precise traps restore retirement-updated committed
history shadows.

GShare uses a separate 10-bit GHR and a 1,024-entry table of two-bit counters:

```text
GShare index = PC[11:2] XOR GHR
```

Its history also updates speculatively and recovers from a ROB-tagged
checkpoint. GShare counters train only from the in-order retirement stream.
Increasing `BPU_HISTORY_WIDTH` doubles the PHT for every added bit but is not
automatically more accurate because unrelated older branches may add noise.

### CBP 4 KiB logical-state accounting

The project enforces the following logical conditional-direction-predictor
budget with elaboration checks:

| Charged logical state | Bits |
| --- | ---: |
| Existing TAGE + GShare baseline | 27,917 |
| SC counters: `256*6 + 4*128*6` | 4,608 |
| Four SC incremental folds: `4*7` | 28 |
| **Total** | **32,553** |
| CBP 4 KiB limit | 32,768 |
| **Remaining** | **215** |

The result is 4,069.125 bytes, leaving 26.875 bytes. The deleted standalone
Local predictor occupied `256*10 + 1024*2 = 4,608` bits, and the deleted
512-entry two-bit chooser occupied 1,024 bits. The new SC counter budget equals
the old Local predictor but no longer pays the chooser cost.

This is a CBP-style logical-state accounting convention, not the literal
synthesized RAM usage. Dual-lane Tag copies, physical banking/replication needed
for multiported reads, committed-history shadows, ROB recovery checkpoints,
update FIFOs, prediction metadata, BTB, and RAS remain real physical hardware
but are outside this logical conditional-direction-predictor budget.

### BTB and RAS

The BTB contains 128 entries arranged as 64 two-way sets. Its set index is
`PC[7:2]`; the remaining upper PC bits form the tag. A Taken retired
control-flow instruction installs its target. Direct JAL targets are calculated
from the instruction without waiting for a BTB entry.

The Return Address Stack holds eight predicted return addresses and maintains
speculative and committed views. Calls push `PC + 4`, and recognized returns pop
the top entry. The current RAS committed shadow is still updated at execute
resolution; adding a per-branch RAS checkpoint/action log remains future work.

### CoreMark A/B result

The following runs use the same RV32I CoreMark image with 10 iterations,
2,236,266 retired conditional branches, and pipeline dumping disabled:

| Direction mode | Cycles | Retired | IPC | Direction misses | Miss rate | Direction MPKI |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| TAGE + GShare, SC disabled | 5,727,837 | 8,062,058 | 1.4075 | 233,869 | 10.4580% | 29.0086 |
| TAGE + GShare + SC-Lite | 5,698,473 | 8,062,067 | 1.4148 | 219,300 | 9.8065% | 27.2015 |

SC changes 35,782 raw TAGE decisions in the enabled run. Of those, 24,782
correct a raw miss and 11,000 harm a raw-correct decision, producing 13,782 net
beneficial overrides on that trajectory. Relative to SC-off, cycles decrease
about 0.513%, IPC increases about 0.519%, and direction MPKI falls by 1.8071.
The cross-run miss delta need not exactly equal the within-run override balance
because SC changes speculative history and subsequent predictor training.

These are simulator performance comparisons, not an official CoreMark score.
Both runs produce the expected CRCs and terminate successfully through
`tohost`. CoreMark still prints its standard `Errors detected` duration warning
because ten simulated iterations represent less than the required ten seconds.

## Memory and address parameters

| RTL parameter | Value | Explanation |
| --- | ---: | --- |
| `INS_ADDR_SIZE` | 65,536 bytes | Size of the modeled instruction memory. |
| `DATA_ADDR_SIZE` | 65,536 bytes | Size of the modeled data memory. |
| `RESET_VECTOR` | `0x00000000` | PC used after reset. |
| `UART_TX_ADDR` | `0x0000FFE0` | Byte-oriented simulation UART output. |
| `FROMHOST_ADDR` | `0x0000FFF0` | Host-to-target simulation mailbox. |
| `TOHOST_ADDR` | `0x0000FFF8` | Target-to-host completion mailbox. |

The internal instruction and data memories use 16-bit byte indexes because
their modeled capacities are 64 KiB, while architectural PCs and calculated
addresses remain 32 bits.

## Parameter relationships and tuning guidance

- `PHYS_REG_NUM` must remain greater than `REG_NUM`; the difference determines
  the maximum number of simultaneously live speculative destination mappings.
- Increasing `ROB_ENTRY_NUM` also enlarges branch-recovery checkpoint arrays and
  the younger-entry recovery masks used by the IQ and LSQ.
- The actual unified IQ capacity is the sum of `ISSUE_QUEUE_ENTRY_NUM` and
  `LSQ_ENTRY_NUM`; change both with that relationship in mind.
- `BPU_HISTORY_WIDTH=N` creates `2^N` GShare counters. Increasing it changes
  both the GShare PHT size and the GShare checkpoint width.
- `TAGE_HISTORY_WIDTH` is independent of `BPU_HISTORY_WIDTH`; increasing it
  does not enlarge the GShare PHT. TAGE/SC table counts, entries, history
  schedules, fold widths, and tags must be changed consistently. Any change
  must also update and satisfy the CBP logical-storage assertions.
- Larger structures increase the amount of exploitable instruction-level
  parallelism or reduce predictor aliasing, but also increase FPGA area,
  simulation cost, reset work, and potentially the critical path.
- After changing structural parameters, run at least `make lint`,
  `make bpu-smoke`, `make tage-smoke`, `make sc-smoke`, `make ooo-smoke`,
  `make ooo-backend-smoke`, and
  `make rv32i-compliance-smoke`, followed by a CoreMark comparison.
