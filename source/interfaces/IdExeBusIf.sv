interface IdExeBusIf;
    import TypesPkg::*;

    instruction_addr_t pc;
    logic              registerWriteEnable;
    logic              dataWriteEnable;
    wb_select_t        wbSelect;
    branch_ctr_t       branchCtr;
    alu_ctr_t          aluCtr;
    mem_access_t       memCtr;
    logic              aluSrcASelect;
    logic              aluSrcBSelect;
    logic              useRs1;
    logic              useRs2;
    word_t             dataA;
    word_t             dataB;
    reg_addr_t         regA;
    reg_addr_t         regB;
    reg_addr_t         rd;
    instruction_addr_t immediate;

    modport decode(
        output pc,
        output registerWriteEnable,
        output dataWriteEnable,
        output wbSelect,
        output branchCtr,
        output aluCtr,
        output memCtr,
        output aluSrcASelect,
        output aluSrcBSelect,
        output useRs1,
        output useRs2,
        output regA,
        output regB,
        output rd,
        output immediate
    );

    modport register_in(
        input pc,
        input registerWriteEnable,
        input dataWriteEnable,
        input wbSelect,
        input branchCtr,
        input aluCtr,
        input memCtr,
        input aluSrcASelect,
        input aluSrcBSelect,
        input useRs1,
        input useRs2,
        input dataA,
        input dataB,
        input regA,
        input regB,
        input rd,
        input immediate
    );

    modport register_out(
        output pc,
        output registerWriteEnable,
        output dataWriteEnable,
        output wbSelect,
        output branchCtr,
        output aluCtr,
        output memCtr,
        output aluSrcASelect,
        output aluSrcBSelect,
        output useRs1,
        output useRs2,
        output dataA,
        output dataB,
        output regA,
        output regB,
        output rd,
        output immediate
    );

    modport sink(
        input pc,
        input registerWriteEnable,
        input dataWriteEnable,
        input wbSelect,
        input branchCtr,
        input aluCtr,
        input memCtr,
        input aluSrcASelect,
        input aluSrcBSelect,
        input useRs1,
        input useRs2,
        input dataA,
        input dataB,
        input regA,
        input regB,
        input rd,
        input immediate
    );
endinterface
