`include "Types.v"

module topCPU(
    input logic clk,
    input logic rst
);

    `instructionAddrPath pc_if,pc_id,pc_exe,pc_mem,pc_wb;
    `instructionAddrPath pc_br;

    `instruction insn_if,insn_id;

    logic registerWriteEnable_id,registerWriteEnable_exe,registerWriteEnable_mem,registerWriteEnable_wb;
    logic dataWriteEnable_id,dataWriteEnable_exe,dataWriteEnable_mem;
    logic regSelect_id,regSelect_exe,regSelect_mem,regSelect_wb;

    `ctrBranch branchCtr_id,branchCtr_exe;

    `ctrALU aluCtr_id,aluCtr_exe;

    `regAddr regA_id,regA_exe,regB_id,regB_exe,regB_mem,regB_wb;

    `data dataA_id,dataA_exe,dataA_mem;
    `data dataB_id,dataB_exe,dataB_mem;

    `instructionAddrPath offset_id,offset_exe;

    `data aluOut_exe,aluOut_mem,aluOut_wb;

    logic zero;

    `data rdData_mem,rdData_wb;

    logic jumpEnable;

    `data data_wb;

    logic wrEnable,stall;

    //register file

    RegisterFile regFile(
        .clk(clk),
        .rst(rst),

        .writeEnable(registerWriteEnable_wb),
        .data_i(data_wb),
        .wrAddr(regB_wb),
        .rdAddrA(regA_id),
        .rdAddrB(regB_id),
        //output
        .rdA(dataA_id),
        .rdB(dataB_id)
    );

    //Instruction fetch stage

    IfStages ifStage(
        .clk(clk),
        .rst(rst),

        .jump_address(pc_br),
        .jump_enable(jumpEnable),
        .wrEnable(wrEnable),
        //output
        .pc(pc_if),
        .insn(insn_if)
    );

    //IF--ID stage register

    IF_IDRegister if_id(
        .clk(clk),
        .rst(rst),

        .instruction_if(insn_if),
        .pc_if(pc_if),
        .stall(stall),
        //output
        .instruction_o(insn_id),
        .pc_o(pc_id)
    );

    //Instruction decode stage

    IdStages idStage(
        .clk(clk),
        .rst(rst),

        .insn(insn_id),
        .pc(pc_id),
        //output
        .registerWriteEnable(registerWriteEnable_id),
        .dataWriteEnable(dataWriteEnable_id),
        .regSelect(regSelect_id),
        .branchCtr(branchCtr_id),
        .aluCtr(aluCtr_id),
        .regA(regA_id),
        .regB(regB_id),
        .offset(offset_id)
    );

    controller control(
        .in1(regA_id),
        .in2(regA_exe),
        .wrEnable(wrEnable),
        .stall(stall)
    );

    //ID--EXE stage register

    ID_EXERegister id_exe(
        .clk(clk),
        .rst(rst),

        .pc_id(pc_id),
        .registerWriteEnable_i(registerWriteEnable_id),
        .dataWriteEnable_i(dataWriteEnable_id),
        .regSelect_i(regSelect_id),
        .branchCtr_i(branchCtr_id),
        .aluCtr_i(aluCtr_id),
        .dataA_i(dataA_id),
        .dataB_i(dataB_id),
        .regA_i(regA_id),
        .regB_i(regB_id),
        .offset_i(offset_id),
        //output
        .pc_exe(pc_exe),
        .registerWriteEnable_o(registerWriteEnable_exe),
        .dataWriteEnable_o(dataWriteEnable_exe),
        .regSelect_o(regSelect_exe),
        .branchCtr_o(branchCtr_exe),
        .aluCtr_o(aluCtr_exe),
        .dataA_o(dataA_exe),
        .dataB_o(dataB_exe),
        .regA_o(regA_exe),
        .regB_o(regB_exe),
        .offset_o(offset_exe)
    );

    //Instruction execution stage

    ExeStages exeStage(
        .clk(clk),
        .rst(rst),

        .pc(pc_exe),
        .aluCtr(aluCtr_exe),
        .dataA(dataA_exe),
        .dataB(dataB_exe),
        //output
        .aluOut(aluOut_exe),
        .zero(zero)
    );

    //Branch control unit

    BranchCtr brCtr(
        .branchCtr(branchCtr_exe),
        .zero(zero),
        .pc_i(pc_exe),
        .offset(offset_exe),
        //output
        .jumpEnable(jumpEnable),
        .pc_o(pc_br)
    );

    //EXE--MEM stage register

    EXE_MEMRegister exe_mem(
        .clk(clk),
        .rst(rst),

        .pc_exe(pc_exe),
        .registerWriteEnable_i(registerWriteEnable_exe),
        .dataWriteEnable_i(dataWriteEnable_exe),
        .regSelect_i(regSelect_exe),
        .dataA_i(dataA_exe),
        .dataB_i(dataB_exe),
        .regB_i(regB_exe),
        .aluOut_i(aluOut_exe),
        //output
        .pc_mem(pc_mem),
        .registerWriteEnable_o(registerWriteEnable_mem),
        .dataWriteEnable_o(dataWriteEnable_mem),
        .regSelect_o(regSelect_mem),
        .dataA_o(dataA_mem),
        .dataB_o(dataB_mem),
        .regB_o(regB_mem),
        .aluOut_o(aluOut_mem)
    );

    //memory access stage

    MEMStages memStage(
        .clk(clk),
        .rst(rst),

        .dataWriteEnable(dataWriteEnable_mem),
        .regDataA(dataA_mem),
        .regDataB(dataB_mem),
        .aluSrc(aluOut_mem),
        //output
        .rdData(rdData_mem)
    );

    //MEM--WB stage register

    MEM_WBRegister mem_wb(
        .clk(clk),
        .rst(rst),

        .pc_mem(pc_mem),
        .registerWriteEnable_i(registerWriteEnable_mem),
        .regSelect_i(regSelect_mem),
        .aluSrc_i(aluOut_mem),
        .rdData_i(rdData_mem),
        .regB_i(regB_mem),
        //output
        .pc_wb(pc_wb),
        .registerWriteEnable_o(registerWriteEnable_wb),
        .regSelect_o(regSelect_wb),
        .aluSrc_o(aluOut_wb),
        .rdData_o(rdData_wb),
        .regB_o(regB_wb)
    );

    //write back stage

    WBStages wbStage(
        .regSelect(regSelect_wb),
        .aluSrc(aluOut_wb),
        .rdData(rdData_wb),
        //output
        .dataWB(data_wb)
    );

endmodule