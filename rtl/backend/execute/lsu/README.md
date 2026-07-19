Memory-side functional blocks live here:

- `LoadStoreQueue.sv` allocates memory operations in program order and records
  independent address/store-data readiness, snoops delayed Store data by
  physical tag, checks older Stores, and provides forwarding.
- `LoadStoreExecutionUnit.sv` computes effective addresses and completes Loads
  or records a Store address; Store data may arrive on the same issue or later
  through PRF writeback snooping.

The cache/memory/MMIO stage wrapper is located at
`../../../memory/subsystem/MEMStages.sv`. It connects the LSU to a 1 KiB,
64-set, direct-mapped D-cache with 16-byte lines. Its elastic synchronous hit
pipeline can accept one cached Load per cycle. A single tagged MSHR implements
critical-word-first, early restart, and different-set hit-under-miss. Retiring
Stores use write-through/no-write-allocate; the UART/host MMIO range bypasses
the cache.

Memory uops share the unified Issue Queue with integer and control uops, then
route through the single LSU port. A memory candidate blocked by LSQ ordering
or sustained D-cache request back-pressure stays in the IQ; the scheduler may
use both integer paths in that cycle, but total accepted issue width remains
two and the LSU cannot accept the held request independently. Loads pass known
non-aliasing Stores and forward when one older Store fully covers the requested
bytes. Unknown addresses and partial overlaps wait conservatively. A
non-forwarded Load completes only after its tagged synchronous D-cache response.
The LSU keeps pending metadata in a ROB-tag-indexed table rather than one global
blocking slot. Responses therefore select their destination/ROB metadata by
tag, not by arrival order. A recovered wrong-path request cannot be withdrawn
from the cache; it is marked killed, and its later response is consumed without
producing ROB completion or PRF writeback.

Committed cacheable Stores enter an eight-entry Store Buffer and drain in
order. The module's query logic searches newest to oldest and can byte-merge
multiple entries; `store-buffer-smoke` continues to test this behavior. The
backend currently does not use the direct full-forward result because its
zero-latency completion path exposed a CoreMark list-CRC error. The forwarded
bytes matched an architectural memory shadow, leaving completion/recovery
integration as the likely race. Instead,
a Load disjoint from all committed entries may pass, while any overlapping Load
waits for the relevant Store to drain. LSQ forwarding from older uncommitted
Stores remains enabled. Because only retired Stores enter this FIFO, it
deliberately has no speculative flush/recovery path. MMIO Stores bypass the
FIFO but remain precise and wait for older buffered Stores. FENCE/CSR
serialization additionally waits until the D-cache/backing-memory wrapper is
idle. Load replay and memory-dependence prediction are not implemented; see
`../../docs/OoO.md`.

Directed checks are available as `make store-buffer-smoke` (FIFO behavior,
byte-merge query logic, youngest-Store priority, and full-queue drain/enqueue) and
`make lsu-pending-smoke` (tagged responses, reverse completion order, and
wrong-path response draining). Cache behavior itself is covered by
`make dcache-smoke`.
