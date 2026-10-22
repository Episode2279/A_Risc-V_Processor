# Out-of-order backend: guarantees and limitations

This page lists what the backend RTL guarantees and where it is deliberately
conservative. Structure and sizes are in [SPEC.md](../../../SPEC.md).

## Guarantees

- `x0`/`p0` is never renamed or written.
- Dispatch is all-or-nothing per instruction: ROB, issue-queue, LSQ, and
  free-register space are reserved together.
- Allocating a destination register clears its ready bit before any consumer
  can issue.
- The ROB allocates and retires in program order. Retirement takes a
  contiguous prefix of completed entries, up to two per cycle.
- ROB and LSQ retire together, and the LSQ head tag must match the ROB entry.
- A memory uop leaves the issue queue only in the cycle the LSU accepts it.
- No Store changes memory or MMIO before its ROB entry retires.
- A branch misprediction keeps the branch, removes every younger ROB,
  issue-queue, and LSQ entry, and restores the RAT, free list, and predictor
  histories from the branch's checkpoint.
- Results from removed uops are dropped. A Load response for a removed Load is
  still taken from the D-cache but writes nothing.
- Exceptions are taken only at the ROB head. A trap flushes the backend and
  rebuilds the speculative RAT and free list from the committed RAT.
- CSR instructions, FENCE, FENCE.I, ECALL, EBREAK, and MRET dispatch only into
  an empty backend, and nothing else dispatches until they retire.

## Known limitations

- Lane 1 never dispatches a branch, jump, CSR, or serializing instruction; it
  waits one cycle to move to lane 0.
- There is one LSU, so at most one memory uop issues per cycle.
- A Load waits for every older Store address. There is no memory-dependence
  prediction and no Load replay.
- A Load that partly overlaps an older Store, or needs data the Store does not
  have yet, waits.
- A Load that overlaps a retired Store still in the Store Buffer waits for it
  to drain. Direct forwarding from the Store Buffer is disabled; see
  [the LSU README](../execute/lsu/README.md).
- MMIO Stores block all younger Loads. An MMIO Load issues only from the LSQ
  head with an empty Store Buffer.
- The RAS committed copy is updated when a branch resolves rather than when it
  retires, and the RAS has no per-branch checkpoint.
- The I-cache blocks on a miss. The D-cache has one MSHR and is write-through
  with no write-allocate.

## Possible next steps

- Memory-dependence prediction with Load replay.
- Re-enable Store Buffer forwarding through a registered, ROB-tagged
  completion path once the CoreMark failure is understood.
- A RAS checkpoint or action log.
