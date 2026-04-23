interface IdExeBusIf;
    import TypesPkg::*;

    // Decode-to-execute bus. It carries decoded control plus source register
    // metadata so hazard detection and forwarding do not need to re-decode insn.
    logic              valid;
    instruction_addr_t pc;
    // Architectural side effects selected in decode.
    logic              registerWriteEnable;
    logic              dataWriteEnable;
    wb_select_t        wbSelect;
    // CSR operation metadata for SYSTEM CSR instructions.
    csr_op_t           csrOp;
    csr_addr_t         csrAddr;
    logic              csrUseImm;
    word_t             csrImm;
    // Execute and memory controls.
    branch_ctr_t       branchCtr;
    alu_ctr_t          aluCtr;
    mem_access_t       memCtr;
    // ALU source selects: A can be register or PC, B can be register or imm.
    logic              aluSrcASelect;
    logic              aluSrcBSelect;
    // Source-use flags let the hazard unit avoid false dependencies on fields
    // that are encoded but not actually read by the instruction format.
    logic              useRs1;
    logic              useRs2;
    // Register-file data and architectural register addresses.
    word_t             dataA;
    word_t             dataB;
    reg_addr_t         regA;
    reg_addr_t         regB;
    reg_addr_t         rd;
    instruction_addr_t immediate;

    // Driven by IdStages/Decoder. Register data is attached separately by the
    // top-level register file before entering ID/EX.
    modport decode(
        output pc,
        output valid,
        output registerWriteEnable,
        output dataWriteEnable,
        output wbSelect,
        output csrOp,
        output csrAddr,
        output csrUseImm,
        output csrImm,
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

    // Consumed by the ID/EX pipeline register.
    modport register_in(
        input pc,
        input valid,
        input registerWriteEnable,
        input dataWriteEnable,
        input wbSelect,
        input csrOp,
        input csrAddr,
        input csrUseImm,
        input csrImm,
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

    // Driven by the ID/EX pipeline register.
    modport register_out(
        output pc,
        output valid,
        output registerWriteEnable,
        output dataWriteEnable,
        output wbSelect,
        output csrOp,
        output csrAddr,
        output csrUseImm,
        output csrImm,
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

    // Read-only view for stages/helpers that inspect an already-formed bus.
    modport sink(
        input pc,
        input valid,
        input registerWriteEnable,
        input dataWriteEnable,
        input wbSelect,
        input csrOp,
        input csrAddr,
        input csrUseImm,
        input csrImm,
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
