module MemWbPrep
    import TypesPkg::*;
(
    ExeMemBusIf.sink        mem_bus,
    input  word_t           rdData_i,
    MemWbBusIf.register_out mem_wb_o
);

    assign mem_wb_o.pc = mem_bus.pc;
    assign mem_wb_o.registerWriteEnable = mem_bus.registerWriteEnable;
    assign mem_wb_o.wbSelect = mem_bus.wbSelect;
    assign mem_wb_o.immediate = mem_bus.immediate;
    assign mem_wb_o.aluSrc = mem_bus.aluOut;
    assign mem_wb_o.rdData = rdData_i;
    assign mem_wb_o.rd = mem_bus.rd;

endmodule
