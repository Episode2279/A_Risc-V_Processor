# PRF out-of-order core

The PRF/ROB architecture is the primary and only executable `topCPU` datapath.
The former sequential execute/memory/writeback pipeline has been removed.

## Current dataflow

1. `DualIfStages` fetches two adjacent instructions and
   `DualIF_IDRegister` buffers them.
2. Two `IdStages` decoders produce architectural-register micro-operations.
3. `DispatchControl` atomically reserves every resource an accepted operation
   needs. `RenameStage` translates source/destination names with the speculative
   RAT and allocates a new physical destination.
4. Every operation enters the ROB and unified Issue Queue. Memory operations
   also enter the LSQ in program order.
5. The unified scheduler selects up to two ready uops: port 0 accepts every FU
   class and port 1 accepts ordinary integer uops. The LSU checks older LSQ
   Stores before allowing a Load.
6. Loads read memory when non-aliasing or forward from the youngest older Store
   that fully covers their bytes. Stores only calculate and record address/data
   during execution.
7. The ROB retires a contiguous completed prefix of up to two operations. The
   committed map is updated, replaced physical registers return to the free
   list, and a retiring Store receives the sole external memory write port.

## Architectural invariants

- Architectural `xN` initially maps to physical `pN`; `x0/p0` is immutable.
- Physical registers `p32` through `p47` start free.
- Destination allocation clears the new physical register's ready bit before
  dependent operations may issue.
- ROB allocation and retirement are in program order even though integer
  completion may occur out of order.
- Dispatch is atomic across ROB, issue queue, LSQ, and free-list requirements.
- No Store modifies RAM or MMIO before its ROB entry retires.
- ROB and LSQ retirement advance atomically and verify matching LSQ tags.
- The committed map provides a precise free-list reconstruction point for a
  full speculative flush.

## Current performance boundary

Two integer operations, or one integer paired with one branch/CSR/memory
operation, may issue in the same cycle. There is one LSU port, so two memory
operations cannot issue together.
Loads may pass older Stores whose addresses are known not to overlap. A Load is
forwarded from the youngest older Store that fully covers its requested bytes;
unknown Store addresses, unavailable Store data, and partial overlap cause a
conservative wait until the Store retires.

The LSU does not yet predict past unknown Store addresses or replay a violated
Load. Store address and data wake together because the current Memory Queue
requires both source operands before issue. Conditional branches use GShare plus
the BTB and may be in flight concurrently. Each branch carries a RAT/free-list
checkpoint, and a misprediction selectively removes younger ROB, IQ, and LSQ
state. JAL/JALR and CSR instructions remain serialized. The GHR is still updated
non-speculatively. Illegal instructions, ECALL/EBREAK, and misaligned instruction
or data accesses are recorded in the ROB and take a precise machine-mode trap at
the head; trap entry updates `mepc`, `mcause`, `mtval`, and `mstatus`, while MRET
restores interrupt-enable state and redirects through `mepc`.

The next performance milestone is decoupled Store-address/data wakeup plus Load
replay or memory-dependence prediction. After that, add speculative GHR recovery
and remove the remaining jump serialization.
