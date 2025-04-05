`include "Types.v"
module dataMem(
    input logic clk,
    input `instructionAddrPath addr,

    output `instruction data_o
);

    instruction mem[0:`INS_ADDR_SIZE-1];

initial begin
    $readmemh("utils/data.mem",mem);
end

assign data_o = mem[addr];
endmodule