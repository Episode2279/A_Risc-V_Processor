# Vivado flow

This directory contains only reproducible Vivado inputs. Generated projects,
runs, caches, IP output products, reports, and logs belong under
`build/vivado/` and are ignored by Git.

The checked-in pieces are deliberately separated by responsibility:

- `scripts/`: project creation and synthesis automation;
- `constraints/`: board/part-specific XDC inputs;
- RTL remains in `rtl/`; Vivado reads the same `config/filelists/core.f` used by
  Verilator, so there is no second copy of the CPU source list.

Create a project with an explicit FPGA part:

```sh
make vivado-project FPGA_PART=xc7a35tcpg236-1
```

Run synthesis and emit reports under `build/vivado/reports/`:

```sh
make vivado-synth FPGA_PART=xc7a35tcpg236-1
```

Run the shared integration testbench in XSim:

```sh
make vivado-sim FPGA_PART=xc7a35tcpg236-1
```

Run `make coremark` before behavioral simulation so `build/images/insn.mem` and
`build/images/data.mem` exist. The Tcl script passes their absolute paths to
XSim; the SystemVerilog testbench contains no workstation-specific path.

`topCPU` is currently the portable core top, not a board shell. A real board
integration should add `fpga/boards/<board>/BoardTop.sv` plus its XDC and clock,
reset, UART, and host-interface adaptation. Do not put those board concerns
inside the core RTL.
