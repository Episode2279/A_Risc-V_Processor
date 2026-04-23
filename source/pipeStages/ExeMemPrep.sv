module ExeMemPrep
    import TypesPkg::*;
(
    // Adapter from execute-stage controls/results to the EX/MEM bus.
    IdExeBusIf.sink          exe_bus,
    // Store data is provided separately because it may be forwarded.
    input  word_t            storeData_i,
    input  word_t            aluOut_i,
    // CSR read data is the old CSR value that CSR instructions write to rd.
    input  word_t            csrData_i,
    ExeMemBusIf.register_out exe_mem_o
);

    // Most fields pass through directly from ID/EX. ALU, store data, and CSR
    // data are computed in EX and inserted here before the pipeline register.
    assign exe_mem_o.valid = exe_bus.valid;
    assign exe_mem_o.pc = exe_bus.pc;
    assign exe_mem_o.registerWriteEnable = exe_bus.registerWriteEnable;
    assign exe_mem_o.dataWriteEnable = exe_bus.dataWriteEnable;
    assign exe_mem_o.wbSelect = exe_bus.wbSelect;
    assign exe_mem_o.memCtr = exe_bus.memCtr;
    assign exe_mem_o.dataB = storeData_i;
    assign exe_mem_o.rd = exe_bus.rd;
    assign exe_mem_o.immediate = exe_bus.immediate;
    assign exe_mem_o.aluOut = aluOut_i;
    assign exe_mem_o.csrData = csrData_i;

endmodule
