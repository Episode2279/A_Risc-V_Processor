# ACT4 RV32I configuration

This directory describes the core to the official `riscv-arch-test` ACT4
framework. Tests start at address zero. The compliance-only 1 MiB model places
UART at `0xFFFE0` and writes `1` (pass) or `3` (fail) to `tohost` at `0xFFFF8`;
the normal 64 KiB CoreMark configuration retains its original MMIO addresses.

The generated suite is intentionally restricted to extension `I`. Zicsr and
machine mode are declared because the self-checking runtime needs trap entry,
but privileged certification tests are disabled until the core implements the
full privileged architecture.

`sail.json` is derived from ACT4's official RV32 Sail base configuration, with
its executable RAM moved to `0x0..0xFFFFF` to match the compliance simulation.
ACT4 does not generate this file from UDB yet.

## Result

The current RTL passes all 39 generated RV32I `I` extension tests. This result
does not claim certification for the full privileged architecture or Zicsr;
those suites remain out of scope until all required CSRs and interrupts exist.

Run the generated ELFs on the DUT with:

```sh
make act4-run
```

The runner mirrors each ELF image into the Harvard instruction and data
memories, uses a compliance-only 1 MiB memory configuration, and reports a
nonzero exit status if any self-checking ELF fails or times out.
