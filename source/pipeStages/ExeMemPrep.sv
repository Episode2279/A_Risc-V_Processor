module ExeMemPrep
    import TypesPkg::*;
(
    IdExeBusIf.sink          exe_bus,
    input  word_t            storeData_i,
    input  word_t            aluOut_i,
    input  word_t            csrData_i,
    ExeMemBusIf.register_out exe_mem_o
);

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
