`include "Types.v"

module IdStages(
    input logic clk,
    input logic rst,

    input `instruction insn,
    input `instructionAddrPath pc,

    output logic registerWriteEnable,
    output logic dataWriteEnable,
    output logic regSelect,
    output `ctrBranch branchCtr,
    output `ctrALU aluCtr,

    output `regAddr rs1,
    output `regAddr rs2,
    output `regAddr rd,
    output `instructionAddrPath offset
);



    Decoder decoder(
        .insn(insn),
        .registerWriteEnable(registerWriteEnable),
        .dataWriteEnable(dataWriteEnable),
        .regSelect(regSelect),
        .branchCtr(branchCtr),
        .aluCtr(aluCtr),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .offset(offset)
    );


endmodule