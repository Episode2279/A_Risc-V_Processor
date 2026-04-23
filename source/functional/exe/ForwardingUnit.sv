module ForwardingUnit
    import TypesPkg::*;
#(
    parameter int DATA_W = WORD_SIZE,
    parameter int REG_ADDR_W = REG_ADDR,
    parameter logic [REG_ADDR_W-1:0] ZERO_REG = '0
)
(
    IdExeBusIf.sink   exe_bus,
    ExeMemBusIf.sink  mem_bus,
    MemWbBusIf.sink   wb_bus,
    input  logic [DATA_W-1:0] mem_result_i,
    input  logic [DATA_W-1:0] wb_result_i,
    output logic [DATA_W-1:0] dataA_o,
    output logic [DATA_W-1:0] dataB_o
);

    always_comb begin
        dataA_o = exe_bus.dataA;
        if (mem_bus.registerWriteEnable && (mem_bus.rd != ZERO_REG) && (mem_bus.rd == exe_bus.regA)) begin
            dataA_o = mem_result_i;
        end else if (wb_bus.registerWriteEnable && (wb_bus.rd != ZERO_REG) && (wb_bus.rd == exe_bus.regA)) begin
            dataA_o = wb_result_i;
        end

        dataB_o = exe_bus.dataB;
        if (mem_bus.registerWriteEnable && (mem_bus.rd != ZERO_REG) && (mem_bus.rd == exe_bus.regB)) begin
            dataB_o = mem_result_i;
        end else if (wb_bus.registerWriteEnable && (wb_bus.rd != ZERO_REG) && (wb_bus.rd == exe_bus.regB)) begin
            dataB_o = wb_result_i;
        end
    end

endmodule
