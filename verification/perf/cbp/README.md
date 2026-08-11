# CBP2025 RTL direction-predictor adapter

This flow connects the production RV32 Bimodal+TAGE+Loop+SC RTL to the official
CBP2025 simulator and trace reader. It measures conditional direction only;
BTB, RAS, instruction-cache, and backend behavior are deliberately outside the
returned prediction.

## External inputs

The official framework and traces are intentionally kept below the ignored
`third_party/` directory:

```sh
git clone --depth 1 https://github.com/ramisheikh/cbp2025.git \
  third_party/cbp2025/framework
mkdir -p third_party/cbp2025/sample_traces/int
curl -L \
  https://raw.githubusercontent.com/ramisheikh/cbp2025/main/sample_traces/int/sample_int_trace.gz \
  -o third_party/cbp2025/sample_traces/int/sample_int_trace.gz
```

Run the bundled integer sample or another CBP2025 trace with:

```sh
make cbp-sample
make cbp-run CBP_TRACE=/absolute/path/to/another_trace.gz
```

## Timing and state semantics

`CbpRtlPredictor.sv` instantiates the same `BimodalPredictor` and
`TagePredictor` modules as the CPU. Prediction metadata is retained in 4,096
verification-only slots until architectural commit. This transient state is
not charged as predictor storage, matching CBP's treatment of prediction-time
history checkpoints.

CBP2025 calls `spec_update` immediately after prediction and explicitly permits
the resolved direction to maintain correct-path speculative history. The
adapter therefore advances RTL GHR, Path History, and IMLI immediately with the
resolved direction. Persistent Bimodal, TAGE, Loop, and SC tables still train
through the production retirement update queue when the official simulator
calls `notify_instr_commit`.

Nonconditional control flow updates Path History but is not scored. The final
direction returned to CBP is `tage_meta_t.finalPrediction`, so a missing BTB
entry cannot turn a direction prediction into Not-Taken.

CBP traces carry 64-bit PCs while the core is RV32. The adapter maps a trace PC
to RTL with:

```text
rtlPC[31:2] = (PC[31:2] XOR PC[63:34])
rtlPC[1:0]  = PC[1:0]
```

Backward-loop classification is calculated from the original 64-bit PC and
target; a synthetic adjacent target communicates only that classification to
the RV32 Loop/IMLI update paths.

## Current sample result

Official `sample_int_trace.gz` result:

| Predictor | Charged storage | Instructions | Conditional branches | Mispredictions | Miss rate | BrMisPKI |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Current RTL Bimodal+TAGE+Loop+SC | 15.928 KiB | 997,301 | 128,874 | 298 | 0.2312% | 0.2988 |
| Official CBP2016 TAGE-SC-L reference | 64 KiB | 997,301 | 128,874 | 264 | 0.2049% | 0.2647 |

For the RTL run, raw TAGE and pre-SC both miss 299 times. SC makes three
overrides, with two corrections and one harm, reducing the final count to 298.
The Loop Predictor makes no override on this short sample.

This approximately one-million-instruction sample is an interface sanity test,
not a representative CBP score. The official simulator reports identical
full/last-10M/last-25M/50-percent rows because the sample is shorter than those
measurement windows. Use several full training traces and their arithmetic
mean before drawing predictor-quality conclusions.
