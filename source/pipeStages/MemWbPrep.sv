module MemWbPrep
    import TypesPkg::*;
(
    // Adapter from MEM-stage outputs to the MEM/WB register input.
    ExeMemBusIf.sink        mem_bus,
    // Load result after sign/zero extension from dataMem.
    input  word_t           rdData_i,
    MemWbBusIf.register_out mem_wb_o
);

    // Preserve all writeback candidates. WBStages later chooses among ALU,
    // memory, PC+4, immediate, and CSR old-value sources.
    assign mem_wb_o.valid = mem_bus.valid;
    assign mem_wb_o.pc = mem_bus.pc;
    assign mem_wb_o.registerWriteEnable = mem_bus.registerWriteEnable;
    assign mem_wb_o.wbSelect = mem_bus.wbSelect;
    assign mem_wb_o.immediate = mem_bus.immediate;
    assign mem_wb_o.aluSrc = mem_bus.aluOut;
    assign mem_wb_o.rdData = rdData_i;
    assign mem_wb_o.csrData = mem_bus.csrData;
    assign mem_wb_o.rd = mem_bus.rd;

endmodule
