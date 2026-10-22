# Backend stage organization

Backend orchestration is split by the state or execution resource each module
owns instead of being collected in a generic `pipeStages/` directory.

- `OoOBackend.sv` connects dispatch, rename, PRF, ROB, the issue queue,
  execution units, LSQ, branch recovery, retirement, and the Store Buffer. It
  also arbitrates the single D-cache port between Loads, Store Buffer drains,
  and MMIO Stores; MMIO Stores and a full Store Buffer take priority. Store
  Buffer behavior is described in
  [execute/lsu/README.md](execute/lsu/README.md).
- `../memory/subsystem/MEMStages.sv` wraps the D-cache and the data
  memory/MMIO backing store. It returns Load responses with their ROB tag and
  reports when it is idle, which FENCE and CSR serialization wait for.

The mechanisms are colocated with their owner: rename logic under `rename/`,
ROB under `retire/`, IQ under `scheduler/`, and execution resources under
`execute/`. Front-end prediction and decode live under `../frontend/`.

Use `make ooo-backend-smoke` for end-to-end dispatch/execute/commit and memory
ordering checks. The lower-level memory paths have separate
`store-buffer-smoke`, `lsu-pending-smoke`, and `dcache-smoke` targets.
