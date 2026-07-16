# Backend stage organization

Backend pipeline orchestration lives under `pipeStages/`, mirroring the
`frontEnd/pipeStages/` layout.

- `pipeStages/OoOBackend.sv` connects dispatch/rename, PRF, ROB, the unified
  dual-issue queue, execution units, LSQ ordering, completion, selective
  branch recovery, and in-order retirement.
- `pipeStages/MEMStages.sv` is the data-memory and MMIO stage wrapper used by
  `topCPU`.

Reusable mechanisms remain under `source/functional/`: BPU, decode, rename,
issue, execution, ROB/PRF, LSU, and LSQ blocks are not pipeline-stage wrappers.
