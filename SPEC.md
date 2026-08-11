# A RISC-V Processor: Microarchitecture Specification

This document describes the current default RTL configuration. The central
size parameters are declared in `rtl/common/TypesPkg.sv`; some BPU parameters
are local to the modules under `rtl/frontend/bpu`.

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

The scheduler has two accepted-issue slots but does not permanently bind one
slot to the LSU. It forms an oldest memory/CSR candidate, an oldest
integer/branch candidate, and a second ordinary-integer fallback candidate. If
the memory candidate can enter the single shared LSU, the core issues it with
one integer/branch uop. If LSQ ordering or sustained D-cache request
back-pressure blocks it, the memory uop remains in the IQ and the two integer
execution paths may instead accept the two non-memory candidates. Total IQ
acceptance remains at most two uops per cycle, and two memory operations cannot
execute together. The current commit logic also permits at most one Store and
one branch to retire in a cycle because each has a single downstream update
path.

## Current pipeline organization

The core is best described as a sequence of logical pipeline stages separated
by a fetch-window register, queues, and execution-result registers:

```text
F0 PC Pair + Parallel I-cache / BPU Request
      |
      v
F1 Synchronous I-cache / Prediction Response
      |        (an I-cache miss blocks for refill)
      v
Eight-entry Fetch Queue
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
| 1. F0 fetch request | 2 instruction addresses | `DualIfStages.sv`, `InstructionCache.sv`, `BranchPredictionUnit.sv`, `TageFoldedHistory.sv`, `TageHash.sv` | An accepted `PC`/`PC+4` pair launches the two-address synchronous I-cache tag/data lookup and the PC-indexed BPU lookup in parallel. No instruction word is read combinationally in F0. Post-accept or recovered GHR/Path History and precomputed folds generate the synchronous TAGE/SC table addresses. |
| 2. F1 cache/prediction response and next PC | 2 instructions | `InstructionCache.sv`, `BranchPredictionUnit.sv`, `TageTable.sv`, `LoopPredictor.sv`, `StatisticalCorrector.sv`, BTB/Bimodal/RAS | I-cache hit data is aligned with the retained BPU request context and registered predictor response. Provider/alternate selection produces raw TAGE, a confident Loop entry may replace it, SC may make the final correction, and target selection chooses the following request PC. A taken slot-0 response suppresses slot 1. An I-cache miss blocks this request, refills each missing 16-byte line with four backing-memory words, and internally retries the lookup before F1 becomes valid. |
| 3. Fetch queue | 8 instructions, 2-wide enqueue/dequeue | `FetchQueue.sv` | Decouples synchronous F1 responses from decode/rename. It accepts a predicted bundle atomically, supplies the oldest two instructions, preserves a lone younger instruction after single dispatch, and flushes all speculative contents on redirect. |
| 4. Decode | 2 instructions | `IdStages.sv`, `Decoder.sv` | Decodes RV32 control, architectural source/destination registers, immediates, memory width, branch type, CSR operation, and decode exceptions. This logic is combinational. |
| 5. Rename and dispatch | 2 uops | `BackendDispatchStage.sv`, `RenameStage.sv` | Checks ROB/IQ/LSQ/free-PRF capacity atomically, translates architectural registers through the speculative RAT, allocates physical destinations, and inserts accepted uops into the ROB and IQ; memory uops also enter the LSQ. |
| 6. Schedule, issue, and operand read | 2 uops | `BackendIssueStage.sv`, `IssueQueue.sv`, `PhysicalRegisterFile.sv` | Uops wait in the unified IQ until their sources are ready. Age-based selection forms memory/CSR, integer/branch, and second-integer fallback candidates. The backend accepts at most two, and the PRF supplies all candidate operands. |
| 7. Execute / memory access | Up to 2 accepted uops | `BackendExecuteStage.sv`, `OoOExecutionUnit.sv`, `LoadStoreExecutionUnit.sv`, `DataCache.sv` | One shared LSU and two integer paths are available. A ready memory uop pairs with one integer/branch uop; an LSQ/cache-blocked memory candidate stays in the IQ while two ordinary integer-capable paths are used. Loads check LSQ forwarding/order before issuing a tagged D-cache request. A Store may calculate its address as soon as the base source is ready; its data either arrives with that issue or is captured later by LSQ writeback snooping. |
| 8. Completion, writeback, and wakeup | 2 results | Execution-unit result registers, PRF, ROB, IQ, LSQ | Registered results write the PRF, wake dependent IQ entries, and mark their ROB entries complete. Memory address/data state is written into the LSQ. Wrong-path completions are filtered during recovery; a killed completion is consumed during the active filter window even if an LSU result has lane-0 priority. |
| 9. Commit and retirement | 2 uops | `BackendCommitStage.sv`, `ReorderBuffer.sv`, `RenameStage.sv`, `StoreBuffer.sv` | Retires only a contiguous completed ROB prefix, updates the committed RAT, frees old physical registers, takes precise traps, transfers cacheable Stores into an eight-entry committed Store Buffer, preserves MMIO ordering, and enqueues retired branch training. |

### Physical boundaries versus logical stages

The front end has an F0/F1 synchronous request/response boundary. The accepted
F0 PC pair enters the I-cache and BPU together; I-cache tag/data and TAGE/SC
tables are read synchronously. The BPU retains the corresponding PC/history
context across an I-cache miss, so its prediction metadata is not paired with a
later request by mistake. Instruction words first become available with the F1
I-cache response. The front end then has an explicit eight-entry `FetchQueue`, but
there is no separate
legacy ID/EX register between decode and rename. Decode, capacity checking, and
rename/dispatch form the combinational path that ends when accepted entries are
clocked into the ROB, IQ, LSQ, and PRF allocation state.

The IQ is the next major state boundary. Operand readiness determines how long
each uop remains there. Once an execution port accepts a uop, the integer and
load/store units register its completion and optional writeback result. The ROB
then records completion independently of other instructions, and the commit
stage waits until that entry reaches the head.

`MEMStages.sv` contains the D-cache and the synchronous data-memory/MMIO backing
store rather than a conventional in-order MEM pipeline register. Non-forwarded
Loads use its tagged request/response port during LSU execution. Cacheable
Stores enter the committed Store Buffer at ROB retirement and drain to the
D-cache in order. A cacheable Store is write-through and does not allocate on a
miss. This retirement boundary guarantees that a speculative Store cannot
modify architectural memory.

### Branch flow and pipeline recovery

Prediction spans the fetch-request and registered-response stages, while branch
direction and target resolve in the execute stage. A misprediction redirects
the fetch PC, flushes the Fetch Queue, removes younger ROB/IQ/LSQ entries,
restores RAT and free-list state,
and recovers the 192-bit TAGE direction history and
16-bit TAGE Path History from the resolving branch's ROB-tagged checkpoints.
The resolving branch remains in the ROB and later retires normally. Tagged
tables, the Bimodal PHT, SC signed counters, BTB, and branch-statistics updates
occur at retirement, not on the speculative execute path.

Decode and execution exceptions are stored in the ROB. Even if a younger uop
has already completed, an exception changes architectural control flow only
when its entry reaches the ROB head, providing precise exceptions.

## Out-of-order window

| RTL parameter | Value | Derived width/capacity | Explanation |
| --- | ---: | ---: | --- |
| `ROB_ENTRY_NUM` | 16 | 4-bit ROB tag | Maximum number of in-flight instructions. Each entry records ordering, exception, destination-renaming, memory, and branch-training metadata. |
| `PHYS_REG_NUM` | 48 | 6-bit physical-register index | The PRF contains 32 initial architectural mappings plus 16 extra registers for speculative destinations. |
| `UNIFIED_IQ_ENTRY_NUM` | 16 | 5-bit occupancy count | Total capacity of the single unified scheduler; independent of LSQ capacity. |
| `LSQ_ENTRY_NUM` | 16 | 4-bit LSQ tag | Maximum number of in-flight Loads and Stores tracked in memory order. |
| `STORE_BUFFER_ENTRY_NUM` | 8 | 4-bit occupancy count | Maximum number of architecturally committed cacheable Stores waiting to drain. |

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

The instantiated PRF has 12 combinational read ports and two writeback ports.
The large read-port count supplies dispatch checks, two execution lanes, and
retirement data in the current straightforward implementation; it is not an
indication of ten-wide execution.

### Unified Issue Queue

`BackendIssueStage` instantiates the unified queue directly from its own
parameter:

```text
IQ depth = UNIFIED_IQ_ENTRY_NUM = 16 entries
```

Memory uops occupy both the unified IQ and the separate LSQ until their address
operation issues, but those structures are no longer sized by one another.
Increasing the LSQ does not add scheduler entries, and increasing the IQ does
not create memory-order entries. The IQ can accept, wake, select, and issue up
to two uops per cycle. It exposes a third candidate only for ready-aware
fallback: when the selected memory uop is blocked, two integer uops may consume
the two accepted-issue slots. Selection remains age-based, and a uop leaves the
IQ only when its selected execution path actually accepts it. In particular,
LSU `Valid` is suppressed whenever memory IQ `Ready` is suppressed, preventing
a request from launching while a stale copy remains in the IQ.

### Load/Store Queue (`LSQ_ENTRY_NUM`)

The 16-entry LSQ preserves memory ordering and retains Load/Store address and
Store-data state. Each Store records separate `addressReady` and `dataReady`
bits plus the physical-register tag of its data source. A Store leaves the IQ
once its address source is ready. If its data is already ready, the LSU writes
address and data together; otherwise the LSQ later captures the data by
snooping the two PRF writeback buses. ROB retirement still requires both bits,
so early address generation cannot expose an incomplete Store.

Loads may bypass older Stores with known non-overlapping
addresses and may forward from the youngest covering older Store. A Load waits
if an older Store has an unknown address, unavailable data, or only a partial
overlap. Stores become externally visible only when their ROB entries retire.
Retirement actually transfers a cacheable Store into the committed Store
Buffer; the backing-memory write may occur later, but never earlier.

### Tagged pending Loads and committed Store Buffer

`LoadStoreExecutionUnit` keeps one pending-metadata slot per ROB tag. An
accepted non-forwarded Load records its destination physical register, address,
and writeback intent in that slot; the tagged D-cache response later selects
that metadata independently of response order. Recovery marks affected slots
as killed rather than trying to cancel an already accepted cache transaction.
The response is still drained, but it creates neither a ROB completion nor a
PRF writeback.

Cacheable Stores leave the LSQ at retirement and enter the separate eight-entry
committed FIFO. This Store Buffer is not speculative and therefore has no
branch-flush input. It drains oldest first through the write-through D-cache.
The `StoreBuffer` module retains and tests its newest-to-oldest byte-merge query,
but the backend does not currently use its direct full-forward result. A Load
with no byte overlap may pass the committed buffer; any overlap, including full
coverage, waits until the relevant Store drains. This guard avoids the
zero-latency direct-completion path that exposed a CoreMark list-CRC error.
Diagnostic comparison against an architectural memory shadow found the
forwarded bytes correct, so completion/recovery integration remains the likely
race rather than the byte-merge calculation.
Forwarding from older uncommitted Stores inside the LSQ remains enabled. MMIO
Stores bypass the buffer, remain at the ROB head until accepted, and wait for
older buffered Stores. Serializing operations require the ROB/IQ/LSQ and Store
Buffer to be empty and the D-cache
wrapper to report idle, which includes an accepted backing-memory transaction.

## Branch prediction

The default direction path is an eight-table TAGE predictor over a Bimodal
base/alternate, followed by a counted-loop predictor and a multi-component
TAGE-SC-L-style statistical corrector. The
standalone local-history predictor and Tournament chooser have been removed.
Target prediction uses a two-way BTB, direct-JAL decoding, and a RAS.
`BPU_SC_ENABLE=0` bypasses only SC for raw-TAGE A/B testing;
`BPU_LOOP_ENABLE=0` bypasses only the Loop Predictor;
`BPU_TAGE_ENABLE=0` selects pure Bimodal.

| Variable/module parameter | Value | Structure produced | Explanation |
| --- | ---: | ---: | --- |
| `BPU_BASE_INDEX_WIDTH` | 10 bits | 1,024-entry Bimodal PHT | Defines the PC-index width; Bimodal has no GHR. |
| `TAGE_HISTORY_WIDTH` | 192 bits | 192-bit speculative TAGE GHR | Maximum global correlation history available to the tagged tables and SC. |
| `TAGE_PATH_HISTORY_WIDTH` | 16 bits | 16-bit control-path signature | Distinguishes equal direction patterns reached through different control-flow paths. |
| `TAGE_TABLE_NUM` | 8 | Histories 4/8/16/32/64/96/128/192 | Number of tagged Provider tables searched in parallel. |
| `TAGE_TABLE_ENTRIES` | 512/table | 4,096 tagged entries | Every table has a 9-bit Index. |
| TAGE tag widths | 7/8/9/10/11/12/13/14 bits | 43,008 logical tag bits | Two read-lane Tag replicas provide two synchronous lookups; logical accounting charges one copy. |
| `TAGE_GENERATION_WIDTH` | 5 bits/entry | 20,480 generation bits | Thirty-two entry versions reject stale queued retirement updates. |
| TAGE shadow state | 6 bits/entry | 24,576 valid/counter/useful bits | Shared between the two Tag-RAM read replicas. |
| Loop table | 64 entries | 2,752 bits | Learns stable trip counts for backward conditional loops; uses 12-bit tags and 10-bit counts. |
| Loop speculative action log | 32 actions | Recovery-only state | Tracks predicted loop iterations and is truncated to a ROB checkpoint on recovery. |
| SC Multi-Bias | 2 × 256 × signed 6-bit | 3,072 bits | Combines a pure PC tendency with a PC/short-history/base-confidence tendency; the family sum is half-weighted. |
| SC Global GEHL | 6 × 256 × signed 6-bit | 9,216 bits | Uses global histories 2/6/12/24/48/192 with independent PC/Path mixing; its family sum is half-weighted. |
| SC Local history/GEHL | 256 × 12-bit LHT + 4 × 512 × signed 6-bit | 15,360 bits | Learns correlations tied to the recent outcomes of the same PC. |
| SC IMLI GEHL | 3 × 256 × signed 6-bit | 4,608 bits | Uses pure IMLI, IMLI+global, and IMLI+global/path modes around a speculative, recoverable 10-bit iteration count. |
| SC Path GEHL | 3 × 256 × signed 6-bit | 4,608 bits | Uses 4/8/16-bit control-path windows independent of direction-only global history. |
| SC adaptive threshold | 32 × signed 6-bit | 192 bits | Per-PC-class feedback makes correction/training more conservative after harmful overrides. |
| SC folds | 6 × 8-bit | 48 bits | Incrementally maintained global folds keep 192-bit compression off the request path. |
| `BPU_SC_LOW_CONFIDENCE_THRESHOLD` | 23 | Score interval `[-23,+23]` | Low-confidence retired predictions train SC even when correct. |
| `BPU_SC_WEAK_BASE_WEIGHT` | 20 | Signed weak TAGE vote | Protects an untrained SC from immediately overriding the base decision. |
| `BPU_SC_STRONG_BASE_WEIGHT` | 62 | Signed strong TAGE vote | Gives a non-weak tagged Provider more resistance to correction. |
| `TageUpdateQueue` depth | 4 updates | Retirement FIFO | Decouples branch retirement from the single table-training port. |
| `BTB_ENTRIES` | 128 | 64 sets × 2 ways | Caches branch and indirect-jump target addresses. |
| RAS `DEPTH` | 8 | 8 return addresses | Predicts targets of recognized function returns. |

### TAGE Provider selection

`TagePredictor.sv` searches eight independent 512-entry tagged tables with
history lengths 4, 8, 16, 32, 64, 96, 128, and 192. Each logical entry contains a valid bit,
a PC/direction/path tag, a three-bit saturating direction counter, a two-bit
useful counter, and a five-bit generation. The Tag RAM is physically replicated
for two prediction lanes; including both Tag copies and shared shadow state, the
eight tables use more physical bits than the charged logical copy because the
Tag RAM is duplicated for both fetch lanes. This physical figure is deliberately
distinct from the CBP logical-capacity count below.

`TageFoldedHistory.sv` incrementally maintains three direction-history folds
for each table: a 9-bit Index fold, a Tag-width fold, and a
`Tag-width-1` fold. Across the eight tables these live registers use 232 bits.
For a history window of length `H` and fold width `C`, one conditional branch
rotates the existing fold, XORs the incoming direction into bit zero, and XORs
the outgoing `GHR[H-1]` into bit `H mod C`. Normal prediction therefore reads
precomputed folds rather than repeatedly folding up to 192 history bits.
Recovery reconstructs all folds from the restored full GHR.

`TageHash.sv` combines those folds with PC and the 16-bit Path History. Index
and Tag use different CRC polynomials, seeds, PC/path bit orders, and per-table
rotations. The transforms elaborate into fixed XOR matrices. Separate Index and
Tag mixing turns many Index aliases into Tag mismatches instead of correlated
false hits.

The longest matching table is the Provider. The next-shortest match is the
Alternate; if no shorter table hits, Bimodal is the Alternate. A new Provider
with usefulness zero and a weak direction counter may temporarily use the
Alternate. Eight four-bit `useAlternateOnNew` counters group Providers by history
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

Each table is split into two 256-row banks. Index bit zero selects the bank and
the remaining eight bits select the row. Each bank has one Tag-RAM copy per
fetch lane, while valid/counter/useful/generation shadow state is shared. Reads
are synchronous and registered. Allocation, Provider update, pressure, and
aging have explicit same-cycle forwarding. A saved generation must still match
at retirement, so a delayed update cannot modify a replacement occupant.

### Loop Predictor

`LoopPredictor.sv` is a 64-entry direct-mapped counted-loop predictor. Each
entry contains valid, a 12-bit hashed-PC tag, the learned 10-bit trip count, a
10-bit committed iteration count, a three-bit confidence counter, a two-bit
age counter, the repeated-loop direction, and a four-bit generation. New
entries are allocated only for retired Taken backward conditional branches;
this avoids spending entries on forward branches and irregular control flow.

A matching entry predicts the repeated direction while the speculative next
iteration is below the learned trip count, then predicts the opposite direction
for the loop exit. It may override raw TAGE only after its confidence saturates
at seven. The selected result is saved as `preScPrediction`; SC then receives
that direction as its base vote. A confident Loop result is treated as a strong
base so weak SC evidence cannot easily overturn a learned trip count.

The table itself trains only from retired branches. Prediction-time iteration
changes are held in a 32-entry speculative action log instead of modifying the
committed table state. Every renamed control-flow instruction saves the
corresponding action-log tail in its ROB checkpoint. On a branch recovery, the
log discards younger actions, restores the resolving branch's pre-prediction
iteration, and appends its actual outcome. Entry generation and tag checks keep
old checkpoints from modifying a replacement occupant.

### Statistical corrector

`StatisticalCorrector.sv` contains five feature families, all using signed
six-bit counters: two 256-entry Multi-Bias tables, six 256-entry Global GEHL
tables, four 512-entry Local GEHL tables backed by a 256-entry 12-bit local
history table, three 256-entry IMLI GEHL tables, and three 256-entry Path GEHL
tables. Global history lengths are 2/6/12/24/48/192. Six incremental eight-bit
folds are maintained beside the TAGE folds, so SC does not duplicate or
recompress the 192-bit GHR on the prediction critical path.

The Local tables use 3/6/9/12 outcome bits from the same-PC history. The IMLI
tables deliberately use different signatures: pure iteration count,
iteration+global history, and iteration+global/path history. The Path family
uses independent 4/8/16-bit path windows. Multi-Bias separates a pure
PC-indexed tendency from a context-sensitive PC/short-history/base-confidence
tendency.

IMLI is a speculative 10-bit inner-loop iteration counter. A predicted Taken
backward conditional increments it, a predicted Not-Taken backward conditional
clears it, and every unresolved branch checkpoint carries its pre-branch IMLI.
Misprediction recovery restores that value and applies the actual resolving
outcome. Local history is updated from the in-order retirement stream; the
prediction-time 12-bit snapshot is retained in ROB metadata for precise
training.

All 18 counter tables are read synchronously in parallel with tagged TAGE and
Loop. Their registered response is combined with the Loop-selected base in the
same response cycle, so SC adds no new front-end stage:

```text
componentScore = sum(multiBias[0..1]) / 2
               + sum(globalGEHL[0..5]) / 2
               + sum(localGEHL[0..3])
               + sum(imliGEHL[0..2])
               + sum(pathGEHL[0..2])
baseVote       = preScPrediction ? +(strong ? 62 : 20)
                                 : -(strong ? 62 : 20)
finalScore     = componentScore + baseVote
```

A positive score predicts Taken, a negative score predicts Not-Taken, and zero
keeps `preScPrediction`. The post-SC result is stored in `finalPrediction`. The
base threshold is 23, adjusted by one of 32 signed six-bit threshold
counters selected by PC. Harmful, high-confidence overrides make the selected
threshold more conservative; useful low-confidence overrides make it more
permissive. A weak base may be overturned only when at least two valid feature
families agree with the candidate; a strong base additionally requires the
score to clear the dynamic threshold and at least three agreeing families.
The two half weights normalize correlated families so that simply having more
tables does not give Global or Multi-Bias an accidental voting advantage. At
retirement, all SC
counters move one step toward the actual result when `finalPrediction` was
wrong or the saved decision was low-confidence. Same-address request/update
collisions forward the trained value. Squashed branches never reach this path.

Prediction metadata containing GHR, Path History, Provider/Alternate decisions,
Provider generation, raw `tagePrediction`, Loop metadata,
`preScPrediction`, final `finalPrediction`, and SC confidence travels through
the fetch window into the ROB. Retired conditional updates enter the four-entry
FIFO and train through one shared update stream.

### Speculative history and Bimodal base

TAGE has an independent 192-bit speculative direction history and a 16-bit
speculative Path History. Direction history advances only for conditional
branches. Path History advances for every accepted conditional branch, JAL, or
JALR. Slot 1 is queried with the virtual fall-through state after Slot 0. Each
renamed control-flow instruction receives a ROB-tagged history checkpoint.
Execute-stage recovery restores the pre-branch checkpoint and appends the
resolving control event; precise traps restore retirement-updated committed
history shadows.

Bimodal uses a 1,024-entry table of two-bit counters:

```text
Bimodal index = PC[11:2]
```

Bimodal has no speculative history, checkpoint, or recovery state. Its
counters train only from the in-order retirement stream. Increasing
`BPU_HISTORY_WIDTH` doubles the PHT for every added index bit.

### Logical-state accounting

The predictor uses the following CBP-style logical-state accounting and is
elaboration-time checked against a 16 KiB limit:

| Charged logical state | Bits |
| --- | ---: |
| TAGE + Bimodal baseline | 90,617 |
| Loop table: `64*(1+12+10+10+3+2+1+4)` | 2,752 |
| SC signed counters | 33,792 |
| SC local history + adaptive threshold + IMLI | 3,274 |
| Six SC incremental folds | 48 |
| **Total** | **130,483** |
| CBP-style 16 KiB limit | 131,072 |
| **Headroom** | **589** |

The result is 16,310.375 bytes, about 15.928 KiB.
`BPU_ENFORCE_CBP_STORAGE_LIMIT=1` is enabled by default and fails elaboration
if later geometry changes exceed 131,072 charged bits.

This is a CBP-style logical-state accounting convention, not the literal
synthesized RAM usage. Dual-lane Tag copies, physical banking/replication needed
for multiported reads, committed-history shadows, ROB recovery checkpoints,
update FIFOs, prediction metadata, BTB, and RAS remain real physical hardware
but are outside this logical conditional-direction-predictor budget.
The Loop action log and ROB checkpoints are likewise recovery machinery rather
than persistent prediction tables, so they are excluded from this CBP-style
number while still counting toward synthesized hardware.

### BTB and RAS

The BTB contains 128 entries arranged as 64 two-way sets. Its set index is
`PC[7:2]`; the remaining upper PC bits form the tag. A Taken retired
control-flow instruction installs its target. Direct JAL targets are calculated
from the instruction without waiting for a BTB entry.

The Return Address Stack holds eight predicted return addresses and maintains
speculative and committed views. Calls push `PC + 4`, and recognized returns pop
the top entry. The current RAS committed shadow is still updated at execute
resolution; adding a per-branch RAS checkpoint/action log remains future work.

### Current TAGE capacity/Base A/B result

These runs use the same one-iteration RV32I CoreMark image, synchronous-cache
model, SC settings, and backend. They isolate the Base replacement and tagged
table capacity:

| Configuration | Cycles | Retired | IPC | Conditional misses | Miss rate | Conditional MPKI |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 5x256 TAGE + GShare + SC | 591,945 | 859,559 | 1.4521 | 26,020 | 11.0388% | 30.2713 |
| 5x256 TAGE + Bimodal + SC | 589,162 | 859,556 | 1.4589 | 25,020 | 10.6145% | 29.1081 |
| 5x512 TAGE + Bimodal + SC | 583,760 | 859,574 | 1.4725 | 23,313 | 9.8900% | 27.1216 |
| 5x512 TAGE + Bimodal + Loop + SC | 583,038 | 859,558 | 1.4743 | 23,033 | 9.7712% | 26.7963 |
| 8x512 TAGE + Bimodal + Loop + 4-family SC | 580,834 | 859,567 | 1.4799 | 22,392 | 9.4993% | 26.0503 |
| 8x512 TAGE + Bimodal + Loop + 5-family normalized SC | 580,436 | 859,534 | 1.4808 | 22,234 | 9.4323% | 25.8675 |

Replacing GShare with Bimodal at unchanged tagged capacity removes 1,000
conditional misses. Doubling each tagged table then removes another 1,707.
Combined, conditional misses fall 10.404%, cycles fall 1.383%, and IPC rises
1.405%. This result is workload-specific and comes with the logical-state
increase from 32,553 to 60,901 bits.

Against the immediately preceding 5x512+Bimodal+SC configuration, the tuned
Loop Predictor removes another 280 conditional misses, reduces cycles by 722,
and raises IPC by about 0.122%. During the enabled run it made 483 predictions
different from raw TAGE: 425 corrected a TAGE miss and 58 harmed a correct TAGE
decision, a net benefit of 367 before later SC interaction. These figures are
trajectory-dependent; the cross-run miss delta need not equal the internal
override balance.

The original 16 KiB configuration removes 641 conditional misses (2.783%) and raises
overall IPC by about 0.380% relative to the 5x512+Bimodal+Loop+SC row. Its SC
made 7,321 overrides: 3,770 corrections and 3,551 harms, net +219. The Loop
Predictor contributed a further net +363 overrides. These modest gains show
that the remaining CoreMark misses are not primarily simple table-capacity
misses; alias control and better feature/threshold tuning matter more than
another uniform capacity increase.

Repartitioning the same 16 KiB class into five SC feature families and
normalizing the correlated Multi-Bias and Global sums removes another 158
conditional misses (0.706%), reduces cycles by 398, and raises IPC by about
0.061% versus the preceding 4-family SC. The final SC makes 6,301 overrides:
3,270 corrections and 3,031 harms, net +239. Support attribution is positive
for every family on this trajectory: Bias +27, Global +152, Local +249,
IMLI +300, and Path +263. Attribution overlaps because several families may
support the same final override; those numbers must not be summed as unique
corrected branches.

### Historical SC enable/disable A/B result

The following predictor-only snapshot predates the synchronous cache timing
changes. The runs use the same RV32I CoreMark image with 10 iterations,
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

### CBP2025 RTL trace result

The optional `verification/perf/cbp/` adapter drives the production
Bimodal+TAGE+Loop+SC RTL from the official CBP2025 callback interface. CBP's
resolved direction advances correct-path speculative GHR/Path/IMLI immediately,
as explicitly permitted by that framework, while persistent predictor tables
retain this core's retirement-training behavior. Nonconditional control flow
updates Path History but is excluded from conditional-direction scoring.

CBP2025 uses 64-bit trace PCs, so the adapter XOR-folds their upper and lower
halves into the core's 32-bit PC while preserving instruction-alignment bits.
This is an unavoidable cross-ISA mapping and means the result evaluates the
current RTL algorithm and capacity, not a native 64-bit implementation.

| Predictor | Charged storage | Instructions | Conditional branches | Mispredictions | Miss rate | BrMisPKI |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Current RTL Bimodal+TAGE+Loop+SC | 15.928 KiB | 997,301 | 128,874 | 298 | 0.2312% | 0.2988 |
| Official CBP2016 TAGE-SC-L reference | 64 KiB | 997,301 | 128,874 | 264 | 0.2049% | 0.2647 |

Raw TAGE and the Loop-selected pre-SC direction each miss 299 times in the RTL
run. SC makes three overrides, two corrective and one harmful, for a net one
fewer miss; the Loop Predictor makes no override. This short official sample
validates integration but is not a representative championship score. Several
full training traces and their arithmetic-mean MPKI are required for a robust
comparison.

### Current synchronous-cache integration result

With the current protected Store Buffer policy and the default 10-iteration
image, the full simulation reaches `tohost=1` after 5,791,170 cycles and
retires 8,064,024 instructions for an overall IPC of 1.3925. The CoreMark
measurement interval reports 5,729,265 ticks, 8,003,643 retired instructions,
and IPC 1.3970. The list/matrix/state CRCs are respectively `e3c1`, `0747`, and
`8d84`.

There are 2,236,467 retired conditional branches and 221,718 conditional
mispredictions, a 9.9138% conditional miss rate. Total branch MPKI is 27.5160.
I-cache and D-cache Load MPKI are 0.665 and 0.756. A fixed 100,000-cycle
comparison measures IPC 1.3407 versus 0.8310 for the original blocking
synchronous-cache baseline, a 61.34% recovery. Disabling committed-Store
direct forwarding for correctness changes that snapshot by only about 0.04%
relative to the unguarded 1.3412 result.

## Memory and address parameters

| RTL parameter | Value | Explanation |
| --- | ---: | --- |
| `INS_ADDR_SIZE` | 65,536 bytes | Size of the synchronous instruction backing memory below the I-cache. |
| `DATA_ADDR_SIZE` | 65,536 bytes | Size of the synchronous data backing memory below the D-cache. |
| `ICACHE_BYTES` | 4,096 bytes | Total I-cache data capacity. |
| `ICACHE_LINE_BYTES` | 16 bytes | Four 32-bit instruction words per I-cache line. |
| Derived I-cache set count | 256 | `4096 / 16`; the I-cache is direct-mapped. |
| `DCACHE_SET_COUNT` | 64 | Number of direct-mapped D-cache sets. |
| `DCACHE_LINE_BYTES` | 16 bytes | Four 32-bit words per D-cache line; total D-cache capacity is 1,024 bytes. |
| `STORE_BUFFER_ENTRY_NUM` | 8 Stores | Committed FIFO entries. Disjoint Loads may pass; overlapping Loads wait for drain. The module's byte-merge query is retained for testing but is not used for backend direct forwarding. |
| `RESET_VECTOR` | `0x00000000` | PC used after reset. |
| `UART_TX_ADDR` | `0x0000FFE0` | Byte-oriented simulation UART output. |
| `FROMHOST_ADDR` | `0x0000FFF0` | Host-to-target simulation mailbox. |
| `TOHOST_ADDR` | `0x0000FFF8` | Target-to-host completion mailbox. |

The internal instruction and data memories use 16-bit byte indexes because
their modeled capacities are 64 KiB, while architectural PCs and calculated
addresses remain 32 bits.

### Instruction cache and backing memory

The 4 KiB I-cache is direct-mapped with 256 sets and 16-byte lines. Each F0
request synchronously reads the tag/data locations for `PC` and `PC+4`; the two
addresses normally share a line, while independent lookup contexts handle a
pair that crosses a line boundary. A hit produces the two instruction words in
F1. A consumed hit may be replaced by the next request on the same edge, so the
hit path can sustain one two-instruction fetch pair per cycle.

The cache is blocking and supports one fetch request at a time. On a miss it
issues four aligned 32-bit reads to the single-port, one-cycle synchronous
`insnMem` backing store, installs the complete line, and retries the retained
lookup. If a cross-line pair misses in both lines, those lines are refilled
sequentially. Redirect/flush cancels transient lookup/refill state without
invalidating resident cache lines.

### Data cache and backing memory

The 1 KiB D-cache is direct-mapped with 64 sets and 16-byte lines. Its elastic
synchronous Tag/Data lookup can accept and return one cached Load hit per cycle
when the response consumer is ready. Requests and responses carry the ROB tag,
allowing the LSU to retain multiple pending Load metadata entries. A single
MSHR performs critical-word-first refill: the requested word returns as soon as
the first backing response arrives, while the remaining three aligned words
fill in the background. Cached Loads hitting another set may proceed during
refill; same-set Loads, Stores, and MMIO wait until installation completes.

Stores use write-through, no-write-allocate policy. A Store hit updates the
resident word with byte enables and also writes the backing RAM; a Store miss
updates only backing RAM. Eight committed Store Buffer entries decouple ROB
retirement from this write-through path. The backend allows a younger Load to
pass when its requested bytes are disjoint from every buffered Store, but stalls
on any overlap until the relevant Store drains. Direct committed-buffer
full-forwarding is disabled by the CoreMark CRC correctness guard described
above; LSQ forwarding from older uncommitted Stores is unaffected. The
parameterized MMIO range defaults to `0x0000_FFE0`
through `0x0000_FFFF` and bypasses allocation and caching so UART, `fromhost`,
and `tohost` side effects remain uncached. `dataMem` implements synchronous
registered reads and byte-enabled writes suitable for SRAM/BRAM-style
inference.

The I-cache remains blocking. The D-cache now has one MSHR and different-set
hit-under-miss, but has no secondary-miss merging, write-back/dirty eviction,
prefetching, or load replay. These remaining limitations are important when
interpreting memory-intensive IPC.

### Cache performance counters

The cache modules export diagnostic 64-bit counters through `topCPU`; they are
not software-visible CSRs. `sim_main.cpp` prints them at the end of a run as
`CACHE I` and `CACHE D`:

| Summary | Counters represented |
| --- | --- |
| `CACHE I` | accepted fetch-pair requests, hits and pair misses, physical line misses, miss-stall cycles, refilled lines/cycles, cross-line misses, response-backpressure cycles, and line-miss MPKI |
| `CACHE D` | accepted requests, Load hits/misses and miss rate, Store hits/misses, MMIO requests, structurally busy cycles, refilled lines/cycles, request-backpressure cycles, Store-commit-stall cycles, and Load-miss MPKI |

MPKI uses retired instructions as the denominator. The I-cache value counts
physical line misses, whereas the D-cache value counts Load misses; therefore
neither should be inferred from the pair-level I-cache miss field or Store-miss
field.

## Parameter relationships and tuning guidance

- `PHYS_REG_NUM` must remain greater than `REG_NUM`; the difference determines
  the maximum number of simultaneously live speculative destination mappings.
- Increasing `ROB_ENTRY_NUM` also enlarges branch-recovery checkpoint arrays and
  the younger-entry recovery masks used by the IQ and LSQ.
- `UNIFIED_IQ_ENTRY_NUM` and `LSQ_ENTRY_NUM` are independent. A memory uop
  consumes one slot in each structure, so dispatch checks both free counts, but
  changing either parameter no longer silently changes the other structure.
- `BPU_BASE_INDEX_WIDTH=N` creates `2^N` Bimodal counters. Increasing it changes
  the Bimodal PHT size; the base predictor has no history checkpoint.
- `TAGE_HISTORY_WIDTH` is independent of `BPU_BASE_INDEX_WIDTH`; increasing it
  does not enlarge the Bimodal PHT. TAGE/SC table counts, entries, history
  schedules, fold widths, and tags must be changed consistently. Any change
  must also update logical-storage accounting; enable the CBP limit assertion
  only for configurations intended to fit 4 KiB.
- Larger structures increase the amount of exploitable instruction-level
  parallelism or reduce predictor aliasing, but also increase FPGA area,
  simulation cost, reset work, and potentially the critical path.
- `ICACHE_BYTES / ICACHE_LINE_BYTES` determines the direct-mapped I-cache set
  count. `DCACHE_SET_COUNT * DCACHE_LINE_BYTES` determines D-cache data
  capacity. Current cache implementations require power-of-two geometry and
  four 32-bit words per line.
- After changing structural parameters, run at least `make lint`,
  `make bpu-smoke`, `make tage-smoke`, `make sc-smoke`, `make cache-smoke`,
  `make store-buffer-smoke`, `make lsu-pending-smoke`, `make ooo-smoke`,
  `make ooo-backend-smoke`, and
  `make rv32i-compliance-smoke`, followed by a CoreMark comparison.
