`include "Types.v"
module dataMem(
    input logic clk,
    input `data logicAddr,


    input logic writeEnable,
    input `data data_i,
    output `data data_o
);

    `block mem[0:`DATA_ADDR_SIZE-1];
    `dataAddrPath addr;

    initial begin
        $readmemh("utils/data.mem",mem);
    end

    assign addr = logicAddr[`DATA_ADDR-1:0];//use only lower 14 bits of a word(32 bits) to address the memory space
    assign data_o = {mem[addr],mem[addr+1],mem[addr+2],mem[addr+3]};

    always @(posedge clk)begin
        if(writeEnable)begin
            {mem[addr],mem[addr+1],mem[addr+2],mem[addr+3]}<=data_i;
        end
    end

endmodule