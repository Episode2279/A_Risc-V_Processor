`include "Types.v"

module MEM_WBRegister(
    input logic clk,
    input logic rst,

    input `instructionAddrPath pc_mem,

    input logic registerWriteEnable_i,
    input logic regSelect_i,

    input `ctrBranch branchCtr_i,

    input `data aluSrc_i,
    input `data rdData_i,

    input `instructionAddrPath offset_i,

    input logic zero_i,

    //output
    output `instructionAddrPath pc_wb,

    output logic registerWriteEnable_o,
    output logic regSelect_o,

    output `ctrBranch branchCtr_o,

    output `data aluSrc_o,
    output `data rdData_o,

    output `instructionAddrPath offset_o,

    output logic zero_o,
);

    always*(posedge clk or negedge rst)begin
        if(~rst)begin
            pc_wb<=0;
            registerWriteEnable_o<=0;
            regSelect_o<=0;
            branchCtr_o<=0;
            aluSrc_o<=0;
            rdData_o<=0;
            offset_o<=0;
            zero_o<=0;
        end
        else begin
            pc_wb<=pc_mem;
            registerWriteEnable_o<=registerWriteEnable_i;
            regSelect_o<=regSelect_i;
            branchCtr_o<=branchCtr_i;
            aluSrc_o<=aluSrc_i;
            rdData_o<=rdData_i;
            offset_o<=offset_i;
            zero_o<=zero_i;
        end
    end

endmodule