module ID_EXERegister
    import TypesPkg::*;
#(
    parameter logic [WORD_SIZE-1:0] RESET_PC = RESET_VECTOR,
    parameter logic [REG_ADDR-1:0] ZERO_REG = '0
)
(
    input logic               clk,
    input logic               rst,
    input logic               stall,
    input logic               flush,
    IdExeBusIf.register_in    id_bus_i,
    IdExeBusIf.register_out   exe_bus_o
);

    always_ff @(posedge clk or negedge rst) begin
        if (~rst || flush || stall) begin
            exe_bus_o.pc <= RESET_PC;
            exe_bus_o.registerWriteEnable <= 1'b0;
            exe_bus_o.dataWriteEnable <= 1'b0;
            exe_bus_o.wbSelect <= WB_ALU;
            exe_bus_o.branchCtr <= BR_NONE;
            exe_bus_o.aluCtr <= ALU_ADD;
            exe_bus_o.memCtr <= MEM_WORD;
            exe_bus_o.aluSrcASelect <= 1'b0;
            exe_bus_o.aluSrcBSelect <= 1'b0;
            exe_bus_o.useRs1 <= 1'b0;
            exe_bus_o.useRs2 <= 1'b0;
            exe_bus_o.dataA <= '0;
            exe_bus_o.dataB <= '0;
            exe_bus_o.regA <= ZERO_REG;
            exe_bus_o.regB <= ZERO_REG;
            exe_bus_o.rd <= ZERO_REG;
            exe_bus_o.immediate <= '0;
        end else begin
            exe_bus_o.pc <= id_bus_i.pc;
            exe_bus_o.registerWriteEnable <= id_bus_i.registerWriteEnable;
            exe_bus_o.dataWriteEnable <= id_bus_i.dataWriteEnable;
            exe_bus_o.wbSelect <= id_bus_i.wbSelect;
            exe_bus_o.branchCtr <= id_bus_i.branchCtr;
            exe_bus_o.aluCtr <= id_bus_i.aluCtr;
            exe_bus_o.memCtr <= id_bus_i.memCtr;
            exe_bus_o.aluSrcASelect <= id_bus_i.aluSrcASelect;
            exe_bus_o.aluSrcBSelect <= id_bus_i.aluSrcBSelect;
            exe_bus_o.useRs1 <= id_bus_i.useRs1;
            exe_bus_o.useRs2 <= id_bus_i.useRs2;
            exe_bus_o.dataA <= id_bus_i.dataA;
            exe_bus_o.dataB <= id_bus_i.dataB;
            exe_bus_o.regA <= id_bus_i.regA;
            exe_bus_o.regB <= id_bus_i.regB;
            exe_bus_o.rd <= id_bus_i.rd;
            exe_bus_o.immediate <= id_bus_i.immediate;
        end
    end

endmodule
