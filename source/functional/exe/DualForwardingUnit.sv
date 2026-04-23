module DualForwardingUnit
    import TypesPkg::*;
#(
    parameter int DATA_W = WORD_SIZE,
    parameter int REG_ADDR_W = REG_ADDR,
    parameter logic [REG_ADDR_W-1:0] ZERO_REG = '0
)
(
    IdExeBusIf.sink   exe_bus,
    ExeMemBusIf.sink  mem0_bus,
    ExeMemBusIf.sink  mem1_bus,
    MemWbBusIf.sink   wb0_bus,
    MemWbBusIf.sink   wb1_bus,
    input  logic [DATA_W-1:0] mem0_result_i,
    input  logic [DATA_W-1:0] mem1_result_i,
    input  logic [DATA_W-1:0] wb0_result_i,
    input  logic [DATA_W-1:0] wb1_result_i,
    output logic [DATA_W-1:0] dataA_o,
    output logic [DATA_W-1:0] dataB_o
);

    function automatic logic producer_matches(
        input logic              writeEnable,
        input logic [REG_ADDR_W-1:0] producerRd,
        input logic [REG_ADDR_W-1:0] sourceReg
    );
        begin
            producer_matches = writeEnable &&
                               (producerRd != ZERO_REG) &&
                               (producerRd == sourceReg);
        end
    endfunction

    always_comb begin
        // Priority follows age and pipeline distance. MEM beats WB because it
        // is closer to EX; within a dual-issued pair, slot1 is younger than slot0.
        dataA_o = exe_bus.dataA;
        if (producer_matches(mem1_bus.registerWriteEnable, mem1_bus.rd, exe_bus.regA)) begin
            dataA_o = mem1_result_i;
        end else if (producer_matches(mem0_bus.registerWriteEnable, mem0_bus.rd, exe_bus.regA)) begin
            dataA_o = mem0_result_i;
        end else if (producer_matches(wb1_bus.registerWriteEnable, wb1_bus.rd, exe_bus.regA)) begin
            dataA_o = wb1_result_i;
        end else if (producer_matches(wb0_bus.registerWriteEnable, wb0_bus.rd, exe_bus.regA)) begin
            dataA_o = wb0_result_i;
        end

        dataB_o = exe_bus.dataB;
        if (producer_matches(mem1_bus.registerWriteEnable, mem1_bus.rd, exe_bus.regB)) begin
            dataB_o = mem1_result_i;
        end else if (producer_matches(mem0_bus.registerWriteEnable, mem0_bus.rd, exe_bus.regB)) begin
            dataB_o = mem0_result_i;
        end else if (producer_matches(wb1_bus.registerWriteEnable, wb1_bus.rd, exe_bus.regB)) begin
            dataB_o = wb1_result_i;
        end else if (producer_matches(wb0_bus.registerWriteEnable, wb0_bus.rd, exe_bus.regB)) begin
            dataB_o = wb0_result_i;
        end
    end

endmodule
