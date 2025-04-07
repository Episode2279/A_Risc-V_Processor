`include "Types.v"

module WBStages(
    input logic regSelect,
    //input logic registerWriteEnable,

    input `data aluSrc,
    input `data rdData,

    output `data dataWB
);

    assign dataWB = (regSelect)? aluSrc:rdData;

endmodule