module WBStages
    import TypesPkg::*;
#(
    parameter int DATA_W = WORD_SIZE,
    parameter int ADDR_W = WORD_SIZE,
    parameter logic [ADDR_W-1:0] PC_INCREMENT = 32'd4
)
(
    MemWbBusIf.sink wb_bus,
    output logic [DATA_W-1:0] dataWB
);

    WritebackMux #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .PC_INCREMENT(PC_INCREMENT)
    ) writebackMux(
        .wbSelect(wb_bus.wbSelect),
        .pc(wb_bus.pc),
        .aluData(wb_bus.aluSrc),
        .memData(wb_bus.rdData),
        .immediate(wb_bus.immediate),
        .csrData(wb_bus.csrData),
        .result_o(dataWB)
    );

endmodule
