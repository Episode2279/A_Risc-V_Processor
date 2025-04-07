`include "Types.v"

module BranchCtr(
    input `ctrBranch branchCtr,
    input logic zero,
    input `instructionAddrPath pc_i,
    input `instructionAddrPath offset,

    output logic jumpEnable,
    output `instructionAddrPath pc_o
);

    always @(*) begin
        if(zero) begin
            case(branchCtr)
                `NO_JUMP:jumpEnable = `FALSE;
                `BEQ:begin
                    pc_o = pc_i+offset;
                    jumpEnable = `TRUE;
                end
                `BLT:begin
                    pc_o = pc_i+offset;
                    jumpEnable = `TRUE;
                end
                default:jumpEnable = `FALSE;//do nothing
            endcase
        end
    end

endmodule