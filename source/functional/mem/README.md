Memory-side functional blocks live here:

- `LoadStoreQueue.sv` allocates memory operations in program order and records
  address/store-data readiness, checks older Stores, and provides forwarding.
- `LoadStoreExecutionUnit.sv` computes effective addresses and completes Loads
  or records Store address/data.

The data-memory/MMIO stage wrapper is now located at
`../../backEnd/pipeStages/MEMStages.sv`.

Memory uops share the unified Issue Queue with integer and control uops, then
route through the single LSU port. Loads pass known
non-aliasing Stores and forward when one older Store fully covers the requested
bytes. Unknown addresses and partial overlaps wait conservatively. Stores write
RAM/MMIO only when accepted at ROB retirement. Load replay and
memory-dependence prediction are not implemented; see `../OoO/README.md`.
