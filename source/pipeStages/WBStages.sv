module WBStages
    import TypesPkg::*;
#(
    parameter int DATA_W = WORD_SIZE,
    parameter logic [DATA_W-1:0] PC_INCREMENT = 32'd4
)
(
    MemWbBusIf.sink wb_bus,
    output logic [DATA_W-1:0] dataWB
);

    always_comb begin
        unique case (wb_bus.wbSelect)
            WB_ALU: dataWB = wb_bus.aluSrc;
            WB_MEM: dataWB = wb_bus.rdData;
            WB_PC4: dataWB = wb_bus.pc + PC_INCREMENT;
            WB_IMM: dataWB = wb_bus.immediate;
            default: dataWB = '0;
        endcase
    end

endmodule
