# Branch Prediction Unit

The current BPU combines an 8-bit GShare direction predictor with a 16-entry
direct-mapped Branch Target Buffer.

## Components

- `BranchPredictionUnit.sv` classifies fetched branch opcodes and combines the
  direction and target predictions.
- `GSharePredictor.sv` contains an 8-bit Global History Register and a
  256-entry Pattern History Table of 2-bit saturating counters. Its lookup is
  `PC[9:2] XOR GHR`; counters reset to weakly not taken (`01`).
- `BranchTargetBuffer.sv` caches targets. Taken resolutions allocate/update an
  entry; not-taken outcomes do not discard the learned target.

Conditional branches redirect fetch only when GShare predicts taken and the
BTB hits. JAL/JALR redirect on a BTB hit. The PHT index calculated at prediction
time travels with the uop and is used for the execute-time counter update.

The GHR currently updates non-speculatively with conditional-branch outcomes in
ROB order. Multiple conditional branches may be in flight, but a younger branch
cannot resolve before an older unresolved branch.

Each conditional branch records RAT and physical-free-list checkpoints indexed
by its ROB tag. On a misprediction, the ROB constructs a mask of younger tags;
ROB, unified IQ, and LSQ remove only those entries. The branch and all
older work remain live, rename state is restored from its checkpoint, and fetch
redirects to the actual next PC. JAL/JALR and CSR operations remain serialized.

Prediction-time speculative GHR shifting is not implemented yet. Adding it will
require saving the pre-branch GHR at prediction/rename and restoring it on a
misprediction.
