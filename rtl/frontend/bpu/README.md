# Branch Prediction Unit

The default BPU uses an eight-table TAGE direction predictor over a Bimodal
base/alternate, followed by a counted-loop predictor and a multi-component
TAGE-SC-L-style statistical corrector. Target
prediction uses a 128-entry two-way BTB, direct-JAL decoding, and a speculative
return-address stack. The TAGE and SC paths launch two requests and return two
registered responses per cycle after a one-cycle warm-up, so the front end
remains two-wide in steady state. F0 sends the same accepted `PC`/`PC+4` pair
to the BPU and synchronous I-cache in parallel; instruction words are not
available until F1. The BPU retains the accepted request context if an I-cache
miss delays that F1 response.

## Direction predictors

- `BimodalPredictor.sv` owns a 1,024-entry table of 2-bit counters. Its index
  is the word PC `PC[11:2]`; it has no speculative history state.
- `TagePredictor.sv` searches eight 512-entry tagged tables with history lengths
  4/8/16/32/64/96/128/192 and tag widths 7/8/9/10/11/12/13/14.
  `TageFoldedHistory.sv` maintains
  prediction-time folds incrementally, `TageHash.sv` generates independently
  mixed Index/Tag keys, and `TageTable.sv` stores the tagged counters,
  usefulness, and generation state in a synchronous banked layout.
- `StatisticalCorrector.sv` owns two 256-entry Multi-Bias tables, six 256-entry
  Global GEHL tables, four 512-entry Local GEHL tables, three 256-entry IMLI
  GEHL tables, and three 256-entry Path GEHL tables. Every component entry is
  a signed 6-bit counter. A 256-entry 12-bit local-history table, 10-bit
  speculative IMLI, and 32 adaptive-threshold counters supply the additional
  TAGE-SC-L-style context.
- `LoopPredictor.sv` owns 64 direct-mapped entries with 12-bit PC tags,
  10-bit trip/iteration counts, three-bit confidence, two-bit age, direction,
  and four-bit generation fields. A 32-action speculative log provides precise
  iteration recovery.
- `TageUpdateQueue.sv` buffers four retired conditional updates and exposes
  ready/backpressure to the commit stage.

The standalone local-history predictor and Tournament chooser have been
removed. Bimodal now supplies the base prediction when no tagged table hits and
the alternate prediction when there is no shorter tagged hit. `TAGE_ENABLE=0`
selects pure Bimodal for A/B testing; `LOOP_ENABLE=0` bypasses counted-loop
prediction; `SC_ENABLE=0` bypasses the statistical correction.

Provider/alternate selection and the use-alternate-on-new policy first produce
`tagePrediction`, the raw TAGE/UAN direction. A confident Loop match may
replace it to form `preScPrediction`; SC then computes:

```text
component score = sum(Multi-Bias[0..1]) / 2
                + sum(Global GEHL[H=2/6/12/24/48/192]) / 2
                + sum(Local GEHL[0..3])
                + sum(IMLI GEHL[0..2])
                + sum(Path GEHL[0..2])

final score = component score
            + signed pre-SC vote
```

The signed pre-SC vote has magnitude 20 for a weak/base decision and 62 for a
strong tagged Provider or confident Loop result. A positive final score predicts
Taken, a negative score predicts Not-Taken, and an exact zero preserves
`preScPrediction`. The result is stored as `finalPrediction`. The initial
low-confidence interval is `[-23,+23]`, then a PC-class adaptive threshold
makes it more conservative after harmful high-confidence overrides and more
permissive after useful low-confidence overrides.
Weak-base corrections require agreement from at least two valid feature
families. Strong-base corrections must also clear the dynamic threshold and
receive at least three family votes. Multi-Bias and Global are half-weighted
at the family sum, preventing their correlated tables from dominating simply
because they contain more component tables.

The SC tables reset to signed zero, so an untrained SC is neutral; the raw TAGE
vote controls early predictions. All SC counters are trained toward the actual
outcome when the retired final prediction was wrong or low-confidence. TAGE
allocation separately compares `tagePrediction` against the actual outcome, so
an SC correction cannot hide a residual TAGE miss and a harmful SC override
cannot cause an unnecessary tagged-table allocation.

## History, hashing, and timing

The Bimodal base has no GHR. TAGE owns a 192-bit speculative GHR that shifts
predicted conditional outcomes at fetch and additionally keeps a 16-bit speculative
Path History. It shifts a hash of PC and fetch-path direction for every
accepted conditional branch, JAL, or JALR, allowing identical direction
patterns reached through different control paths to hash apart. Each branch
carries prediction-time GHR/Path snapshots and receives ROB-tagged checkpoints
at rename. A misprediction restores the checkpoints plus the resolving
control-flow event immediately at execute. Global histories retain committed
shadows so a precise trap can discard younger speculative outcomes.

For every TAGE table, the 9-bit Index fold, Tag-width fold, and
`(Tag-width-1)` fold are registers. A normal speculative direction update
rotates each fold, XORs the incoming direction at bit zero, and removes the
outgoing GHR bit at `history_length modulo fold_width`. Recovery reconstructs
these registers from the precise full-GHR checkpoint. Index and Tag use
separate CRC-polynomial PC/Path hashes with per-table seeds, input orders, and
rotations. The transforms elaborate into fixed XOR matrices rather than a
serial runtime feedback chain.

SC uses the same incremental-history mechanism for six additional 8-bit
folds at history lengths 2/6/12/24/48/192. Its signed-counter reads are
registered alongside the TAGE table reads. Local history trains at retirement;
its prediction-time snapshot is saved in ROB metadata. IMLI advances
speculatively on backward conditionals and is restored from ROB checkpoints on
a misprediction. The four Local signatures use 3/6/9/12 bits of same-PC
history. The three IMLI tables use pure IMLI, IMLI+global, and
IMLI+global/path keys; the three Path tables separately use 4/8/16-bit path
windows. The raw TAGE/UAN result arrives in the response cycle and is
combined with the registered SC counters, so SC does not add another front-end
pipeline stage.

The longest tagged-table hit supplies the Provider; the next-shortest hit, or
Bimodal when none exists, supplies the Alternate. A weak new Provider may use
the Alternate. Eight trust counters separate four history groups and two PC
classes. Raw TAGE direction errors use an 8-bit LFSR to rotate among
replaceable longer-history tables, and one quarter of allocation attempts may
install a second distinct entry. Four grouped pressure counters release one
pseudorandom minimum-usefulness candidate when all eligible entries are
protected; incremental aging periodically frees other stale entries.

Each logical 512-entry TAGE table is split into two 256-row banks selected by
Hash Index bit zero. Two physical Tag-RAM replicas supply the dual prediction
lanes; counter/useful/valid/generation shadows are shared. Reads are synchronous,
and allocation, Provider update, pressure, aging, and SC counter writes
explicitly forward to same-cycle queries. A 5-bit Provider-generation snapshot
rejects a delayed training update if allocation has replaced the saved entry.

## Counted-loop prediction

The Loop Predictor allocates only from retired Taken backward conditional
branches. It learns the number of repeated-direction outcomes before the loop
exit and becomes eligible to override TAGE only when its three-bit confidence
counter saturates. A confident match predicts the learned loop direction until
the trip count, then predicts the opposite direction for the exit.

Committed iteration state remains in the 64-entry table. Accepted conditional
predictions append their speculative iteration changes to a 32-entry action
log, and ROB checkpoints save the corresponding tail. Misprediction recovery
truncates younger actions and reapplies the resolving branch's actual outcome.
Tags and four-bit entry generations reject recovery or retirement metadata
belonging to a replaced entry.

## Logical-state budget

The project uses a CBP-style logical predictor-state accounting convention:

| Charged state | Bits |
| --- | ---: |
| TAGE + Bimodal baseline | 90,617 |
| Loop table: `64*(1+12+10+10+3+2+1+4)` | 2,752 |
| SC signed counters | 33,792 |
| SC local history + adaptive threshold + IMLI | 3,274 |
| Six SC incremental folds | 48 |
| **Total** | **130,483** |
| 16 KiB limit | 131,072 |
| **Headroom** | **589** |

The predictor totals 16,310.375 bytes, about 15.928 KiB.
`BPU_ENFORCE_CBP_STORAGE_LIMIT` defaults to one, so elaboration fails if a
geometry change exceeds the 16 KiB charged-state target.

This is a logical-capacity statement, not a claim that synthesis uses only
15.928 KiB of RAM. Dual-lane Tag-RAM copies, physical replication or banking for
multiported SC reads, committed-history shadows, ROB recovery checkpoints,
update FIFOs, prediction metadata, BTB, and RAS are real implementation costs
but are outside this CBP conditional-direction-predictor logical-state count.
The Loop action log and its ROB checkpoints are recovery machinery and are
also excluded from this persistent-table accounting.

## Targets, recovery, and training

`BranchTargetBuffer.sv` is a 128-entry, two-way target cache. Taken retired
branches allocate or update entries, while Not-Taken outcomes preserve learned
targets. Conditional fetch redirects require both a selected Taken direction
and a BTB hit. Direct JAL targets are decoded immediately. JALR uses the BTB,
while recognized returns prefer `ReturnAddressStack.sv`.

Multiple branches may be unresolved and may execute out of order. A branch
misprediction selectively removes younger ROB, IQ, and LSQ entries, restores
rename/free-list/history checkpoints, and redirects fetch. Bimodal PHT, TAGE,
SC, and BTB training records remain in the ROB and update only at retirement,
so squashed wrong-path branches cannot pollute those tables. Retired
conditionals enter the four-entry TAGE update FIFO and train through its single
dequeue port. Same-address SC read/write collisions forward the post-training
value to make behavior independent of inferred RAM read-during-write mode.

Branch and misprediction performance counters use the same committed-only
stream. The RAS committed shadow still follows execute resolution; a future RAS
checkpoint/action log is needed to remove that remaining source of wrong-path
state.

## Current CoreMark capacity/Base A/B result

The same one-iteration CoreMark image and complete synchronous-cache core were
used for all three runs:

| Configuration | Cycles | Retired | IPC | Conditional misses | Miss rate | Conditional MPKI |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 5x256 TAGE + GShare + SC | 591,945 | 859,559 | 1.4521 | 26,020 | 11.0388% | 30.2713 |
| 5x256 TAGE + Bimodal + SC | 589,162 | 859,556 | 1.4589 | 25,020 | 10.6145% | 29.1081 |
| 5x512 TAGE + Bimodal + SC | 583,760 | 859,574 | 1.4725 | 23,313 | 9.8900% | 27.1216 |
| 5x512 TAGE + Bimodal + Loop + SC | 583,038 | 859,558 | 1.4743 | 23,033 | 9.7712% | 26.7963 |
| 8x512 TAGE + Bimodal + Loop + 4-family SC | 580,834 | 859,567 | 1.4799 | 22,392 | 9.4993% | 26.0503 |
| 8x512 TAGE + Bimodal + Loop + 5-family normalized SC | 580,436 | 859,534 | 1.4808 | 22,234 | 9.4323% | 25.8675 |

The Base replacement removes 1,000 conditional misses at unchanged tagged
capacity; doubling the tagged tables removes another 1,707. The combined
configuration reduces conditional misses by 10.404% and raises IPC by 1.405%
relative to the former default.

Relative to the 5x512+Bimodal+SC row, the Loop Predictor removes another 280
conditional misses and 722 cycles, raising IPC by about 0.122%. It made 483
directions differ from raw TAGE: 425 corrections and 58 harms, for a net 367
beneficial pre-SC overrides on that run.

The original 16 KiB configuration removes 641 conditional misses (2.783%) and raises
overall IPC by about 0.380% relative to the preceding Loop-enabled row. SC
made 7,321 overrides (3,770 corrections and 3,551 harms, net +219); the Loop
Predictor contributed net +363 overrides on the same run.

The five-family repartition then removes another 158 conditional misses
(0.706%), saves 398 cycles, and raises IPC by about 0.061% without exceeding
the 16 KiB logical-state limit. Its SC makes 6,301 overrides: 3,270 corrections
and 3,031 harms, net +239. Family support attribution is Bias +27, Global +152,
Local +249, IMLI +300, and Path +263. Multiple families can support the same
override, so these attribution counts overlap.

## Historical SC enable/disable A/B result

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
