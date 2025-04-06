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

    input `regAddr rs1_i,
    input `regAddr rs2_i,
    input `regAddr rd_i,
    input `instructionAddrPath offset_i,

    output `instructionAddrPath pc_exe,

    output logic registerWriteEnable_o,
    output logic dataWriteEnable_o,
    output logic regSelect_o,

    output `ctrBranch branchCtr_o,
    output `ctrALU aluCtr_o,

    output `regAddr rs1_o,
    output `regAddr rs2_o,
    output `regAddr rd_o,
    output `instructionAddrPath offset_o

);

    always*(posedge clk or negedge rst)begin
        if(~rst)begin
            pc_exe<=`RESET_VECTOR;

            registerWriteEnable_o<=`RESET_VECTOR;
            dataWriteEnable_o<=`RESET_VECTOR;
            regSelect_o<=`RESET_VECTOR;

            branchCtr_o<=`RESET_VECTOR;
            aluCtr_o<=`RESET_VECTOR;

            rs1_o<=`RESET_VECTOR;
            rs2_o<=`RESET_VECTOR;
            rd_o<=`RESET_VECTOR;

            offset_o<=`RESET_VECTOR;
        end
        else begin
            if(~stall)begin
                pc_exe<=pc_id;
                registerWriteEnable_o<=registerWriteEnable_i;
                dataWriteEnable_o<=dataWriteEnable_i;
                regSelect_o<=regSelect_i;

                branchCtr_o<=branchCtr_i;
                aluCtr_o<=aluCtr_i;

                rs1_o<=rs1_i;
                rs2_o<=rs2_i;
                rd_o<=rd_i;
                
                offset_o<=offset_i;
            end
        end
    end

endmodule