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

## Running

```sh
make act4-run
```

This builds a 1 MiB-memory Verilator model and runs every ELF it finds. It
needs two things that are not in the repository:

- The test ELFs in `compliance/act4/work/a-riscv-processor-rv32i/elfs/rv32i/I/`.
  Generate them with the upstream framework in `third_party/riscv-arch-test`
  (see its README), with `CONFIG_FILES` set to this directory's
  `test_config.yaml` and `WORKDIR` set to `compliance/act4/work`. Generation
  also needs the Sail reference model `sail_riscv_sim` on `PATH`
  (`.tools/sail-riscv/bin/`).
- The RISC-V GCC 15 toolchain in `.tools/riscv-gcc-15/`, used both by
  `test_config.yaml` and by the runner's `objcopy` step.

The runner loads each ELF into both the instruction and data memories and
returns a nonzero exit status if any test fails or times out.
