`include "Types.v"
module insnMem(
    input logic clk,
    input `instructionAddrPath addr,

    output `instruction instruction_o
);

    instruction mem[0:`INS_ADDR_SIZE-1];

initial begin
    $readmemh("utils/insn.mem",mem);
end

assign instruction_o = mem[addr];
endmodule