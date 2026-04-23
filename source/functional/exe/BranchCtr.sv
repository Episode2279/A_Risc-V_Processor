module BranchCtr
    import TypesPkg::*;
#(
    // Program counter width and sequential step size. RV32 instructions are
    // currently word-aligned, so the default increment is 4 bytes.
    parameter int ADDR_W = WORD_SIZE,
    parameter logic [ADDR_W-1:0] PC_INCREMENT = 32'd4
)
(
    // Execute-stage decoded control and PC/immediate operands.
    IdExeBusIf.sink          exe_bus,
    // Comparator results are generated in ExeStages from forwarded operands.
    input  logic             equal,
    input  logic             lessThan,
    input  logic             lessThanUnsigned,
    // JALR uses the ALU result for rs1 + immediate before clearing bit 0.
    input  logic [ADDR_W-1:0] aluOut,
    // jumpEnable flushes younger instructions and selects pc_o in IF.
    output logic             jumpEnable,
    output logic [ADDR_W-1:0] pc_o
);

    always_comb begin
        // Default path is fall-through. Branch/jump cases override both the
        // enable and the target address only when the ISA condition is true.
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
                // RISC-V requires JALR target bit 0 to be cleared.
                pc_o = {aluOut[ADDR_W-1:1], 1'b0};
            end
            default: begin
            end
        endcase
    end

endmodule
