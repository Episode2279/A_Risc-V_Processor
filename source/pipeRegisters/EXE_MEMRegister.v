`include "Types.v"

module EXE_MEMRegister(
    input logic clk,
    input logic rst,

    input `instructionAddrPath pc_exe,

    input logic registerWriteEnable_i,
    input logic dataWriteEnable_i,
    input logic regSelect_i,

    //input `ctrBranch branchCtr_i,

    input `data dataA_i,
    input `data dataB_i,
    input `regAddr rd_i,
    //input `instructionAddrPath offset_i,

    input `data aluOut_i,
    //input logic zero_i,

    output `instructionAddrPath pc_mem,

    output logic registerWriteEnable_o,
    output logic dataWriteEnable_o,
    output logic regSelect_o,

    //output `ctrBranch branchCtr_o,

    output `data dataA_o,
    output `data dataB_o,
    output `regAddr rd_o,
    //output `instructionAddrPath offset_o,

    output `data aluOut_o
);

    always@(posedge clk or negedge rst)begin
        if(~rst)begin
            pc_mem<=0;
            registerWriteEnable_o<=0;
            dataWriteEnable_o<=0;
            regSelect_o<=0;
            dataA_o<=0;
            dataB_o<=0;
            aluOut_o<=0;
            rd_o<=0;
        end
        else begin
            pc_mem<=pc_exe;
            registerWriteEnable_o<=registerWriteEnable_i;
            dataWriteEnable_o<=dataWriteEnable_i;
            regSelect_o<=regSelect_i;
            dataA_o<=dataA_i;
            dataB_o<=dataB_i;
            aluOut_o<=aluOut_i;
            rd_o<=rd_i;
        end
    end

endmodule