`include "Types.v"

module ExeStages(
    input logic clk,
    input logic rst,

    input `instructionAddrPath pc,

    //input logic registerWriteEnable,
    //input logic dataWriteEnable,
    //input logic regSelect,

    //input `ctrBranch branchCtr,
    input `ctrALU aluCtr,

    input `data dataA,
    input `data dataB,

    //input `instructionAddrPath offset,

    output `data aluOut,
    output logic zero
);


    ALU alu(
        .ctr(aluCtr),
        .dataA(dataA),
        .dataB(dataB),
        .out(aluOut),
        .zero(zero)
    );

endmodule