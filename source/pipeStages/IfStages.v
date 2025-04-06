`include "Types.v"

module IfStages(
    input logic clk,
    input logic rst,
    
    input `instructionAddrPath jump_address,

    output `instructionAddrPath pc,
    output `instruction insn
);

    PC pcReg(
        .clk(clk),
        .rst(rst),
        .jump_enable(jump_enable),
        .jump_address(jump_address),
        .pc_address_out(pc)
    )

    insnMem insnMem(
        .clk(clk),
        .addr(pc),
        .instruction_o(insn)
    )

endmodule