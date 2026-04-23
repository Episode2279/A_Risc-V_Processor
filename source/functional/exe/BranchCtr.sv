module BranchCtr
    import TypesPkg::*;
#(
    parameter int ADDR_W = WORD_SIZE,
    parameter logic [ADDR_W-1:0] PC_INCREMENT = 32'd4
)
(
    IdExeBusIf.sink          exe_bus,
    input  logic             equal,
    input  logic             lessThan,
    input  logic             lessThanUnsigned,
    input  logic [ADDR_W-1:0] aluOut,
    output logic             jumpEnable,
    output logic [ADDR_W-1:0] pc_o
);

    always_comb begin
        jumpEnable = 1'b0;
        pc_o = exe_bus.pc + PC_INCREMENT;

        unique case (exe_bus.branchCtr)
            BR_BEQ: begin
                if (equal) begin
                    jumpEnable = 1'b1;
                    pc_o = exe_bus.pc + exe_bus.immediate;
                end
            end
            BR_BNE: begin
                if (!equal) begin
                    jumpEnable = 1'b1;
                    pc_o = exe_bus.pc + exe_bus.immediate;
                end
            end
            BR_BLT: begin
                if (lessThan) begin
                    jumpEnable = 1'b1;
                    pc_o = exe_bus.pc + exe_bus.immediate;
                end
            end
            BR_BGE: begin
                if (!lessThan) begin
                    jumpEnable = 1'b1;
                    pc_o = exe_bus.pc + exe_bus.immediate;
                end
            end
            BR_BLTU: begin
                if (lessThanUnsigned) begin
                    jumpEnable = 1'b1;
                    pc_o = exe_bus.pc + exe_bus.immediate;
                end
            end
            BR_BGEU: begin
                if (!lessThanUnsigned) begin
                    jumpEnable = 1'b1;
                    pc_o = exe_bus.pc + exe_bus.immediate;
                end
            end
            BR_JAL: begin
                jumpEnable = 1'b1;
                pc_o = exe_bus.pc + exe_bus.immediate;
            end
            BR_JALR: begin
                jumpEnable = 1'b1;
                pc_o = {aluOut[ADDR_W-1:1], 1'b0};
            end
            default: begin
            end
        endcase
    end

endmodule
