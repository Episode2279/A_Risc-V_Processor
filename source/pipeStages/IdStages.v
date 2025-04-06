`include "Types.v"

module IdStages(
    input logic clk,
    input logic rst,

    input `instruction insn,
    input `instructionAddrPath pc,
);

    logic registerWriteEnable;
    logic dataWriteEnable;
    logic regSelect;
    `ctrBranch branchCtr;
    `ctrALU aluCtr;

    Decoder decoder(
        .insn(insn),
        .registerWriteEnable(registerWriteEnable),
        .dataWriteEnable(dataWriteEnable),
        .regSelect(regSelect),
        .branchCtr(branchCtr),
        .aluCtr(aluCtr)
    )

endmodule