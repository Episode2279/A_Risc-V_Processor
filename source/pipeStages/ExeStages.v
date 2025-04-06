`include "Types.v"

module ExeStages(
    input logic clk,
    input logic rst,

    input `instructionAddrPath pc,

    input logic registerWriteEnable,
    input logic dataWriteEnable,
    input logic regSelect,

    input `ctrBranch branchCtr,
    input `ctrALU aluCtr,

    input `regAddr rs1,
    input `regAddr rs2,
    input `regAddr rd,
    input `instructionAddrPath offset
);

    ALU alu(

    );

endmodule