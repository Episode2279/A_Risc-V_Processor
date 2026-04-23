module ForwardingUnit
    import TypesPkg::*;
#(
    // Widths are parameterized with the rest of the datapath, but default to RV32.
    parameter int DATA_W = WORD_SIZE,
    parameter int REG_ADDR_W = REG_ADDR,
    // Architectural x0 must never be forwarded as a producer.
    parameter logic [REG_ADDR_W-1:0] ZERO_REG = '0
)
(
    // The current instruction in EX consumes regA/regB and the original
    // register-file dataA/dataB values.
    IdExeBusIf.sink   exe_bus,
    // Older instructions in MEM/WB may have the newest value for those sources.
    ExeMemBusIf.sink  mem_bus,
    MemWbBusIf.sink   wb_bus,
    // Already-selected writeback candidates for the older pipeline stages.
    input  logic [DATA_W-1:0] mem_result_i,
    input  logic [DATA_W-1:0] wb_result_i,
    // Forwarded operands used by the execute stage and store-data path.
    output logic [DATA_W-1:0] dataA_o,
    output logic [DATA_W-1:0] dataB_o
);

    always_comb begin
        // MEM has priority over WB because it is the younger producer and
        // therefore owns the most recent value for back-to-back dependencies.
        dataA_o = exe_bus.dataA;
        if (mem_bus.registerWriteEnable && (mem_bus.rd != ZERO_REG) && (mem_bus.rd == exe_bus.regA)) begin
            dataA_o = mem_result_i;
        end else if (wb_bus.registerWriteEnable && (wb_bus.rd != ZERO_REG) && (wb_bus.rd == exe_bus.regA)) begin
            dataA_o = wb_result_i;
        end

        // Apply the same bypass priority to rs2. This value is used both as an
        // ALU operand and as store data for S-type instructions.
        dataB_o = exe_bus.dataB;
        if (mem_bus.registerWriteEnable && (mem_bus.rd != ZERO_REG) && (mem_bus.rd == exe_bus.regB)) begin
            dataB_o = mem_result_i;
        end else if (wb_bus.registerWriteEnable && (wb_bus.rd != ZERO_REG) && (wb_bus.rd == exe_bus.regB)) begin
            dataB_o = wb_result_i;
        end
    end

endmodule
