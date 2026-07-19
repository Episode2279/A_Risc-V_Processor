# Constraints

Place portable or selected-target XDC files in this directory. The Vivado Tcl
flow automatically imports every `*.xdc` file here.

No constraint is supplied by default because the repository does not select a
specific FPGA board, oscillator, reset polarity, or pinout. For a board port,
prefer `fpga/boards/<board>/constraints/` and extend the Tcl flow to select only
that board's files; this avoids accidentally applying incompatible pin or clock
constraints to another target.
