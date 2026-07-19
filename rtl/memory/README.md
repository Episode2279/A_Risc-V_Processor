# Synchronous cache and backing-memory organization

`InstructionCache.sv` and `DataCache.sv` are the CPU-facing memory structures.
`insnMem.sv` and `dataMem.sv` model the SRAM/BRAM-style backing memories beneath
them; their reads are registered rather than combinational.

## Instruction side

- Capacity: 4 KiB, 256 direct-mapped sets, 16 bytes/four words per line.
- F0 accepts `PC` and `PC+4` and launches two synchronous tag/data lookups in
  parallel with the BPU request. The two addresses may occupy different lines.
- F1 returns both instruction words on a hit. Response valid is held until the
  front end consumes it, and a consumed hit can be replaced on the same edge.
- A miss blocks new fetches and refills each missing line with four consecutive
  32-bit reads from the single-port, one-cycle `insnMem` backing store. The
  retained lookup is retried internally after installation.
- A redirect cancels transient lookup/refill state but preserves valid lines.

## Data side

- Capacity: 1 KiB, 64 direct-mapped sets, 16 bytes/four words per line.
- The synchronous Tag/Data lookup is an elastic pipeline. With an accepting
  response consumer, cached Load hits can be accepted and returned every cycle.
- Requests and responses carry a ROB tag. One tagged MSHR tracks a refill. Its
  requested word is fetched first and may complete the Load immediately; the
  remaining three words fill in the background. Cached Loads hitting a
  different set continue during that refill, while same-set Loads, Stores, and
  MMIO wait for it to finish.
- Stores are write-through and no-write-allocate. A hit also merges the written
  byte/halfword/word into the resident line; a miss changes only backing RAM.
- The parameterized MMIO window defaults to `0x0000_FFE0`-`0x0000_FFFF`.
  UART, `fromhost`, and `tohost` requests go directly to `dataMem`, preserving
  their side-effect semantics.
- `dataMem` uses per-byte write enables, allowing byte and halfword Stores
  without a combinational read/modify/write path.
- `idle_o` covers the lookup, refill, and backing-memory transaction state.
  Serializing operations wait for this signal as well as an empty committed
  Store Buffer, so an accepted write cannot remain hidden past a FENCE.

The I-cache remains blocking. The D-cache has one MSHR and basic
hit-under-miss, but still has no secondary-miss merging, dirty state/write-back,
prefetching, or load replay.

## Performance visibility

Both caches expose 64-bit diagnostic counters to `topCPU` and the Verilator
harness. The final simulation summary prints two lines:

- `CACHE I` reports request/hit/pair-miss counts, physical line misses, refill
  and miss-stall cycles, cross-line misses, response backpressure, and line-miss
  MPKI.
- `CACHE D` reports Load and Store hits/misses, Load miss rate and MPKI, MMIO
  requests, busy/refill cycles, request backpressure, and Store-commit stalls.

These are diagnostic RTL outputs rather than architecturally visible CSRs.
`make icache-smoke`, `make dcache-smoke`, and `make cache-smoke` exercise the
cache request/response, refill, backpressure, redirect, MMIO, early-restart,
and hit-under-miss paths.
