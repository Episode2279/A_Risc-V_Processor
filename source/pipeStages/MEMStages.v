`include "Types.v"

module MEMStages(
    input logic clk,
    input logic rst,

    //input logic registerWriteEnable,
    input logic dataWriteEnable,
    //input logic regSelect,

    input `data regDataA,
    input `data regDataB,
    input `data aluSrc,

    output `data rdData
);

    dataMem dataMem(
        .clk(clk),
        .logicAddr(regDataA),
        .writeEnable(dataWriteEnable),
        .data_i(regDataB),
        .data_o(rdData)
    );

endmodule