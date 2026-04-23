module MEM_WBRegister
    import TypesPkg::*;
#(
    // Bubble/reset defaults for the final pipeline boundary.
    parameter logic [WORD_SIZE-1:0] RESET_PC = RESET_VECTOR,
    parameter logic [REG_ADDR-1:0] ZERO_REG = '0
)
(
    // MEM/WB captures all candidate writeback values.
    input logic                clk,
    input logic                rst,
    MemWbBusIf.register_in     mem_wb_i,
    MemWbBusIf.register_out    mem_wb_o
);

    always_ff @(posedge clk or negedge rst) begin
        if (~rst) begin
            // Reset disables register writes until a valid instruction retires.
            mem_wb_o.valid <= 1'b0;
            mem_wb_o.pc <= RESET_PC;
            mem_wb_o.registerWriteEnable <= 1'b0;
            mem_wb_o.wbSelect <= WB_ALU;
            mem_wb_o.immediate <= '0;
            mem_wb_o.aluSrc <= '0;
            mem_wb_o.rdData <= '0;
            mem_wb_o.csrData <= '0;
            mem_wb_o.rd <= ZERO_REG;
        end else begin
            // Normal advance into writeback; WBStages chooses the final value.
            mem_wb_o.valid <= mem_wb_i.valid;
            mem_wb_o.pc <= mem_wb_i.pc;
            mem_wb_o.registerWriteEnable <= mem_wb_i.registerWriteEnable;
            mem_wb_o.wbSelect <= mem_wb_i.wbSelect;
            mem_wb_o.immediate <= mem_wb_i.immediate;
            mem_wb_o.aluSrc <= mem_wb_i.aluSrc;
            mem_wb_o.rdData <= mem_wb_i.rdData;
            mem_wb_o.csrData <= mem_wb_i.csrData;
            mem_wb_o.rd <= mem_wb_i.rd;
        end
    end

endmodule
