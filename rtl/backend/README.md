# Backend stage organization

Backend orchestration is split by the state or execution resource each module
owns instead of being collected in a generic `pipeStages/` directory.

- `OoOBackend.sv` connects dispatch/rename, PRF, ROB, the unified
  dual-issue queue, execution units, LSQ ordering, completion, selective
  branch recovery, in-order retirement, and the eight-entry committed Store
  Buffer. Its memory-port arbitration prioritizes precise MMIO and forced
  full-buffer draining. Loads disjoint from committed buffered Stores may
  proceed ahead of opportunistic draining, while any overlapping Load waits for
  the relevant Store to drain. LSQ forwarding from older uncommitted Stores is
  still active. The Store Buffer retains byte-merge query logic, but backend
  direct forwarding is guarded off because its zero-latency completion path
  exposed a CoreMark list-CRC error. Diagnostic checking found the forwarded
  bytes correct, so a completion/recovery integration race is the remaining
  suspect rather than the byte-merge algorithm.
- `../memory/subsystem/MEMStages.sv` wraps the pipelined synchronous D-cache, its single
  MSHR, and the data-memory/MMIO backing store for `topCPU`. It returns Load
  responses with their ROB tag and exports a true idle indication used by
  backend serialization/FENCE draining.

The mechanisms are colocated with their owner: rename logic under `rename/`,
ROB under `retire/`, IQ under `scheduler/`, and execution resources under
`execute/`. Front-end prediction and decode live under `../frontend/`.

Use `make ooo-backend-smoke` for end-to-end dispatch/execute/commit and memory
ordering checks. The lower-level memory paths have separate
`store-buffer-smoke`, `lsu-pending-smoke`, and `dcache-smoke` targets.
