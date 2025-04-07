`include "Types.v"
module insnMem(
    input `instructionAddrPath addr,

    output `instruction instruction_o
);

    `block mem[0:`INS_ADDR_SIZE-1];

    initial begin
        $readmemb("utils/insn.mem",mem);
    end

    assign instruction_o = {mem[addr],mem[addr+1],mem[addr+2],mem[addr+3]};
endmodule