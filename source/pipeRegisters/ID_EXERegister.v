`include "Types.v"

module ID_EXERegister(
    input logic clk,
    input logic rst,

    input `instructionAddrPath pc_id,

    input logic registerWriteEnable_i,
    input logic dataWriteEnable_i,
    input logic regSelect_i,

    input `ctrBranch branchCtr_i,
    input `ctrALU aluCtr_i,

    input `data dataA_i,
    input `data dataB_i,
    input `regAddr regA_i,
    input `regAddr regB_i,
    input `instructionAddrPath offset_i,

    output `instructionAddrPath pc_exe,

    output logic registerWriteEnable_o,
    output logic dataWriteEnable_o,
    output logic regSelect_o,

    output `ctrBranch branchCtr_o,
    output `ctrALU aluCtr_o,

    output `data dataA_o,
    output `data dataB_o,
    output `regAddr regA_o,
    output `regAddr regB_o,
    output `instructionAddrPath offset_o

);

    always@(posedge clk or negedge rst)begin
        if(~rst)begin
            pc_exe<=`RESET_VECTOR;

            registerWriteEnable_o<=`RESET_VECTOR;
            dataWriteEnable_o<=`RESET_VECTOR;
            regSelect_o<=`RESET_VECTOR;

            branchCtr_o<=`RESET_VECTOR;
            aluCtr_o<=`RESET_VECTOR;

            dataA_o<=`RESET_VECTOR;
            dataB_o<=`RESET_VECTOR;

            regA_o<=`RESET_VECTOR;
            regB_o<=`RESET_VECTOR;

            offset_o<=`RESET_VECTOR;
        end
        else begin
            pc_exe<=pc_id;
            registerWriteEnable_o<=registerWriteEnable_i;
            dataWriteEnable_o<=dataWriteEnable_i;
            regSelect_o<=regSelect_i;

            branchCtr_o<=branchCtr_i;
            aluCtr_o<=aluCtr_i;

            dataA_o<=dataA_i;
            dataB_o<=dataB_i;

            regA_o<=regA_i;
            regB_o<=regB_i;

            offset_o<=offset_i;
        end
    end

endmodule