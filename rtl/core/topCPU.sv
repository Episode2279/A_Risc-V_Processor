module topCPU
    import TypesPkg::*;
#(
    parameter int DATA_W = WORD_SIZE,
    parameter int INSN_W = INS_SIZE,
    parameter int ADDR_W = WORD_SIZE,
    parameter int REG_ADDR_W = REG_ADDR,
    parameter int REG_COUNT = REG_NUM,
    parameter int INSN_MEM_ADDR_W = INS_ADDR,
    parameter int INSN_MEM_BYTES = INS_ADDR_SIZE,
    parameter int DATA_MEM_ADDR_W = DATA_ADDR,
    parameter int DATA_MEM_BYTES = DATA_ADDR_SIZE,
    parameter int ICACHE_BYTES = 4096,
    parameter int ICACHE_LINE_BYTES = 16,
    parameter int FETCH_QUEUE_ENTRIES = 8,
    parameter int DCACHE_SET_COUNT = 64,
    parameter int DCACHE_LINE_BYTES = 16,
    parameter logic [DATA_W-1:0] STATE_RESET_VALUE = '0,
    parameter logic [ADDR_W-1:0] RESET_PC = RESET_VECTOR,
    parameter logic [ADDR_W-1:0] PC_INCREMENT = 32'd4,
    parameter logic [DATA_W-1:0] UART_TX_MMIO_ADDR = UART_TX_ADDR,
    parameter logic [DATA_W-1:0] FROMHOST_MMIO_ADDR = FROMHOST_ADDR,
    parameter logic [DATA_W-1:0] TOHOST_MMIO_ADDR = TOHOST_ADDR,
    parameter logic [DATA_W-1:0] MMIO_BASE_ADDR = UART_TX_MMIO_ADDR,
    parameter logic [DATA_W-1:0] MMIO_LAST_ADDR = TOHOST_MMIO_ADDR + 32'd7,
    parameter bit BPU_TAGE_ENABLE = 1'b1,
    parameter bit BPU_SC_ENABLE = 1'b1,
    parameter int BPU_SC_LOW_CONFIDENCE_THRESHOLD = 23,
    parameter int BPU_SC_WEAK_BASE_WEIGHT = 20,
    parameter int BPU_SC_STRONG_BASE_WEIGHT = 62
)
(
    input  logic              clk,
    input  logic              rst,
    input  logic [DATA_W-1:0] fromHost_i,
    output logic [DATA_W-1:0] toHost_o,
    output logic              uartValid_o,
    output logic [7:0]        uartData_o,
    output logic [INSN_W-1:0] check,
    output logic [ADDR_W-1:0] checkPC,
    output logic [DATA_W-1:0] checkData

`ifdef VERILATOR
    ,
    output logic              dbg_wrEnable,
    output logic              dbg_stall,
    output logic              dbg_flush,
    output logic              dbg_jumpEnable,
    output logic              dbg_issue0,
    output logic              dbg_issue1,
    output logic              dbg_if_valid,
    output logic [ADDR_W-1:0] dbg_if_pc,
    output logic [INSN_W-1:0] dbg_if_insn,
    output logic              dbg_if1_valid,
    output logic [ADDR_W-1:0] dbg_if1_pc,
    output logic [INSN_W-1:0] dbg_if1_insn,
    output logic              dbg_id_valid,
    output logic [ADDR_W-1:0] dbg_id_pc,
    output logic [INSN_W-1:0] dbg_id_insn,
    output logic [REG_ADDR_W-1:0] dbg_id_rd,
    output logic              dbg_id_regWrite,
    output logic              dbg_id_memWrite,
    output logic [3:0]        dbg_id_branchCtr,
    output logic [3:0]        dbg_id_aluCtr,
    output logic [2:0]        dbg_id_memCtr,
    output logic [REG_ADDR_W-1:0] dbg_id_regA,
    output logic [REG_ADDR_W-1:0] dbg_id_regB,
    output logic [ADDR_W-1:0] dbg_id_imm,
    output logic              dbg_id1_valid,
    output logic [ADDR_W-1:0] dbg_id1_pc,
    output logic [INSN_W-1:0] dbg_id1_insn,
    output logic [REG_ADDR_W-1:0] dbg_id1_rd,
    output logic              dbg_id1_regWrite,
    output logic              dbg_id1_memWrite,
    output logic [3:0]        dbg_id1_branchCtr,
    output logic [3:0]        dbg_id1_aluCtr,
    output logic [2:0]        dbg_id1_memCtr,
    output logic [REG_ADDR_W-1:0] dbg_id1_regA,
    output logic [REG_ADDR_W-1:0] dbg_id1_regB,
    output logic [ADDR_W-1:0] dbg_id1_imm,
    output logic [ADDR_W-1:0] dbg_ex_pc,
    output logic [REG_ADDR_W-1:0] dbg_ex_rd,
    output logic              dbg_ex_regWrite,
    output logic              dbg_ex_memWrite,
    output logic [2:0]        dbg_ex_memCtr,
    output logic [DATA_W-1:0] dbg_ex_aluOut,
    output logic [DATA_W-1:0] dbg_ex_dataA,
    output logic [DATA_W-1:0] dbg_ex_dataB,
    output logic [ADDR_W-1:0] dbg_ex_imm,
    output logic [ADDR_W-1:0] dbg_ex1_pc,
    output logic [REG_ADDR_W-1:0] dbg_ex1_rd,
    output logic              dbg_ex1_regWrite,
    output logic              dbg_ex1_memWrite,
    output logic [2:0]        dbg_ex1_memCtr,
    output logic [DATA_W-1:0] dbg_ex1_aluOut,
    output logic [DATA_W-1:0] dbg_ex1_dataA,
    output logic [DATA_W-1:0] dbg_ex1_dataB,
    output logic [ADDR_W-1:0] dbg_ex1_imm,
    output logic [ADDR_W-1:0] dbg_mem_pc,
    output logic [REG_ADDR_W-1:0] dbg_mem_rd,
    output logic              dbg_mem_regWrite,
    output logic              dbg_mem_memWrite,
    output logic [2:0]        dbg_mem_memCtr,
    output logic [DATA_W-1:0] dbg_mem_aluOut,
    output logic [DATA_W-1:0] dbg_mem_dataB,
    output logic [DATA_W-1:0] dbg_mem_rdData,
    output logic              dbg_mem_toHostHit,
    output logic              dbg_mem_uartHit,
    output logic              dbg_mem_fromHostHit,
    output logic [ADDR_W-1:0] dbg_mem1_pc,
    output logic [REG_ADDR_W-1:0] dbg_mem1_rd,
    output logic              dbg_mem1_regWrite,
    output logic              dbg_mem1_memWrite,
    output logic [2:0]        dbg_mem1_memCtr,
    output logic [DATA_W-1:0] dbg_mem1_aluOut,
    output logic [DATA_W-1:0] dbg_mem1_dataB,
    output logic [DATA_W-1:0] dbg_mem1_rdData,
    output logic [ADDR_W-1:0] dbg_wb_pc,
    output logic [REG_ADDR_W-1:0] dbg_wb_rd,
    output logic              dbg_wb_regWrite,
    output logic [2:0]        dbg_wb_wbSelect,
    output logic [DATA_W-1:0] dbg_wb_aluSrc,
    output logic [DATA_W-1:0] dbg_wb_rdData,
    output logic [DATA_W-1:0] dbg_wb_dataWb,
    output logic [ADDR_W-1:0] dbg_wb1_pc,
    output logic [REG_ADDR_W-1:0] dbg_wb1_rd,
    output logic              dbg_wb1_regWrite,
    output logic [2:0]        dbg_wb1_wbSelect,
    output logic [DATA_W-1:0] dbg_wb1_aluSrc,
    output logic [DATA_W-1:0] dbg_wb1_rdData,
    output logic [DATA_W-1:0] dbg_wb1_dataWb,
    output logic [$clog2(ROB_ENTRY_NUM+1)-1:0] dbg_robCount,
    output logic [$clog2(UNIFIED_IQ_ENTRY_NUM+1)-1:0] dbg_issueCount,
    output logic [$clog2(LSQ_ENTRY_NUM+1)-1:0] dbg_lsqCount,
    output logic [1:0] dbg_retireCount,
    output logic [63:0] dbg_perfDualIssueCycles, dbg_perfSingleIssueCycles, dbg_perfIqNoReadyCycles,
    output logic [63:0] dbg_perfPort0LsuBlockedCycles, dbg_perfPort0BranchBlockedCycles,
    output logic [63:0] dbg_perfLsqOrderBlockedCycles,
    output logic [63:0] dbg_perfStoreBufferAliasBlockedCycles,
    output logic [63:0] dbg_perfMmioOrderBlockedCycles,
    output logic [63:0] dbg_perfDcacheRequestBlockedCycles,
    output logic [63:0] dbg_perfLsuInternalBlockedCycles,
    output logic [63:0] dbg_perfLsuFallbackCycles,
    output logic [63:0] dbg_perfRobFullCycles, dbg_perfIqFullCycles, dbg_perfLsqFullCycles,
    output logic [63:0] dbg_perfPrfEmptyCycles, dbg_perfBranchCount, dbg_perfBranchMispredictCount,
    output logic [63:0] dbg_perfJumpSerializationCycles
    ,output logic [63:0] dbg_perfConditionalCount,dbg_perfConditionalMispredictCount,
    output logic [63:0] dbg_perfDirectionMispredictCount,dbg_perfTargetMispredictCount,dbg_perfBtbMissCount,
    output logic [63:0] dbg_perfJalMispredictCount,dbg_perfJalrMispredictCount,dbg_perfRasMissCount,
    output logic [63:0] dbg_perfStoreCommitStallCycles,
    output logic [63:0] dbg_perfIcacheRequests,dbg_perfIcacheHits,dbg_perfIcacheMisses,
    output logic [63:0] dbg_perfIcacheLineMisses,dbg_perfIcacheMissStallCycles,
    output logic [63:0] dbg_perfIcacheRefillLines,dbg_perfIcacheRefillCycles,
    output logic [63:0] dbg_perfIcacheCrosslineMisses,dbg_perfIcacheResponseBackpressureCycles,
    output logic [63:0] dbg_perfDcacheRequests,dbg_perfDcacheLoadHits,dbg_perfDcacheLoadMisses,
    output logic [63:0] dbg_perfDcacheStoreHits,dbg_perfDcacheStoreMisses,dbg_perfDcacheBusyCycles,
    output logic [63:0] dbg_perfDcacheRefillLines,dbg_perfDcacheRefillCycles,
    output logic [63:0] dbg_perfDcacheMmioRequests,dbg_perfDcacheRequestBackpressureCycles,
    output logic dbg_scOverrideEvent,dbg_scCorrectEvent,dbg_scHarmEvent,
    output logic dbg_branchTrainValid,dbg_branchTrainTaken,
    output logic dbg_branchTrainTagePrediction,dbg_branchTrainFinalPrediction,
    output logic dbg_branchTrainStrong,dbg_branchTrainScLowConfidence,
    output logic [31:0] dbg_branchTrainPc,
    output logic [63:0] dbg_branchTrainHistory,
    output logic [15:0] dbg_branchTrainPathHistory,
    // Event-oriented OoO trace ports.  Unlike the legacy EX/MEM/WB views,
    // these signals preserve the ROB identity of each dynamic instruction.
    output logic dbg_dispatch0Valid, dbg_dispatch1Valid,
    output rob_tag_t dbg_dispatch0RobTag, dbg_dispatch1RobTag,
    output logic [ADDR_W-1:0] dbg_dispatch0Pc, dbg_dispatch1Pc,
    output logic [INSN_W-1:0] dbg_dispatch0Insn, dbg_dispatch1Insn,
    output fu_class_t dbg_dispatch0Fu, dbg_dispatch1Fu,
    output logic dbg_oooIssue0Valid, dbg_oooIssue1Valid,
    output logic dbg_oooIssueFallbackValid,
    output rob_tag_t dbg_oooIssue0RobTag, dbg_oooIssue1RobTag,
    output rob_tag_t dbg_oooIssueFallbackRobTag,
    output logic [ADDR_W-1:0] dbg_oooIssue0Pc, dbg_oooIssue1Pc,
    output logic [ADDR_W-1:0] dbg_oooIssueFallbackPc,
    output fu_class_t dbg_oooIssue0Fu, dbg_oooIssue1Fu,
    output fu_class_t dbg_oooIssueFallbackFu,
    output logic dbg_complete0Valid, dbg_complete1Valid,
    output rob_tag_t dbg_complete0RobTag, dbg_complete1RobTag,
    output logic dbg_complete0Exception, dbg_complete1Exception,
    output logic [DATA_W-1:0] dbg_complete0Value, dbg_complete1Value,
    output logic dbg_commit0Valid, dbg_commit1Valid,
    output rob_tag_t dbg_commit0RobTag, dbg_commit1RobTag,
    output logic [ADDR_W-1:0] dbg_commit0Pc, dbg_commit1Pc,
    output logic [REG_ADDR_W-1:0] dbg_commit0Rd, dbg_commit1Rd,
    output logic [DATA_W-1:0] dbg_commit0Data, dbg_commit1Data,
    output logic dbg_recoverValid,
    output rob_tag_t dbg_recoverRobTag,
    output logic dbg_globalFlush
`endif
);

    InstructionPacketIf if_fetch_bus();
    InstructionPacketIf if_fetch_bus1();
    InstructionPacketIf if_decode_bus();
    InstructionPacketIf if_decode_bus1();
    IdExeBusIf id_exe_in_bus();
    IdExeBusIf id_exe1_in_bus();

    // Compatibility views retained for existing waveform/testbench tooling.
    IdExeBusIf id_exe_bus();
    IdExeBusIf id_exe1_bus();
    ExeMemBusIf exe_mem_bus();
    ExeMemBusIf exe_mem1_bus();
    MemWbBusIf mem_wb_bus();
    MemWbBusIf mem_wb1_bus();

    logic [1:0] dispatchAccept;
    logic dispatchStall;
    logic fetchQueueReady;
    logic fetchResponseConsumed;
    logic [$clog2(FETCH_QUEUE_ENTRIES+1)-1:0] fetchQueueCount;
    logic wrEnable;
    logic stall;
    logic issue0;
    logic issue1;
    logic flush;
    logic jumpEnable;

    logic memoryValid;
    logic memoryWrite;
    rob_tag_t memoryRequestId;
    rob_tag_t memoryResponseId;
    word_t memoryAddress;
    word_t memoryWriteData;
    mem_access_t memoryAccess;
    word_t rdData_mem;
    word_t rdData1_mem;
    logic memoryRequestReady;
    logic memoryIdle;
    logic memoryResponseValid;
    logic memoryResponseReady;
    logic memToHostHit;
    logic memUartHit;
    logic memFromHostHit;

    logic [63:0] perfIcacheRequests;
    logic [63:0] perfIcacheHits;
    logic [63:0] perfIcacheMisses;
    logic [63:0] perfIcacheLineMisses;
    logic [63:0] perfIcacheMissStallCycles;
    logic [63:0] perfIcacheRefillLines;
    logic [63:0] perfIcacheRefillCycles;
    logic [63:0] perfIcacheCrosslineMisses;
    logic [63:0] perfIcacheResponseBackpressureCycles;
    logic [63:0] perfDcacheRequests;
    logic [63:0] perfDcacheLoadHits;
    logic [63:0] perfDcacheLoadMisses;
    logic [63:0] perfDcacheStoreHits;
    logic [63:0] perfDcacheStoreMisses;
    logic [63:0] perfDcacheBusyCycles;
    logic [63:0] perfDcacheRefillLines;
    logic [63:0] perfDcacheRefillCycles;
    logic [63:0] perfDcacheMmioRequests;
    logic [63:0] perfDcacheRequestBackpressureCycles;

    logic csrValid;
    csr_op_t csrOp;
    csr_addr_t csrAddr;
    word_t csrWriteData;
    word_t csrReadData;

    logic branchResolved;
    instruction_addr_t branchPc;
    logic branchIsConditional;
    logic branchIsCall;
    logic branchIsReturn;
    bpu_index_t branchPredictorIndex;
    logic branchTaken;
    instruction_addr_t branchTarget;
    logic branchMispredicted;
    instruction_addr_t branchRedirect;
    rob_tag_t branchRobTag;
    logic [1:0] branchCheckpointValid;
    rob_tag_t branchCheckpointTag [2];
    logic [BPU_HISTORY_WIDTH-1:0] branchCheckpointHistory [2];
    tage_history_t branchCheckpointTageHistory [2];
    tage_path_history_t branchCheckpointTagePathHistory [2];
    bpu_train_t branchTrain;
    logic bpuUpdateReady;
    logic trapValid;
    instruction_addr_t trapPc;
    logic [5:0] trapCause;
    word_t trapValue;
    logic mretCommit;
    instruction_addr_t trapVector;
    logic btbPredictTaken;
    instruction_addr_t btbPredictTarget;
    bpu_index_t bpuPredictorIndex;
    logic bpuPredictTaken1;
    instruction_addr_t bpuPredictTarget1;
    bpu_index_t bpuPredictorIndex1;
    logic [BPU_HISTORY_WIDTH-1:0] bpuHistorySnapshot;
    logic [BPU_HISTORY_WIDTH-1:0] bpuHistorySnapshot1;
    tage_meta_t bpuTageMeta;
    tage_meta_t bpuTageMeta1;
    logic bpuBtbHit,bpuBtbHit1,bpuRasUsed,bpuRasUsed1;
    logic bpuPredictionValid;
    logic bpuQueryValid;
    logic bpuQueryReady;
    logic icacheResponseValid;
    instruction_addr_t bpuRequestPc,bpuRequestPc1;
    instruction_t bpuRequestInsn,bpuRequestInsn1;
    instruction_addr_t bpuResponsePc,bpuResponsePc1;
    instruction_t bpuResponseInsn,bpuResponseInsn1;

    logic [1:0] commitValid;
    instruction_addr_t commitPc [2];
    reg_addr_t commitRd [2];
    word_t commitData [2];
    logic [1:0] retireCount;
    logic [1:0] architecturalRetireCount;
    logic [$clog2(ROB_ENTRY_NUM+1)-1:0] robCount;
    logic [$clog2(UNIFIED_IQ_ENTRY_NUM+1)-1:0] issueCount;
    logic [$clog2(LSQ_ENTRY_NUM+1)-1:0] lsqCount;

    logic [DATA_W-1:0] aluOut_exe;
    logic [DATA_W-1:0] aluOut1_exe;
    logic [DATA_W-1:0] forwardA_exe;
    logic [DATA_W-1:0] forwardB_exe;
    logic [DATA_W-1:0] forwardA1_exe;
    logic [DATA_W-1:0] forwardB1_exe;
    logic [DATA_W-1:0] data_wb;
    logic [DATA_W-1:0] data1_wb;

    assign issue0 = dispatchAccept[0];
    assign issue1 = dispatchAccept[1];
    assign stall = dispatchStall;
    assign wrEnable = !stall;
    assign jumpEnable = trapValid || (branchResolved && branchMispredicted);
    assign flush = jumpEnable;
    assign architecturalRetireCount = retireCount;
    assign check = if_fetch_bus.insn;
    assign checkPC = if_fetch_bus.pc;
    assign checkData = commitValid[0] ? commitData[0] :
                       commitValid[1] ? commitData[1] : '0;

    BranchPredictionUnit #(
        .TAGE_ENABLE(BPU_TAGE_ENABLE),
        .SC_ENABLE(BPU_SC_ENABLE),
        .SC_LOW_CONFIDENCE_THRESHOLD(
            BPU_SC_LOW_CONFIDENCE_THRESHOLD),
        .SC_WEAK_BASE_WEIGHT(BPU_SC_WEAK_BASE_WEIGHT),
        .SC_STRONG_BASE_WEIGHT(BPU_SC_STRONG_BASE_WEIGHT)
    ) bpu (
        .clk(clk),
        .rst(rst),
        .flush_i(trapValid),
        .cancel_i(jumpEnable),
        .queryValid_i(bpuQueryValid),
        .queryReady_o(bpuQueryReady),
        .queryPc_i(bpuRequestPc),
        .instructionValid_i(icacheResponseValid),
        .queryInsn_i(bpuRequestInsn),
        .predictionValid_o(bpuPredictionValid),
        .responsePc_o(bpuResponsePc),
        .responseInsn_o(bpuResponseInsn),
        .predictTaken_o(btbPredictTaken),
        .predictTarget_o(btbPredictTarget),
        .predictorIndex_o(bpuPredictorIndex),
        .tageMeta_o(bpuTageMeta),
        .queryAdvance_i(fetchResponseConsumed && !jumpEnable),
        .queryPc1_i(bpuRequestPc1), .queryInsn1_i(bpuRequestInsn1),
        .responsePc1_o(bpuResponsePc1), .responseInsn1_o(bpuResponseInsn1),
        .queryAdvance1_i(fetchResponseConsumed &&
                         !btbPredictTaken && !jumpEnable),
        .predictTaken1_o(bpuPredictTaken1), .predictTarget1_o(bpuPredictTarget1),
        .predictorIndex1_o(bpuPredictorIndex1),
        .tageMeta1_o(bpuTageMeta1),
        .historySnapshot_o(bpuHistorySnapshot), .historySnapshot1_o(bpuHistorySnapshot1),
        .btbHit_o(bpuBtbHit),.btbHit1_o(bpuBtbHit1),.rasUsed_o(bpuRasUsed),.rasUsed1_o(bpuRasUsed1),
        .updateValid_i(branchTrain.valid),
        .updatePc_i(branchTrain.pc),
        .updateIsConditional_i(branchTrain.isConditional),
        .updateTaken_i(branchTrain.taken),
        .updateTarget_i(branchTrain.target),
        .updatePredictorIndex_i(branchTrain.predictorIndex),
        .updateTageMeta_i(branchTrain.tageMeta),
        .updateReady_o(bpuUpdateReady),
        .resolveValid_i(branchResolved), .resolvePc_i(branchPc),
        .resolveIsConditional_i(branchIsConditional), .resolveTaken_i(branchTaken),
        .resolveMispredicted_i(branchMispredicted),
        .resolveIsCall_i(branchIsCall), .resolveIsReturn_i(branchIsReturn),
        .resolveRobTag_i(branchRobTag), .checkpointAllocValid_i(branchCheckpointValid),
        .checkpointAllocTag_i(branchCheckpointTag),
        .checkpointAllocHistory_i(branchCheckpointHistory),
        .checkpointAllocTageHistory_i(branchCheckpointTageHistory),
        .checkpointAllocTagePathHistory_i(
            branchCheckpointTagePathHistory)
    );

    DualIfStages #(
        .ADDR_W(ADDR_W),
        .INSN_W(INSN_W),
        .MEM_ADDR_W(INSN_MEM_ADDR_W),
        .MEM_BYTES(INSN_MEM_BYTES),
        .ICACHE_BYTES(ICACHE_BYTES),
        .ICACHE_LINE_BYTES(ICACHE_LINE_BYTES),
        .RESET_PC(RESET_PC),
        .PC_INCREMENT(PC_INCREMENT)
    ) ifStage (
        .clk(clk),
        .rst(rst),
        .jump_address(trapValid ? trapVector : branchRedirect),
        .jump_enable(jumpEnable),
        .predictionValid_i(bpuPredictionValid),
        .responsePc_i(bpuResponsePc), .responseInsn_i(bpuResponseInsn),
        .responsePc1_i(bpuResponsePc1), .responseInsn1_i(bpuResponseInsn1),
        .predictTaken_i(btbPredictTaken),
        .predictTarget_i(btbPredictTarget),
        .predictorIndex_i(bpuPredictorIndex),
        .predictTaken1_i(bpuPredictTaken1), .predictTarget1_i(bpuPredictTarget1),
        .predictorIndex1_i(bpuPredictorIndex1),
        .historySnapshot_i(bpuHistorySnapshot), .historySnapshot1_i(bpuHistorySnapshot1),
        .tageMeta_i(bpuTageMeta), .tageMeta1_i(bpuTageMeta1),
        .btbHit_i(bpuBtbHit),.btbHit1_i(bpuBtbHit1),.rasUsed_i(bpuRasUsed),.rasUsed1_i(bpuRasUsed1),
        .responseReady_i(fetchQueueReady),
        .responseConsumed_o(fetchResponseConsumed),
        .requestReady_i(bpuQueryReady),
        .requestValid_o(bpuQueryValid),
        .requestPc_o(bpuRequestPc), .requestInsn_o(bpuRequestInsn),
        .requestPc1_o(bpuRequestPc1), .requestInsn1_o(bpuRequestInsn1),
        .cacheResponseValid_o(icacheResponseValid),
        .perfRequestCount_o(perfIcacheRequests),
        .perfHitCount_o(perfIcacheHits),
        .perfMissCount_o(perfIcacheMisses),
        .perfLineMissCount_o(perfIcacheLineMisses),
        .perfMissStallCycles_o(perfIcacheMissStallCycles),
        .perfRefillLineCount_o(perfIcacheRefillLines),
        .perfRefillCycles_o(perfIcacheRefillCycles),
        .perfCrosslineMissCount_o(perfIcacheCrosslineMisses),
        .perfResponseBackpressureCycles_o(
            perfIcacheResponseBackpressureCycles),
        .fetch_packet0(if_fetch_bus),
        .fetch_packet1(if_fetch_bus1)
    );

    FetchQueue #(
        .DEPTH(FETCH_QUEUE_ENTRIES)
    ) fetchQueue (
        .clk(clk),
        .rst(rst),
        .fetch0_i(if_fetch_bus),
        .fetch1_i(if_fetch_bus1),
        .flush_i(flush),
        .fetchReady_o(fetchQueueReady),
        .issue0_i(issue0),
        .issue1_i(issue1),
        .packet0_o(if_decode_bus),
        .packet1_o(if_decode_bus1),
        .count_o(fetchQueueCount)
    );

    IdStages idStage (
        .id_packet(if_decode_bus),
        .id_bus(id_exe_in_bus)
    );

    IdStages idStage1 (
        .id_packet(if_decode_bus1),
        .id_bus(id_exe1_in_bus)
    );

    OoOBackend #(
        .MMIO_BASE_ADDR(MMIO_BASE_ADDR),
        .MMIO_LAST_ADDR(MMIO_LAST_ADDR)
    ) backend (
        .clk(clk),
        .rst(rst),
        .flush_i(trapValid),
        .decode0_bus(id_exe_in_bus),
        .decode1_bus(id_exe1_in_bus),
        .dispatchAccept_o(dispatchAccept),
        .dispatchStall_o(dispatchStall),
        .memoryRequestReady_i(memoryRequestReady),
        .memoryIdle_i(memoryIdle),
        .memoryResponseValid_i(memoryResponseValid),
        .memoryResponseId_i(memoryResponseId),
        .memoryResponseData_i(rdData_mem),
        .memoryResponseReady_o(memoryResponseReady),
        .memoryValid_o(memoryValid),
        .memoryWrite_o(memoryWrite),
        .memoryRequestId_o(memoryRequestId),
        .memoryAddress_o(memoryAddress),
        .memoryWriteData_o(memoryWriteData),
        .memoryAccess_o(memoryAccess),
        .csrReadData_i(csrReadData),
        .csrValid_o(csrValid),
        .csrOp_o(csrOp),
        .csrAddr_o(csrAddr),
        .csrWriteData_o(csrWriteData),
        .branchResolved_o(branchResolved),
        .branchPc_o(branchPc),
        .branchIsConditional_o(branchIsConditional),
        .branchIsCall_o(branchIsCall), .branchIsReturn_o(branchIsReturn),
        .branchPredictorIndex_o(branchPredictorIndex),
        .branchTaken_o(branchTaken),
        .branchTarget_o(branchTarget),
        .branchMispredicted_o(branchMispredicted),
        .branchRedirect_o(branchRedirect),
        .branchRobTag_o(branchRobTag), .branchCheckpointValid_o(branchCheckpointValid),
        .branchCheckpointTag_o(branchCheckpointTag),
        .branchCheckpointHistory_o(branchCheckpointHistory),
        .branchCheckpointTageHistory_o(branchCheckpointTageHistory),
        .branchCheckpointTagePathHistory_o(
            branchCheckpointTagePathHistory),
        .branchTrain_o(branchTrain),
        .branchTrainReady_i(bpuUpdateReady),
        .trapValid_o(trapValid),
        .trapPc_o(trapPc),
        .trapCause_o(trapCause),
        .trapValue_o(trapValue),
        .mretCommit_o(mretCommit),
        .commitValid_o(commitValid),
        .commitPc_o(commitPc),
        .commitArchRd_o(commitRd),
        .commitData_o(commitData),
        .retireCount_o(retireCount),
        .robCount_o(robCount),
        .issueCount_o(issueCount),
        .lsqCount_o(lsqCount),
        .perfDualIssueCycles_o(dbg_perfDualIssueCycles), .perfSingleIssueCycles_o(dbg_perfSingleIssueCycles),
        .perfIqNoReadyCycles_o(dbg_perfIqNoReadyCycles),
        .perfPort0LsuBlockedCycles_o(dbg_perfPort0LsuBlockedCycles),
        .perfPort0BranchBlockedCycles_o(dbg_perfPort0BranchBlockedCycles),
        .perfLsqOrderBlockedCycles_o(dbg_perfLsqOrderBlockedCycles),
        .perfStoreBufferAliasBlockedCycles_o(
            dbg_perfStoreBufferAliasBlockedCycles),
        .perfMmioOrderBlockedCycles_o(dbg_perfMmioOrderBlockedCycles),
        .perfDcacheRequestBlockedCycles_o(
            dbg_perfDcacheRequestBlockedCycles),
        .perfLsuInternalBlockedCycles_o(dbg_perfLsuInternalBlockedCycles),
        .perfLsuFallbackCycles_o(dbg_perfLsuFallbackCycles),
        .perfRobFullCycles_o(dbg_perfRobFullCycles), .perfIqFullCycles_o(dbg_perfIqFullCycles),
        .perfLsqFullCycles_o(dbg_perfLsqFullCycles), .perfPrfEmptyCycles_o(dbg_perfPrfEmptyCycles),
        .perfBranchCount_o(dbg_perfBranchCount), .perfBranchMispredictCount_o(dbg_perfBranchMispredictCount),
        .perfJumpSerializationCycles_o(dbg_perfJumpSerializationCycles)
        ,.perfConditionalCount_o(dbg_perfConditionalCount),
        .perfConditionalMispredictCount_o(dbg_perfConditionalMispredictCount),
        .perfDirectionMispredictCount_o(dbg_perfDirectionMispredictCount),
        .perfTargetMispredictCount_o(dbg_perfTargetMispredictCount),.perfBtbMissCount_o(dbg_perfBtbMissCount),
        .perfJalMispredictCount_o(dbg_perfJalMispredictCount),.perfJalrMispredictCount_o(dbg_perfJalrMispredictCount),
        .perfRasMissCount_o(dbg_perfRasMissCount),
        .perfStoreCommitStallCycles_o(dbg_perfStoreCommitStallCycles)
    );

    assign exe_mem_bus.valid = memoryValid;
    assign exe_mem_bus.pc = '0;
    assign exe_mem_bus.registerWriteEnable = memoryValid && !memoryWrite;
    assign exe_mem_bus.dataWriteEnable = memoryValid && memoryWrite;
    assign exe_mem_bus.wbSelect = memoryWrite ? WB_ALU : WB_MEM;
    assign exe_mem_bus.memCtr = memoryAccess;
    assign exe_mem_bus.dataB = memoryWriteData;
    assign exe_mem_bus.rd = '0;
    assign exe_mem_bus.immediate = '0;
    assign exe_mem_bus.aluOut = memoryAddress;
    assign exe_mem_bus.csrData = '0;

    MEMStages #(
        .DATA_W(DATA_W),
        .LOGIC_ADDR_W(DATA_MEM_ADDR_W),
        .MEM_BYTES(DATA_MEM_BYTES),
        .CACHE_SET_COUNT(DCACHE_SET_COUNT),
        .CACHE_LINE_BYTES(DCACHE_LINE_BYTES),
        .UART_TX_MMIO_ADDR(UART_TX_MMIO_ADDR),
        .FROMHOST_MMIO_ADDR(FROMHOST_MMIO_ADDR),
        .TOHOST_MMIO_ADDR(TOHOST_MMIO_ADDR)
        ,.MMIO_BASE_ADDR(MMIO_BASE_ADDR)
        ,.MMIO_LAST_ADDR(MMIO_LAST_ADDR)
    ) memStage (
        .clk(clk),
        .rst(rst),
        .fromHost_i(fromHost_i),
        .requestValid_i(memoryValid),
        .requestReady_o(memoryRequestReady),
        .requestWrite_i(memoryWrite),
        .requestId_i(memoryRequestId),
        .requestAddress_i(memoryAddress),
        .requestWriteData_i(memoryWriteData),
        .requestAccess_i(memoryAccess),
        .responseValid_o(memoryResponseValid),
        .responseReady_i(memoryResponseReady),
        .responseId_o(memoryResponseId),
        .idle_o(memoryIdle),
        .responseData_o(rdData_mem),
        .toHost_o(toHost_o),
        .uartValid_o(uartValid_o),
        .uartData_o(uartData_o),
        .toHostHit_o(memToHostHit),
        .uartHit_o(memUartHit),
        .fromHostHit_o(memFromHostHit),
        .perfRequestCount_o(perfDcacheRequests),
        .perfLoadHitCount_o(perfDcacheLoadHits),
        .perfLoadMissCount_o(perfDcacheLoadMisses),
        .perfStoreHitCount_o(perfDcacheStoreHits),
        .perfStoreMissCount_o(perfDcacheStoreMisses),
        .perfBusyCycles_o(perfDcacheBusyCycles),
        .perfRefillLineCount_o(perfDcacheRefillLines),
        .perfRefillCycles_o(perfDcacheRefillCycles),
        .perfMmioRequestCount_o(perfDcacheMmioRequests),
        .perfRequestBackpressureCycles_o(
            perfDcacheRequestBackpressureCycles)
    );

    CSRFile csrFile (
        .clk(clk),
        .rst(rst),
        .retireCount_i(architecturalRetireCount),
        .csrValid_i(csrValid),
        .csrOp_i(csrOp),
        .csrAddr_i(csrAddr),
        .csrWriteData_i(csrWriteData),
        .csrReadData_o(csrReadData),
        .trapValid_i(trapValid),
        .trapPc_i(trapPc),
        .trapCause_i(trapCause),
        .trapValue_i(trapValue),
        .mret_i(mretCommit),
        .trapVector_o(trapVector)
    );

    // Compatibility-only views for the existing textual pipeline dumper.
    assign id_exe_bus.pc = id_exe_in_bus.pc;
    assign id_exe_bus.predictedTaken = id_exe_in_bus.predictedTaken;
    assign id_exe_bus.predictedTarget = id_exe_in_bus.predictedTarget;
    assign id_exe_bus.predictorIndex = id_exe_in_bus.predictorIndex;
    assign id_exe_bus.historySnapshot = id_exe_in_bus.historySnapshot;
    assign id_exe_bus.tageMeta = id_exe_in_bus.tageMeta;
    assign id_exe_bus.predictedBtbHit = id_exe_in_bus.predictedBtbHit;
    assign id_exe_bus.predictedRasUsed = id_exe_in_bus.predictedRasUsed;
    assign id_exe_bus.rd = id_exe_in_bus.rd;
    assign id_exe_bus.registerWriteEnable = id_exe_in_bus.registerWriteEnable;
    assign id_exe_bus.dataWriteEnable = id_exe_in_bus.dataWriteEnable;
    assign id_exe_bus.memCtr = id_exe_in_bus.memCtr;
    assign id_exe_bus.immediate = id_exe_in_bus.immediate;
    assign id_exe1_bus.pc = id_exe1_in_bus.pc;
    assign id_exe1_bus.predictedTaken = id_exe1_in_bus.predictedTaken;
    assign id_exe1_bus.predictedTarget = id_exe1_in_bus.predictedTarget;
    assign id_exe1_bus.predictorIndex = id_exe1_in_bus.predictorIndex;
    assign id_exe1_bus.historySnapshot = id_exe1_in_bus.historySnapshot;
    assign id_exe1_bus.tageMeta = id_exe1_in_bus.tageMeta;
    assign id_exe1_bus.predictedBtbHit = id_exe1_in_bus.predictedBtbHit;
    assign id_exe1_bus.predictedRasUsed = id_exe1_in_bus.predictedRasUsed;
    assign id_exe1_bus.rd = id_exe1_in_bus.rd;
    assign id_exe1_bus.registerWriteEnable = id_exe1_in_bus.registerWriteEnable;
    assign id_exe1_bus.dataWriteEnable = id_exe1_in_bus.dataWriteEnable;
    assign id_exe1_bus.memCtr = id_exe1_in_bus.memCtr;
    assign id_exe1_bus.immediate = id_exe1_in_bus.immediate;
    assign aluOut_exe = memoryAddress;
    assign aluOut1_exe = '0;
    assign forwardA_exe = '0;
    assign forwardB_exe = memoryWriteData;
    assign forwardA1_exe = '0;
    assign forwardB1_exe = '0;

    assign exe_mem1_bus.valid = 1'b0;
    assign exe_mem1_bus.pc = '0;
    assign exe_mem1_bus.registerWriteEnable = 1'b0;
    assign exe_mem1_bus.dataWriteEnable = 1'b0;
    assign exe_mem1_bus.wbSelect = WB_ALU;
    assign exe_mem1_bus.memCtr = MEM_WORD;
    assign exe_mem1_bus.dataB = '0;
    assign exe_mem1_bus.rd = '0;
    assign exe_mem1_bus.immediate = '0;
    assign exe_mem1_bus.aluOut = '0;
    assign exe_mem1_bus.csrData = '0;
    assign rdData1_mem = '0;

    assign mem_wb_bus.valid = commitValid[0];
    assign mem_wb_bus.pc = commitPc[0];
    assign mem_wb_bus.registerWriteEnable = commitValid[0] && (commitRd[0] != '0);
    assign mem_wb_bus.wbSelect = WB_ALU;
    assign mem_wb_bus.immediate = '0;
    assign mem_wb_bus.aluSrc = commitData[0];
    assign mem_wb_bus.rdData = '0;
    assign mem_wb_bus.csrData = '0;
    assign mem_wb_bus.rd = commitRd[0];
    assign data_wb = commitData[0];
    assign mem_wb1_bus.valid = commitValid[1];
    assign mem_wb1_bus.pc = commitPc[1];
    assign mem_wb1_bus.registerWriteEnable = commitValid[1] && (commitRd[1] != '0);
    assign mem_wb1_bus.wbSelect = WB_ALU;
    assign mem_wb1_bus.immediate = '0;
    assign mem_wb1_bus.aluSrc = commitData[1];
    assign mem_wb1_bus.rdData = '0;
    assign mem_wb1_bus.csrData = '0;
    assign mem_wb1_bus.rd = commitRd[1];
    assign data1_wb = commitData[1];

`ifdef VERILATOR
    assign dbg_wrEnable = wrEnable;
    assign dbg_stall = stall;
    assign dbg_flush = flush;
    assign dbg_jumpEnable = jumpEnable;
    assign dbg_issue0 = issue0;
    assign dbg_issue1 = issue1;
    assign dbg_if_valid = (if_fetch_bus.insn != '0);
    assign dbg_if_pc = if_fetch_bus.pc;
    assign dbg_if_insn = if_fetch_bus.insn;
    assign dbg_if1_valid = (if_fetch_bus1.insn != '0);
    assign dbg_if1_pc = if_fetch_bus1.pc;
    assign dbg_if1_insn = if_fetch_bus1.insn;
    assign dbg_id_valid = id_exe_in_bus.valid;
    assign dbg_id_pc = if_decode_bus.pc;
    assign dbg_id_insn = if_decode_bus.insn;
    assign dbg_id_rd = id_exe_in_bus.rd;
    assign dbg_id_regWrite = id_exe_in_bus.registerWriteEnable;
    assign dbg_id_memWrite = id_exe_in_bus.dataWriteEnable;
    assign dbg_id_branchCtr = id_exe_in_bus.branchCtr;
    assign dbg_id_aluCtr = id_exe_in_bus.aluCtr;
    assign dbg_id_memCtr = id_exe_in_bus.memCtr;
    assign dbg_id_regA = id_exe_in_bus.regA;
    assign dbg_id_regB = id_exe_in_bus.regB;
    assign dbg_id_imm = id_exe_in_bus.immediate;
    assign dbg_id1_valid = id_exe1_in_bus.valid;
    assign dbg_id1_pc = if_decode_bus1.pc;
    assign dbg_id1_insn = if_decode_bus1.insn;
    assign dbg_id1_rd = id_exe1_in_bus.rd;
    assign dbg_id1_regWrite = id_exe1_in_bus.registerWriteEnable;
    assign dbg_id1_memWrite = id_exe1_in_bus.dataWriteEnable;
    assign dbg_id1_branchCtr = id_exe1_in_bus.branchCtr;
    assign dbg_id1_aluCtr = id_exe1_in_bus.aluCtr;
    assign dbg_id1_memCtr = id_exe1_in_bus.memCtr;
    assign dbg_id1_regA = id_exe1_in_bus.regA;
    assign dbg_id1_regB = id_exe1_in_bus.regB;
    assign dbg_id1_imm = id_exe1_in_bus.immediate;
    assign dbg_ex_pc = id_exe_bus.pc;
    assign dbg_ex_rd = id_exe_bus.rd;
    assign dbg_ex_regWrite = id_exe_bus.registerWriteEnable;
    assign dbg_ex_memWrite = id_exe_bus.dataWriteEnable;
    assign dbg_ex_memCtr = id_exe_bus.memCtr;
    assign dbg_ex_aluOut = aluOut_exe;
    assign dbg_ex_dataA = forwardA_exe;
    assign dbg_ex_dataB = forwardB_exe;
    assign dbg_ex_imm = id_exe_bus.immediate;
    assign dbg_ex1_pc = id_exe1_bus.pc;
    assign dbg_ex1_rd = id_exe1_bus.rd;
    assign dbg_ex1_regWrite = id_exe1_bus.registerWriteEnable;
    assign dbg_ex1_memWrite = id_exe1_bus.dataWriteEnable;
    assign dbg_ex1_memCtr = id_exe1_bus.memCtr;
    assign dbg_ex1_aluOut = aluOut1_exe;
    assign dbg_ex1_dataA = forwardA1_exe;
    assign dbg_ex1_dataB = forwardB1_exe;
    assign dbg_ex1_imm = id_exe1_bus.immediate;
    assign dbg_mem_pc = exe_mem_bus.pc;
    assign dbg_mem_rd = exe_mem_bus.rd;
    assign dbg_mem_regWrite = exe_mem_bus.registerWriteEnable;
    assign dbg_mem_memWrite = exe_mem_bus.dataWriteEnable;
    assign dbg_mem_memCtr = exe_mem_bus.memCtr;
    assign dbg_mem_aluOut = exe_mem_bus.aluOut;
    assign dbg_mem_dataB = exe_mem_bus.dataB;
    assign dbg_mem_rdData = rdData_mem;
    assign dbg_mem_toHostHit = memToHostHit;
    assign dbg_mem_uartHit = memUartHit;
    assign dbg_mem_fromHostHit = memFromHostHit;
    assign dbg_mem1_pc = '0;
    assign dbg_mem1_rd = '0;
    assign dbg_mem1_regWrite = 1'b0;
    assign dbg_mem1_memWrite = 1'b0;
    assign dbg_mem1_memCtr = MEM_WORD;
    assign dbg_mem1_aluOut = '0;
    assign dbg_mem1_dataB = '0;
    assign dbg_mem1_rdData = '0;
    assign dbg_wb_pc = commitPc[0];
    assign dbg_wb_rd = commitRd[0];
    assign dbg_wb_regWrite = commitValid[0] && (commitRd[0] != '0);
    assign dbg_wb_wbSelect = WB_ALU;
    assign dbg_wb_aluSrc = commitData[0];
    assign dbg_wb_rdData = '0;
    assign dbg_wb_dataWb = commitData[0];
    assign dbg_wb1_pc = commitPc[1];
    assign dbg_wb1_rd = commitRd[1];
    assign dbg_wb1_regWrite = commitValid[1] && (commitRd[1] != '0);
    assign dbg_wb1_wbSelect = WB_ALU;
    assign dbg_wb1_aluSrc = commitData[1];
    assign dbg_wb1_rdData = '0;
    assign dbg_wb1_dataWb = commitData[1];
    assign dbg_robCount = robCount;
    assign dbg_issueCount = issueCount;
    assign dbg_lsqCount = lsqCount;
    assign dbg_retireCount = architecturalRetireCount;
    assign dbg_perfIcacheRequests = perfIcacheRequests;
    assign dbg_perfIcacheHits = perfIcacheHits;
    assign dbg_perfIcacheMisses = perfIcacheMisses;
    assign dbg_perfIcacheLineMisses = perfIcacheLineMisses;
    assign dbg_perfIcacheMissStallCycles = perfIcacheMissStallCycles;
    assign dbg_perfIcacheRefillLines = perfIcacheRefillLines;
    assign dbg_perfIcacheRefillCycles = perfIcacheRefillCycles;
    assign dbg_perfIcacheCrosslineMisses = perfIcacheCrosslineMisses;
    assign dbg_perfIcacheResponseBackpressureCycles =
        perfIcacheResponseBackpressureCycles;
    assign dbg_perfDcacheRequests = perfDcacheRequests;
    assign dbg_perfDcacheLoadHits = perfDcacheLoadHits;
    assign dbg_perfDcacheLoadMisses = perfDcacheLoadMisses;
    assign dbg_perfDcacheStoreHits = perfDcacheStoreHits;
    assign dbg_perfDcacheStoreMisses = perfDcacheStoreMisses;
    assign dbg_perfDcacheBusyCycles = perfDcacheBusyCycles;
    assign dbg_perfDcacheRefillLines = perfDcacheRefillLines;
    assign dbg_perfDcacheRefillCycles = perfDcacheRefillCycles;
    assign dbg_perfDcacheMmioRequests = perfDcacheMmioRequests;
    assign dbg_perfDcacheRequestBackpressureCycles =
        perfDcacheRequestBackpressureCycles;
    assign dbg_scOverrideEvent = branchTrain.valid &&
        branchTrain.isConditional &&
        (branchTrain.tageMeta.tagePrediction !=
         branchTrain.tageMeta.finalPrediction);
    assign dbg_scCorrectEvent = branchTrain.valid &&
        branchTrain.isConditional &&
        (branchTrain.tageMeta.tagePrediction != branchTrain.taken) &&
        (branchTrain.tageMeta.finalPrediction == branchTrain.taken);
    assign dbg_scHarmEvent = branchTrain.valid &&
        branchTrain.isConditional &&
        (branchTrain.tageMeta.tagePrediction == branchTrain.taken) &&
        (branchTrain.tageMeta.finalPrediction != branchTrain.taken);
    assign dbg_branchTrainValid = branchTrain.valid &&
        branchTrain.isConditional;
    assign dbg_branchTrainTaken = branchTrain.taken;
    assign dbg_branchTrainTagePrediction =
        branchTrain.tageMeta.tagePrediction;
    assign dbg_branchTrainFinalPrediction =
        branchTrain.tageMeta.finalPrediction;
    assign dbg_branchTrainStrong = branchTrain.tageMeta.providerValid &&
        !branchTrain.tageMeta.providerWeak;
    assign dbg_branchTrainScLowConfidence =
        branchTrain.tageMeta.scLowConfidence;
    assign dbg_branchTrainPc = branchTrain.pc;
    assign dbg_branchTrainHistory = branchTrain.tageMeta.history;
    assign dbg_branchTrainPathHistory = branchTrain.tageMeta.pathHistory;

    // Event-oriented trace view used by sim_main.cpp and topCPU_tb.sv.  The
    // dispatch Valid signals are suppressed while recovery owns the ROB edge;
    // the combinational allocator tags are not accepted in that situation.
    assign dbg_dispatch0Valid = backend.robAllocValid[0] &&
                                !backend.recoveryValid && !trapValid;
    assign dbg_dispatch1Valid = backend.robAllocValid[1] &&
                                !backend.recoveryValid && !trapValid;
    assign dbg_dispatch0RobTag = backend.robAllocTag[0];
    assign dbg_dispatch1RobTag = backend.robAllocTag[1];
    assign dbg_dispatch0Pc = id_exe_in_bus.pc;
    assign dbg_dispatch1Pc = id_exe1_in_bus.pc;
    assign dbg_dispatch0Insn = if_decode_bus.insn;
    assign dbg_dispatch1Insn = if_decode_bus1.insn;
    assign dbg_dispatch0Fu = backend.renamedUop[0].fuClass;
    assign dbg_dispatch1Fu = backend.renamedUop[1].fuClass;

    assign dbg_oooIssue0Valid = backend.issueValid[0] &&
                                backend.issueReady[0];
    assign dbg_oooIssue1Valid = backend.issueValid[1] &&
                                backend.issueReady[1];
    assign dbg_oooIssueFallbackValid = backend.issueFallbackValid &&
                                       backend.issueFallbackReady;
    assign dbg_oooIssue0RobTag = backend.issueUop[0].robTag;
    assign dbg_oooIssue1RobTag = backend.issueUop[1].robTag;
    assign dbg_oooIssueFallbackRobTag = backend.issueFallbackUop.robTag;
    assign dbg_oooIssue0Pc = backend.issueUop[0].pc;
    assign dbg_oooIssue1Pc = backend.issueUop[1].pc;
    assign dbg_oooIssueFallbackPc = backend.issueFallbackUop.pc;
    assign dbg_oooIssue0Fu = backend.issueUop[0].fuClass;
    assign dbg_oooIssue1Fu = backend.issueUop[1].fuClass;
    assign dbg_oooIssueFallbackFu = backend.issueFallbackUop.fuClass;

    assign dbg_complete0Valid = backend.robCompleteValid[0];
    assign dbg_complete1Valid = backend.robCompleteValid[1];
    assign dbg_complete0RobTag = backend.robCompleteTag[0];
    assign dbg_complete1RobTag = backend.robCompleteTag[1];
    assign dbg_complete0Exception = backend.robCompleteException[0];
    assign dbg_complete1Exception = backend.robCompleteException[1];
    assign dbg_complete0Value = backend.robCompleteValue[0];
    assign dbg_complete1Value = backend.robCompleteValue[1];

    assign dbg_commit0Valid = backend.robRetireValid[0];
    assign dbg_commit1Valid = backend.robRetireValid[1];
    assign dbg_commit0RobTag = backend.robCommitTag[0];
    assign dbg_commit1RobTag = backend.robCommitTag[1];
    assign dbg_commit0Pc = backend.robCommitEntry[0].pc;
    assign dbg_commit1Pc = backend.robCommitEntry[1].pc;
    assign dbg_commit0Rd = commitRd[0];
    assign dbg_commit1Rd = commitRd[1];
    assign dbg_commit0Data = commitData[0];
    assign dbg_commit1Data = commitData[1];
    assign dbg_recoverValid = backend.recoveryValid;
    assign dbg_recoverRobTag = backend.recoveryTag;
    assign dbg_globalFlush = trapValid;
`endif

endmodule
