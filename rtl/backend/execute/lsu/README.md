# Load/store unit

- `LoadStoreQueue.sv` keeps Loads and Stores in program order, records each
  Store's address and data separately, captures late Store data from the PRF
  writeback buses, checks Loads against older Stores, and forwards Store data.
- `LoadStoreExecutionUnit.sv` computes addresses, completes Loads, and
  records Store addresses (and Store data when it is already available).
- `StoreBuffer.sv` holds up to eight retired Stores until they drain to the
  D-cache.

The D-cache wrapper is `../../../memory/subsystem/MEMStages.sv`; see
[rtl/memory/README.md](../../../memory/README.md).

## Issue and ordering

Memory uops share the unified issue queue and a single LSU port. A memory uop
blocked by LSQ ordering or D-cache back-pressure stays in the issue queue
while the two integer paths keep issuing.

A Load passes older Stores whose addresses are known and do not overlap it,
and takes its data from the youngest older Store that covers all of its bytes.
It waits if an older Store address is unknown, the overlap is partial, or the
covering Store has no data yet. Stores to the MMIO range block all younger
Loads, and an MMIO Load issues only from the LSQ head with an empty Store
Buffer.

A Load that is not forwarded goes to the D-cache with its ROB tag. Pending
Loads are tracked per ROB tag, so responses may return in any order. A Load
removed by branch recovery cannot be cancelled in the cache; its response is
drained without completing the ROB entry or writing the PRF.

## Store Buffer

Retired cacheable Stores enter the Store Buffer and drain oldest first. Only
retired Stores enter it, so it needs no recovery logic. MMIO Stores skip it
but wait until older buffered Stores have drained.

A Load that does not overlap any buffered Store may pass the buffer. A Load
that overlaps one waits until that Store drains. The buffer's byte-merge
lookup could forward the data instead, and `store-buffer-smoke` still tests
it, but the backend ignores its result: enabling it made CoreMark's list CRC
wrong. The forwarded bytes matched a reference memory, so the suspected cause
is a race between this zero-latency completion path and branch recovery, not
the byte merging. The root cause has not been found. Forwarding from unretired
Stores in the LSQ is not affected.

CSR and FENCE serialization also waits for the D-cache wrapper to be idle, so
no accepted write is still pending.

## Tests

- `make store-buffer-smoke`: FIFO order, byte-merge lookup, youngest-Store
  priority, drain and enqueue when full.
- `make lsu-pending-smoke`: tagged responses, reverse completion order,
  wrong-path response draining.
- `make dcache-smoke`: the D-cache itself.
