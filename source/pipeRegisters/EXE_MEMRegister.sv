module EXE_MEMRegister
    import TypesPkg::*;
#(
    parameter logic [WORD_SIZE-1:0] RESET_PC = RESET_VECTOR,
    parameter logic [REG_ADDR-1:0] ZERO_REG = '0
)
(
    input logic               clk,
    input logic               rst,
    ExeMemBusIf.register_in   exe_mem_i,
    ExeMemBusIf.register_out  exe_mem_o
);

    always_ff @(posedge clk or negedge rst) begin
        if (~rst) begin
            exe_mem_o.pc <= RESET_PC;
            exe_mem_o.registerWriteEnable <= 1'b0;
            exe_mem_o.dataWriteEnable <= 1'b0;
            exe_mem_o.wbSelect <= WB_ALU;
            exe_mem_o.memCtr <= MEM_WORD;
            exe_mem_o.dataB <= '0;
            exe_mem_o.rd <= ZERO_REG;
            exe_mem_o.immediate <= '0;
            exe_mem_o.aluOut <= '0;
        end else begin
            exe_mem_o.pc <= exe_mem_i.pc;
            exe_mem_o.registerWriteEnable <= exe_mem_i.registerWriteEnable;
            exe_mem_o.dataWriteEnable <= exe_mem_i.dataWriteEnable;
            exe_mem_o.wbSelect <= exe_mem_i.wbSelect;
            exe_mem_o.memCtr <= exe_mem_i.memCtr;
            exe_mem_o.dataB <= exe_mem_i.dataB;
            exe_mem_o.rd <= exe_mem_i.rd;
            exe_mem_o.immediate <= exe_mem_i.immediate;
            exe_mem_o.aluOut <= exe_mem_i.aluOut;
        end
    end

endmodule
