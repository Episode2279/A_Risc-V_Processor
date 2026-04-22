# A_Risc-V_Processor

## to compile it

----enter the directory source.

----the HDL has been converted to SystemVerilog and now uses a shared package in `TypesPkg.sv`.

----use `verilator --sv -f filelist.f --cc --build --exe --trace sim_main.cpp` to compile it.

----use `./obj_dir/VtopCPU` to execute it.
