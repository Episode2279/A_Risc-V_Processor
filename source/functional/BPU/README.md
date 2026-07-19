# Branch Prediction Unit

The default BPU uses a five-table TAGE direction predictor over a GShare
base/alternate, followed by a compact statistical corrector (SC-Lite). Target
prediction uses a 128-entry two-way BTB, direct-JAL decoding, and a speculative
return-address stack. The TAGE and SC paths launch two requests and return two
registered responses per cycle after a one-cycle warm-up, so the front end
remains two-wide in steady state.

## Direction predictors

- `GSharePredictor.sv` owns a 10-bit speculative global history register and a
  1,024-entry table of 2-bit counters. Its index is `PC[11:2] XOR GHR`.
- `TagePredictor.sv` searches five 256-entry tagged tables with history lengths
  4/8/16/32/64 and tag widths 7/8/9/10/11. `TageFoldedHistory.sv` maintains
  prediction-time folds incrementally, `TageHash.sv` generates independently
  mixed Index/Tag keys, and `TageTable.sv` stores the tagged counters,
  usefulness, and generation state in a synchronous banked layout.
- `StatisticalCorrector.sv` owns a 256-entry PC-bias table and four 128-entry
  GEHL tables. Every entry is a signed 6-bit counter. The GEHL histories are
  3/7/15/31 branches and use four incremental 7-bit folds maintained by TAGE.
- `TageUpdateQueue.sv` buffers four retired conditional updates and exposes
  ready/backpressure to the commit stage.

The standalone local-history predictor and Tournament chooser have been
removed. GShare now supplies the base prediction when no tagged table hits and
the alternate prediction when there is no shorter tagged hit. `TAGE_ENABLE=0`
selects pure GShare for A/B testing; `SC_ENABLE=0` keeps TAGE and GShare active
but bypasses the statistical correction.

Provider/alternate selection and the use-alternate-on-new policy first produce
`tagePrediction`, the raw TAGE/UAN direction. SC then computes:

```text
component score = 2 * PC-bias counter
                + GEHL[H=3] + GEHL[H=7]
                + GEHL[H=15] + GEHL[H=31]

final score = component score
            + signed TAGE vote
```

The signed TAGE vote has magnitude 20 for a weak/base decision and 62 for a
strong tagged Provider. A positive final score predicts Taken, a negative score
predicts Not-Taken, and an exact zero preserves `tagePrediction`. The result is
stored as `finalPrediction`. A complete score in `[-23,+23]` is low-confidence.
The factor of two on the bias counter is arithmetic weighting and does not
duplicate its storage.

The SC tables reset to signed zero, so an untrained SC is neutral; the raw TAGE
vote controls early predictions. All SC counters are trained toward the actual
outcome when the retired final prediction was wrong or low-confidence. TAGE
allocation separately compares `tagePrediction` against the actual outcome, so
an SC correction cannot hide a residual TAGE miss and a harmful SC override
cannot cause an unnecessary tagged-table allocation.

## History, hashing, and timing

The 10-bit GShare GHR and independent 64-bit TAGE GHR shift predicted
conditional outcomes at fetch. TAGE additionally keeps a 16-bit speculative
Path History. It shifts a hash of PC and fetch-path direction for every
accepted conditional branch, JAL, or JALR, allowing identical direction
patterns reached through different control paths to hash apart. Each branch
carries prediction-time GHR/Path snapshots and receives ROB-tagged checkpoints
at rename. A misprediction restores the checkpoints plus the resolving
control-flow event immediately at execute. Global histories retain committed
shadows so a precise trap can discard younger speculative outcomes.

For every TAGE table, the 8-bit Index fold, Tag-width fold, and
`(Tag-width-1)` fold are registers. A normal speculative direction update
rotates each fold, XORs the incoming direction at bit zero, and removes the
outgoing GHR bit at `history_length modulo fold_width`. Recovery reconstructs
these registers from the precise full-GHR checkpoint. Index and Tag use
separate CRC-polynomial PC/Path hashes with per-table seeds, input orders, and
rotations. The transforms elaborate into fixed XOR matrices rather than a
serial runtime feedback chain.

SC uses the same incremental-history mechanism for four additional 7-bit folds
at history lengths 3/7/15/31. Its signed-counter reads are registered alongside
the TAGE table reads. The raw TAGE/UAN result arrives in the response cycle and
is combined with the already registered SC counters, so SC does not add another
front-end pipeline stage. Retirement reconstructs the update folds from the
prediction-time full-history snapshot outside the fetch critical path.

The longest tagged-table hit supplies the Provider; the next-shortest hit, or
GShare when none exists, supplies the Alternate. A weak new Provider may use
the Alternate. Six trust counters separate short/medium/long Providers and two
PC classes. Raw TAGE direction errors use an 8-bit LFSR to rotate among
replaceable longer-history tables, and one quarter of allocation attempts may
install a second distinct entry. Three grouped pressure counters release one
pseudorandom minimum-usefulness candidate when all eligible entries are
protected; incremental aging periodically frees other stale entries.

Each logical 256-entry TAGE table is split into two 128-row banks selected by
Hash Index bit zero. Two physical Tag-RAM replicas supply the dual prediction
lanes; counter/useful/valid/generation shadows are shared. Reads are synchronous,
and allocation, Provider update, pressure, aging, and SC counter writes
explicitly forward to same-cycle queries. A 5-bit Provider-generation snapshot
rejects a delayed training update if allocation has replaced the saved entry.

## CBP 4 KiB logical-state budget

The project uses a CBP-style logical predictor-state accounting convention:

| Charged state | Bits |
| --- | ---: |
| TAGE + GShare baseline | 27,917 |
| SC counters: `256*6 + 4*128*6` | 4,608 |
| Four SC incremental folds: `4*7` | 28 |
| **Total** | **32,553** |
| 4 KiB limit | 32,768 |
| **Remaining margin** | **215** |

The total is 4,069.125 bytes, leaving 26.875 bytes. The removed standalone
Local predictor used `256*10 + 1024*2 = 4,608` bits and its 512-entry 2-bit
chooser used another 1,024 bits. Replacing those structures with the 4,608-bit
SC therefore improves resource efficiency while remaining inside the project
budget.

This is a logical-capacity statement, not a claim that synthesis uses only
4 KiB of RAM. Dual-lane Tag-RAM copies, physical replication or banking for
multiported SC reads, committed-history shadows, ROB recovery checkpoints,
update FIFOs, prediction metadata, BTB, and RAS are real implementation costs
but are outside this CBP conditional-direction-predictor logical-state count.

## Targets, recovery, and training

`BranchTargetBuffer.sv` is a 128-entry, two-way target cache. Taken retired
branches allocate or update entries, while Not-Taken outcomes preserve learned
targets. Conditional fetch redirects require both a selected Taken direction
and a BTB hit. Direct JAL targets are decoded immediately. JALR uses the BTB,
while recognized returns prefer `ReturnAddressStack.sv`.

Multiple branches may be unresolved and may execute out of order. A branch
misprediction selectively removes younger ROB, IQ, and LSQ entries, restores
rename/free-list/history checkpoints, and redirects fetch. GShare PHT, TAGE,
SC, and BTB training records remain in the ROB and update only at retirement,
so squashed wrong-path branches cannot pollute those tables. Retired
conditionals enter the four-entry TAGE update FIFO and train through its single
dequeue port. Same-address SC read/write collisions forward the post-training
value to make behavior independent of inferred RAM read-during-write mode.

Branch and misprediction performance counters use the same committed-only
stream. The RAS committed shadow still follows execute resolution; a future RAS
checkpoint/action log is needed to remove that remaining source of wrong-path
state.

## CoreMark A/B result

The following runs use the same RV32I CoreMark image with 10 iterations and
2,236,266 retired conditional branches:

| Mode | Cycles | Retired | IPC | Direction misses | Miss rate | Direction MPKI |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| TAGE + GShare, SC disabled | 5,727,837 | 8,062,058 | 1.4075 | 233,869 | 10.4580% | 29.0086 |
| TAGE + GShare + SC-Lite | 5,698,473 | 8,062,067 | 1.4148 | 219,300 | 9.8065% | 27.2015 |

In the SC-enabled run, SC changed 35,782 raw TAGE decisions: 24,782 overrides
corrected a raw miss and 11,000 harmed a raw-correct prediction, for 13,782 net
beneficial overrides on that execution trajectory. Relative to the SC-disabled
run, cycles fall by about 0.513%, IPC rises by about 0.519%, and direction MPKI
falls by 1.8071. The A/B miss-count delta need not exactly equal the within-run
override balance because enabling SC changes speculative histories and the
subsequent predictor-training trajectory.

These simulator runs are performance comparisons, not official CoreMark scores.
The expected CRCs and `tohost` success are produced, but ten iterations complete
in less than CoreMark's required 10-second validation interval, so its UART
output includes the standard `Errors detected` duration warning.
