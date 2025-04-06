`include "Types.v"

module RegisterFile(
    input logic clk,
    input logic rst,

//one write
    input logic writeEnable,
    input `data data_i,
    input `regAddr wrAddr,
//two read
    input `regAddr rdAddrA,
    input `regAddr rdAddrB,

    output `data rdA,
    output `data rdB
);

    `data regMem[0:`REG_NUM-1];

    always @(posedge clk)begin
        if(~rst) begin
            regMem <='{default:`RESET_VECTOR};
        end
        else if(writeEnable)begin
            regMem[wrAddr] = data_i;
        end
    end

    assign rdA = regMem[rdAddrA];
    assign rdB = regMem[rdAddrB];

endmodule