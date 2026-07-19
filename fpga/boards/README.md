# Board integrations

Each supported board should own a self-contained directory:

```text
fpga/boards/<board>/
  BoardTop.sv
  constraints/<board>.xdc
  README.md
```

`BoardTop.sv` adapts the portable `topCPU` ports to the board oscillator, reset,
UART, LEDs, and any host interface. Board clock-generation IP and its generated
products must remain under `build/vivado/`; only reproducible configuration or
Tcl used to recreate the IP belongs in this tree.

No board is selected yet. This is intentional: choosing a part number does not
define oscillator frequency, pinout, reset polarity, or external interfaces.
