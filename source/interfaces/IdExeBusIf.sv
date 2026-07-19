interface IdExeBusIf;
    import TypesPkg::*;

    // Decode-to-execute bus. It carries decoded control plus source register
    // metadata so hazard detection and forwarding do not need to re-decode insn.
    logic              valid;
    instruction_addr_t pc;
    logic              predictedTaken;
    instruction_addr_t predictedTarget;
    bpu_index_t        predictorIndex;
    logic [BPU_HISTORY_WIDTH-1:0] historySnapshot;
    tage_meta_t        tageMeta;
    logic predictedBtbHit;
    logic predictedRasUsed;
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
    logic              decodeException;
    logic [5:0]        decodeExceptionCause;
    word_t             exceptionValue;
    logic              serialize;
    logic              mret;

    // Driven by IdStages/Decoder. Register data is attached separately by the
    // top-level register file before entering ID/EX.
    modport decode(
        output pc,
        output predictedTaken,
        output predictedTarget,
        output predictorIndex,
        output historySnapshot,
        output tageMeta,
        output predictedBtbHit, predictedRasUsed,
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
        ,output decodeException
        ,output decodeExceptionCause
        ,output exceptionValue
        ,output serialize
        ,output mret
    );

    // Consumed by the ID/EX pipeline register.
    modport register_in(
        input pc,
        input predictedTaken,
        input predictedTarget,
        input predictorIndex,
        input historySnapshot,
        input tageMeta,
        input predictedBtbHit, predictedRasUsed,
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
        ,input decodeException
        ,input decodeExceptionCause
        ,input exceptionValue
        ,input serialize
        ,input mret
    );

    // Driven by the ID/EX pipeline register.
    modport register_out(
        output pc,
        output predictedTaken,
        output predictedTarget,
        output predictorIndex,
        output historySnapshot,
        output tageMeta,
        output predictedBtbHit, predictedRasUsed,
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
        ,output decodeException
        ,output decodeExceptionCause
        ,output exceptionValue
        ,output serialize
        ,output mret
    );

    // Read-only view for stages/helpers that inspect an already-formed bus.
    modport sink(
        input pc,
        input predictedTaken,
        input predictedTarget,
        input predictorIndex,
        input historySnapshot,
        input tageMeta,
        input predictedBtbHit, predictedRasUsed,
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
        ,input decodeException
        ,input decodeExceptionCause
        ,input exceptionValue
        ,input serialize
        ,input mret
    );
endinterface
