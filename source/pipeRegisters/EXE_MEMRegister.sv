module EXE_MEMRegister
    import TypesPkg::*;
#(
    // Bubble/reset defaults for the execute-to-memory boundary.
    parameter logic [WORD_SIZE-1:0] RESET_PC = RESET_VECTOR,
    parameter logic [REG_ADDR-1:0] ZERO_REG = '0
)
(
    // EX/MEM captures ALU results, CSR read data, and forwarded store data.
    input logic               clk,
    input logic               rst,
    ExeMemBusIf.register_in   exe_mem_i,
    ExeMemBusIf.register_out  exe_mem_o
);

    always_ff @(posedge clk or negedge rst) begin
        if (~rst) begin
            // Reset clears side effects so no accidental store or writeback can
            // occur before a valid instruction reaches this stage.
            exe_mem_o.valid <= 1'b0;
            exe_mem_o.pc <= RESET_PC;
            exe_mem_o.registerWriteEnable <= 1'b0;
            exe_mem_o.dataWriteEnable <= 1'b0;
            exe_mem_o.wbSelect <= WB_ALU;
            exe_mem_o.memCtr <= MEM_WORD;
            exe_mem_o.dataB <= '0;
            exe_mem_o.rd <= ZERO_REG;
            exe_mem_o.immediate <= '0;
            exe_mem_o.aluOut <= '0;
            exe_mem_o.csrData <= '0;
        end else begin
            // No stall is currently needed at this boundary; all fields advance
            // every cycle after reset.
            exe_mem_o.valid <= exe_mem_i.valid;
            exe_mem_o.pc <= exe_mem_i.pc;
            exe_mem_o.registerWriteEnable <= exe_mem_i.registerWriteEnable;
            exe_mem_o.dataWriteEnable <= exe_mem_i.dataWriteEnable;
            exe_mem_o.wbSelect <= exe_mem_i.wbSelect;
            exe_mem_o.memCtr <= exe_mem_i.memCtr;
            exe_mem_o.dataB <= exe_mem_i.dataB;
            exe_mem_o.rd <= exe_mem_i.rd;
            exe_mem_o.immediate <= exe_mem_i.immediate;
            exe_mem_o.aluOut <= exe_mem_i.aluOut;
            exe_mem_o.csrData <= exe_mem_i.csrData;
        end
    end

endmodule
