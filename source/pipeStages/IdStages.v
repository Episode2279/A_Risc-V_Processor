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

    output `regAddr regA,
    output `regAddr regB,

    output `instructionAddrPath offset
);

    `regAddr rs2;
    `regAddr rd;


    Decoder decoder(
        .insn(insn),
        .registerWriteEnable(registerWriteEnable),
        .dataWriteEnable(dataWriteEnable),
        .regSelect(regSelect),
        .branchCtr(branchCtr),
        .aluCtr(aluCtr),
        .rs1(regA),
        .rs2(rs2),
        .rd(rd),
        .offset(offset)
    );

    Mux selReg( //determines rs2 or rd which should be regB
        .in1(rd),
        .in2(rs2),
        .sel(insn[5]),
        .out(regB)
    );

    //need a controller to determine if stall


endmodule