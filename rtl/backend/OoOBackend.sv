module OoOBackend
    import TypesPkg::*;
#(
    parameter word_t MMIO_BASE_ADDR = UART_TX_ADDR,
    parameter word_t MMIO_LAST_ADDR = TOHOST_ADDR + 32'd7
)
(
    input  logic clk,
    input  logic rst,
    input  logic flush_i,

    IdExeBusIf.sink decode0_bus,
    IdExeBusIf.sink decode1_bus,
    output logic [1:0] dispatchAccept_o,
    output logic dispatchStall_o,

    input  logic memoryRequestReady_i,
    input  logic memoryIdle_i,
    input  logic memoryResponseValid_i,
    input  rob_tag_t memoryResponseId_i,
    input  word_t memoryResponseData_i,
    output logic memoryResponseReady_o,
    output logic memoryValid_o,
    output logic memoryWrite_o,
    output rob_tag_t memoryRequestId_o,
    output word_t memoryAddress_o,
    output word_t memoryWriteData_o,
    output mem_access_t memoryAccess_o,

    input  word_t csrReadData_i,
    output logic csrValid_o,
    output csr_op_t csrOp_o,
    output csr_addr_t csrAddr_o,
    output word_t csrWriteData_o,

    output logic branchResolved_o,
    output instruction_addr_t branchPc_o,
    output logic branchIsConditional_o,
    output logic branchIsCall_o,
    output logic branchIsReturn_o,
    output bpu_index_t branchPredictorIndex_o,
    output logic branchTaken_o,
    output instruction_addr_t branchTarget_o,
    output logic branchMispredicted_o,
    output instruction_addr_t branchRedirect_o,
    output rob_tag_t branchRobTag_o,
    output logic [1:0] branchCheckpointValid_o,
    output rob_tag_t branchCheckpointTag_o [2],
    output logic [BPU_HISTORY_WIDTH-1:0] branchCheckpointHistory_o [2],
    output tage_history_t branchCheckpointTageHistory_o [2],
    output tage_path_history_t branchCheckpointTagePathHistory_o [2],
    output sc_imli_t branchCheckpointScImli_o [2],
    output loop_meta_t branchCheckpointLoopMeta_o [2],
    output bpu_train_t branchTrain_o,
    input  logic branchTrainReady_i,

    output logic trapValid_o,
    output instruction_addr_t trapPc_o,
    output logic [5:0] trapCause_o,
    output word_t trapValue_o,
    output logic mretCommit_o,

    output logic [1:0] commitValid_o,
    output instruction_addr_t commitPc_o [2],
    output reg_addr_t commitArchRd_o [2],
    output word_t commitData_o [2],
    output logic [1:0] retireCount_o,

    output logic [$clog2(ROB_ENTRY_NUM+1)-1:0] robCount_o,
    output logic [$clog2(UNIFIED_IQ_ENTRY_NUM+1)-1:0] issueCount_o,
    output logic [$clog2(LSQ_ENTRY_NUM+1)-1:0] lsqCount_o,
    output logic [63:0] perfDualIssueCycles_o, perfSingleIssueCycles_o, perfIqNoReadyCycles_o,
    output logic [63:0] perfPort0LsuBlockedCycles_o, perfPort0BranchBlockedCycles_o,
    output logic [63:0] perfLsqOrderBlockedCycles_o,
    output logic [63:0] perfStoreBufferAliasBlockedCycles_o,
    output logic [63:0] perfMmioOrderBlockedCycles_o,
    output logic [63:0] perfDcacheRequestBlockedCycles_o,
    output logic [63:0] perfLsuInternalBlockedCycles_o,
    output logic [63:0] perfLsuFallbackCycles_o,
    output logic [63:0] perfRobFullCycles_o, perfIqFullCycles_o, perfLsqFullCycles_o, perfPrfEmptyCycles_o,
    output logic [63:0] perfBranchCount_o, perfBranchMispredictCount_o, perfJumpSerializationCycles_o
    ,output logic [63:0] perfConditionalCount_o,perfConditionalMispredictCount_o,
    output logic [63:0] perfDirectionMispredictCount_o,perfTargetMispredictCount_o,perfBtbMissCount_o,
    output logic [63:0] perfJalMispredictCount_o,perfJalrMispredictCount_o,perfRasMissCount_o,
    output logic [63:0] perfStoreCommitStallCycles_o
);

    localparam int PRF_READ_PORTS = 12;

    logic [1:0] laneValid;
    logic [1:0] laneSupported;
    logic [1:0] laneWritesDestination;
    logic [1:0] laneIsMemory;
    logic [1:0] laneNeedsDrained;
    logic [1:0] laneIsControl;
    logic [1:0] laneStartsSerialization;
    logic serializing;
    logic jumpSerializing;
    logic backendDrained;

    phys_reg_addr_t renameSourcePhys [4];
    logic [3:0] renameSourceReady;
    logic [1:0] destinationAvailable;
    logic [1:0] destinationAllocValid;
    phys_reg_addr_t destinationPhys [2];
    renamed_uop_t renamedUop [2];
    rob_entry_t renameRobEntry [2];
    lsq_entry_t renameLsqEntry [2];
    logic [$clog2(PHYS_REG_NUM+1)-1:0] freePhysCount;
    logic recoveryValid;
    rob_tag_t recoveryTag;
    logic [ROB_ENTRY_NUM-1:0] recoveryYoungerMask;
    logic integerOrderingReady;
    logic branchIssueLane;

    logic [1:0] robAllocReady;
    logic [1:0] robAllocValid;
    rob_tag_t robAllocTag [2];
    logic [1:0] robCompleteValid;
    rob_tag_t robCompleteTag [2];
    logic [1:0] robCompleteException;
    logic [5:0] robCompleteCause [2];
    word_t robCompleteValue [2];
    logic [1:0] robCommitValid;
    logic [1:0] robCommitReady;
    logic [1:0] robRetireValid;
    rob_tag_t robCommitTag [2];
    rob_entry_t robCommitEntry [2];
    logic robEmpty;
    logic robFull;

    renamed_uop_t issueDispatchUop [2];
    logic [1:0] issueDispatchReady;
    logic [1:0] issueValid;
    renamed_uop_t issueUop [2];
    logic [1:0] issueReady;
    logic issueFallbackValid;
    renamed_uop_t issueFallbackUop;
    logic issueFallbackReady;
    logic issueEmpty;
    logic issueFull;
    logic [$clog2(UNIFIED_IQ_ENTRY_NUM+1)-1:0] issueCount;

    logic [1:0] lsqAllocValid;
    logic [1:0] lsqAllocReady;
    lsq_tag_t lsqAllocTag [2];
    lsq_entry_t lsqHeadEntry [2];
    lsq_tag_t lsqHeadTag [2];
    logic lsqEmpty;
    logic lsqFull;
    logic [1:0] lsqAddressValid;
    lsq_tag_t lsqAddressTag [2];
    word_t lsqAddress [2];
    logic [1:0] lsqStoreDataValid;
    lsq_tag_t lsqStoreDataTag [2];
    word_t lsqStoreData [2];
    logic [1:0] lsqRetireCount;
    logic lsqIssueReady;
    logic lsqForwardValid;
    word_t lsqForwardData;

    phys_reg_addr_t prfReadAddr [PRF_READ_PORTS];
    word_t prfReadData [PRF_READ_PORTS];
    word_t executeSourceA [2];
    word_t executeSourceB [2];
    word_t fallbackSourceA;
    word_t fallbackSourceB;
    logic [PRF_READ_PORTS-1:0] prfReadReady;
    logic [1:0] prfWritebackValid;
    phys_reg_addr_t prfWritebackPhys [2];
    word_t prfWritebackData [2];

    logic lsuExecuteValid;
    logic lsuCandidateValid;
    logic lsuLoadReadValid;
    rob_tag_t lsuLoadRequestId;
    logic lsuIsStore;
    word_t lsuAddress;
    logic lsuStoreDataValid;
    word_t lsuStoreData;
    mem_access_t lsuMemoryAccess;
    lsq_tag_t lsuTag;

    logic commitStoreValid;
    logic commitStoreMmio;
    logic commitStoreBlocked;
    word_t commitStoreAddress;
    word_t commitStoreData;
    mem_access_t commitStoreAccess;
    logic storeBufferEnqueueReady;
    logic storeBufferDrainValid;
    logic storeBufferDrainReady;
    word_t storeBufferDrainAddress;
    word_t storeBufferDrainData;
    mem_access_t storeBufferDrainAccess;
    logic storeBufferQueryConflict;
    logic storeBufferEmpty;
    logic storeBufferFull;
    logic combinedLsqIssueReady;
    logic combinedForwardValid;
    word_t combinedForwardData;
    logic forceStoreBufferDrain;
    logic selectStoreBufferDrain;
    logic selectLoadRequest;
    logic loadCacheRequestReady;
    logic mmioStoreReady;
    logic mmioStoreRequest;
    logic loadIssueCandidate;
    logic loadAddressIsMmio;
    logic memoryCandidateBlocked;
    logic memoryFallbackIssued;
    logic perfLsqOrderBlocked;
    logic perfStoreBufferAliasBlocked;
    logic perfMmioOrderBlocked;
    logic perfDcacheRequestBlocked;
    logic perfLsuInternalBlocked;
    integer prepLane;
    integer trainLane;

    always_comb begin
        laneValid[0] = decode0_bus.valid;
        laneValid[1] = decode1_bus.valid;
        laneWritesDestination[0] = decode0_bus.valid &&
            decode0_bus.registerWriteEnable && (decode0_bus.rd != '0);
        laneWritesDestination[1] = decode1_bus.valid &&
            decode1_bus.registerWriteEnable && (decode1_bus.rd != '0);
        laneIsMemory[0] = decode0_bus.dataWriteEnable || (decode0_bus.wbSelect == WB_MEM);
        laneIsMemory[1] = decode1_bus.dataWriteEnable || (decode1_bus.wbSelect == WB_MEM);
        laneIsControl[0] = (decode0_bus.branchCtr != BR_NONE) ||
                           (decode0_bus.wbSelect == WB_CSR);
        laneIsControl[1] = (decode1_bus.branchCtr != BR_NONE) ||
                           (decode1_bus.wbSelect == WB_CSR);
        // Conditional branches have no architectural destination and can be
        // recovered by restoring committed rename state plus flushing all
        // younger work. Jumps and CSR operations retain the older serialized
        // behavior until selective ROB checkpoint recovery is available.
        laneStartsSerialization[0] = decode0_bus.serialize || (decode0_bus.wbSelect == WB_CSR);
        laneStartsSerialization[1] = decode1_bus.serialize || (decode1_bus.wbSelect == WB_CSR);
        laneNeedsDrained = laneStartsSerialization;

        backendDrained = (robCount_o == '0) && issueEmpty && lsqEmpty &&
                         storeBufferEmpty && memoryIdle_i;
        laneSupported[0] = !serializing &&
            (!laneNeedsDrained[0] || backendDrained);
        laneSupported[1] = !serializing &&
                           !laneIsControl[1] &&
                           !laneStartsSerialization[1];
    end

    always_comb begin
        for (prepLane = 0; prepLane < 4; prepLane = prepLane + 1) begin
            prfReadAddr[prepLane] = renameSourcePhys[prepLane];
            renameSourceReady[prepLane] = prfReadReady[prepLane];
        end
        prfReadAddr[4] = issueUop[0].src1Phys;
        prfReadAddr[5] = issueUop[0].src2Phys;
        prfReadAddr[6] = issueUop[1].src1Phys;
        prfReadAddr[7] = issueUop[1].src2Phys;
        prfReadAddr[8] = issueFallbackUop.src1Phys;
        prfReadAddr[9] = issueFallbackUop.src2Phys;
        prfReadAddr[10] = robCommitEntry[0].newPhys;
        prfReadAddr[11] = robCommitEntry[1].newPhys;
        executeSourceA[0] = prfReadData[4];
        executeSourceB[0] = prfReadData[5];
        executeSourceA[1] = prfReadData[6];
        executeSourceB[1] = prfReadData[7];
        fallbackSourceA = prfReadData[8];
        fallbackSourceB = prfReadData[9];

        robAllocValid = dispatchAccept_o & laneValid;
        branchCheckpointValid_o[0] = robAllocValid[0] && (decode0_bus.branchCtr != BR_NONE);
        branchCheckpointValid_o[1] = robAllocValid[1] && (decode1_bus.branchCtr != BR_NONE);
        branchCheckpointTag_o[0] = robAllocTag[0];
        branchCheckpointTag_o[1] = robAllocTag[1];
        branchCheckpointHistory_o[0] = decode0_bus.historySnapshot;
        branchCheckpointHistory_o[1] = decode1_bus.historySnapshot;
        branchCheckpointTageHistory_o[0] = decode0_bus.tageMeta.history;
        branchCheckpointTageHistory_o[1] = decode1_bus.tageMeta.history;
        branchCheckpointTagePathHistory_o[0] =
            decode0_bus.tageMeta.pathHistory;
        branchCheckpointTagePathHistory_o[1] =
            decode1_bus.tageMeta.pathHistory;
        branchCheckpointScImli_o[0] = decode0_bus.tageMeta.scImli;
        branchCheckpointScImli_o[1] = decode1_bus.tageMeta.scImli;
        branchCheckpointLoopMeta_o[0] = decode0_bus.tageMeta.loop;
        branchCheckpointLoopMeta_o[1] = decode1_bus.tageMeta.loop;
        lsqAllocValid = robAllocValid & laneIsMemory;

        for (prepLane = 0; prepLane < 2; prepLane = prepLane + 1)
            issueDispatchUop[prepLane] = renamedUop[prepLane];

        lsqAddressValid = '0;
        lsqAddressTag[0] = lsuTag;
        lsqAddressTag[1] = '0;
        lsqAddress[0] = lsuAddress;
        lsqAddress[1] = '0;
        lsqAddressValid[0] = lsuExecuteValid;
        lsqStoreDataValid = '0;
        lsqStoreDataTag[0] = lsuTag;
        lsqStoreDataTag[1] = '0;
        lsqStoreData[0] = lsuStoreData;
        lsqStoreData[1] = '0;
        lsqStoreDataValid[0] = lsuStoreDataValid;

        issueCount_o = issueCount;
        recoveryValid = branchMispredicted_o;
        recoveryTag = branchRobTag_o;
        integerOrderingReady = 1'b1;

        branchTrain_o = '0;
        trainLane = -1;
        if (robRetireValid[0] && robCommitEntry[0].isBranch)
            trainLane = 0;
        else if (robRetireValid[1] && robCommitEntry[1].isBranch)
            trainLane = 1;
        if (trainLane >= 0) begin
            branchTrain_o.valid = 1'b1;
            branchTrain_o.pc = robCommitEntry[trainLane].pc;
            branchTrain_o.isConditional =
                (robCommitEntry[trainLane].branchCtr >= BR_BEQ) &&
                (robCommitEntry[trainLane].branchCtr <= BR_BGEU);
            branchTrain_o.isCall = robCommitEntry[trainLane].isCall;
            branchTrain_o.isReturn = robCommitEntry[trainLane].isReturn;
            branchTrain_o.taken = robCommitEntry[trainLane].branchTaken;
            branchTrain_o.target = robCommitEntry[trainLane].branchTarget;
            branchTrain_o.mispredicted = robCommitEntry[trainLane].branchMispredicted;
            branchTrain_o.predictedTaken = robCommitEntry[trainLane].predictedTaken;
            branchTrain_o.predictedTarget = robCommitEntry[trainLane].predictedTarget;
            branchTrain_o.predictedBtbHit = robCommitEntry[trainLane].predictedBtbHit;
            branchTrain_o.predictedRasUsed = robCommitEntry[trainLane].predictedRasUsed;
            branchTrain_o.predictorIndex = robCommitEntry[trainLane].predictorIndex;
            branchTrain_o.tageMeta = robCommitEntry[trainLane].tageMeta;
            branchTrain_o.branchCtr = robCommitEntry[trainLane].branchCtr;
        end
    end

    BackendCommitStage #(
        .MMIO_BASE_ADDR(MMIO_BASE_ADDR),
        .MMIO_LAST_ADDR(MMIO_LAST_ADDR)
    ) commitStage (
        .recoveryValid_i(recoveryValid),
        .branchTrainReady_i(branchTrainReady_i),
        .storeReady_i(storeBufferEnqueueReady),
        .mmioStoreReady_i(mmioStoreReady),
        .robCommitValid_i(robCommitValid), .robCommitEntry_i(robCommitEntry),
        .lsqHeadEntry_i(lsqHeadEntry), .lsqHeadTag_i(lsqHeadTag),
        .robCommitReady_o(robCommitReady), .robRetireValid_o(robRetireValid),
        .lsqRetireCount_o(lsqRetireCount), .storeValid_o(commitStoreValid),
        .storeMmio_o(commitStoreMmio), .storeBlocked_o(commitStoreBlocked),
        .storeAddress_o(commitStoreAddress), .storeData_o(commitStoreData),
        .storeAccess_o(commitStoreAccess), .trapValid_o(trapValid_o),
        .trapPc_o(trapPc_o), .trapCause_o(trapCause_o),
        .trapValue_o(trapValue_o), .mretCommit_o(mretCommit_o)
    );

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            serializing <= 1'b0;
            jumpSerializing <= 1'b0;
        end else if (flush_i) begin
            serializing <= 1'b0;
            jumpSerializing <= 1'b0;
        end else begin
            if (dispatchAccept_o[0] && laneValid[0] &&
                laneStartsSerialization[0]) begin
                serializing <= 1'b1;
                jumpSerializing <= 1'b0;
            end else if (serializing && (robCount_o == '0)) begin
                serializing <= 1'b0;
                jumpSerializing <= 1'b0;
            end
        end
    end

    BackendDispatchStage dispatchStage (
        .laneValid_i(laneValid),
        .laneSupported_i(laneSupported),
        .laneWritesDestination_i(laneWritesDestination),
        .laneIsMemory_i(laneIsMemory),
        .robCount_i(robCount_o),
        .issueCount_i(issueCount),
        .lsqCount_i(lsqCount_o),
        .freePhysCount_i(freePhysCount),
        .accept_o(dispatchAccept_o),
        .stall_o(dispatchStall_o)
    );

    RenameStage renameStage (
        .clk(clk),
        .rst(rst),
        .restoreCommitted_i(flush_i),
        .recoverValid_i(recoveryValid),
        .recoverTag_i(recoveryTag),
        .decode0_bus(decode0_bus),
        .decode1_bus(decode1_bus),
        .renameEnable_i(dispatchAccept_o),
        .robTag_i(robAllocTag),
        .lsqTag_i(lsqAllocTag),
        .sourcePhys_o(renameSourcePhys),
        .sourceReady_i(renameSourceReady),
        .destinationAvailable_o(destinationAvailable),
        .destinationAllocValid_o(destinationAllocValid),
        .destinationPhys_o(destinationPhys),
        .renamedUop_o(renamedUop),
        .robEntry_o(renameRobEntry),
        .lsqEntry_o(renameLsqEntry),
        .commitValid_i(robRetireValid),
        .commitArchRd_i(commitArchRd_o),
        .commitNewPhys_i('{robCommitEntry[0].newPhys, robCommitEntry[1].newPhys}),
        .commitOldPhys_i('{robCommitEntry[0].oldPhys, robCommitEntry[1].oldPhys}),
        .freePhysCount_o(freePhysCount)
    );

    PhysicalRegisterFile #(
        .READ_PORTS(PRF_READ_PORTS)
    ) physicalRegisterFile (
        .clk(clk),
        .rst(rst),
        .readAddr_i(prfReadAddr),
        .readData_o(prfReadData),
        .readReady_o(prfReadReady),
        .allocValid_i(destinationAllocValid),
        .allocPhys_i(destinationPhys),
        .writebackValid_i(prfWritebackValid),
        .writebackPhys_i(prfWritebackPhys),
        .writebackData_i(prfWritebackData)
    );

    ReorderBuffer reorderBuffer (
        .clk(clk),
        .rst(rst),
        .flush_i(flush_i),
        .recoverValid_i(recoveryValid),
        .recoverTag_i(recoveryTag),
        .recoverYoungerMask_o(recoveryYoungerMask),
        .queryBranchValid_i(1'b0), .queryBranchTag_i('0),
        .queryHasOlderUnresolvedBranch_o(),
        .allocValid_i(robAllocValid),
        .allocEntry_i(renameRobEntry),
        .allocReady_o(robAllocReady),
        .allocTag_o(robAllocTag),
        .completeValid_i(robCompleteValid),
        .completeTag_i(robCompleteTag),
        .completeException_i(robCompleteException),
        .completeCause_i(robCompleteCause),
        .completeValue_i(robCompleteValue),
        .branchResolveValid_i(branchResolved_o),
        .branchResolveTag_i(branchRobTag_o),
        .branchTaken_i(branchTaken_o), .branchTarget_i(branchTarget_o),
        .branchMispredicted_i(branchMispredicted_o),
        .commitValid_o(robCommitValid),
        .commitTag_o(robCommitTag),
        .commitEntry_o(robCommitEntry),
        .commitReady_i(robCommitReady),
        .empty_o(robEmpty),
        .full_o(robFull),
        .count_o(robCount_o)
    );

    BackendIssueStage issueStage (
        .clk(clk),
        .rst(rst),
        .flush_i(flush_i),
        .recoverValid_i(recoveryValid),
        .recoverTag_i(recoveryTag),
        .recoverYoungerMask_i(recoveryYoungerMask),
        .dispatchUop_i(issueDispatchUop),
        .dispatchReady_o(issueDispatchReady),
        .wakeupValid_i(prfWritebackValid),
        .wakeupPhys_i(prfWritebackPhys),
        .issueValid_o(issueValid),
        .issueUop_o(issueUop),
        .issueReady_i(issueReady),
        .fallbackValid_o(issueFallbackValid),
        .fallbackUop_o(issueFallbackUop),
        .fallbackReady_i(issueFallbackReady),
        .empty_o(issueEmpty),
        .full_o(issueFull),
        .count_o(issueCount)
    );

    BackendPerformanceCounters performanceCounters (
        .clk(clk), .rst(rst), .issueValid_i(issueValid), .issueReady_i(issueReady),
        .issueUop_i(issueUop),
        .fallbackValid_i(issueFallbackValid),
        .fallbackReady_i(issueFallbackReady),
        .issueCount_i(issueCount), .robFull_i(robFull),
        .iqFull_i(issueFull), .lsqFull_i(lsqFull), .prfEmpty_i(freePhysCount == 0),
        .branchResolved_i(branchTrain_o.valid), .branchMispredicted_i(branchTrain_o.mispredicted),
        .branchConditional_i(branchTrain_o.isConditional),
        .branchDirectionMispredict_i(branchTrain_o.isConditional &&
            (branchTrain_o.tageMeta.finalPrediction != branchTrain_o.taken)),
        .branchTargetMispredict_i(branchTrain_o.taken && branchTrain_o.predictedTaken &&
            (branchTrain_o.predictedTarget != branchTrain_o.target)),
        .branchBtbMiss_i(branchTrain_o.taken && !branchTrain_o.predictedBtbHit &&
            !branchTrain_o.predictedRasUsed && (branchTrain_o.branchCtr != BR_JAL)),
        .branchJal_i(branchTrain_o.branchCtr == BR_JAL),
        .branchJalr_i(branchTrain_o.branchCtr == BR_JALR),
        .branchRasMiss_i(branchTrain_o.isReturn &&
            (!branchTrain_o.predictedRasUsed || branchTrain_o.mispredicted)),
        .lsuBlocked_i(memoryCandidateBlocked),
        .lsqOrderBlocked_i(perfLsqOrderBlocked),
        .storeBufferAliasBlocked_i(perfStoreBufferAliasBlocked),
        .mmioOrderBlocked_i(perfMmioOrderBlocked),
        .dcacheRequestBlocked_i(perfDcacheRequestBlocked),
        .lsuInternalBlocked_i(perfLsuInternalBlocked),
        .lsuFallbackIssued_i(memoryFallbackIssued),
        .storeCommitBlocked_i(commitStoreBlocked),
        .jumpSerializing_i(jumpSerializing), .dualIssueCycles_o(perfDualIssueCycles_o),
        .singleIssueCycles_o(perfSingleIssueCycles_o), .iqNoReadyCycles_o(perfIqNoReadyCycles_o),
        .port0LsuBlockedCycles_o(perfPort0LsuBlockedCycles_o),
        .port0BranchBlockedCycles_o(perfPort0BranchBlockedCycles_o),
        .lsqOrderBlockedCycles_o(perfLsqOrderBlockedCycles_o),
        .storeBufferAliasBlockedCycles_o(perfStoreBufferAliasBlockedCycles_o),
        .mmioOrderBlockedCycles_o(perfMmioOrderBlockedCycles_o),
        .dcacheRequestBlockedCycles_o(perfDcacheRequestBlockedCycles_o),
        .lsuInternalBlockedCycles_o(perfLsuInternalBlockedCycles_o),
        .lsuFallbackCycles_o(perfLsuFallbackCycles_o),
        .robFullCycles_o(perfRobFullCycles_o),
        .iqFullCycles_o(perfIqFullCycles_o), .lsqFullCycles_o(perfLsqFullCycles_o),
        .prfEmptyCycles_o(perfPrfEmptyCycles_o), .branchCount_o(perfBranchCount_o),
        .branchMispredictCount_o(perfBranchMispredictCount_o),
        .jumpSerializationCycles_o(perfJumpSerializationCycles_o)
        ,.conditionalCount_o(perfConditionalCount_o),.conditionalMispredictCount_o(perfConditionalMispredictCount_o),
        .directionMispredictCount_o(perfDirectionMispredictCount_o),.targetMispredictCount_o(perfTargetMispredictCount_o),
        .btbMissCount_o(perfBtbMissCount_o),.jalMispredictCount_o(perfJalMispredictCount_o),
        .jalrMispredictCount_o(perfJalrMispredictCount_o),.rasMissCount_o(perfRasMissCount_o),
        .storeCommitStallCycles_o(perfStoreCommitStallCycles_o)
    );

    assign loadIssueCandidate = lsuCandidateValid && !lsuIsStore;
    assign loadAddressIsMmio = (lsuAddress >= MMIO_BASE_ADDR) &&
                               (lsuAddress <= MMIO_LAST_ADDR);

    StoreBuffer #(
        .DEPTH(STORE_BUFFER_ENTRY_NUM)
    ) storeBuffer (
        .clk(clk),
        .rst(rst),
        .enqueueValid_i(commitStoreValid && !commitStoreMmio),
        .enqueueReady_o(storeBufferEnqueueReady),
        .enqueueAddress_i(commitStoreAddress),
        .enqueueData_i(commitStoreData),
        .enqueueAccess_i(commitStoreAccess),
        .drainValid_o(storeBufferDrainValid),
        .drainReady_i(storeBufferDrainReady),
        .drainAddress_o(storeBufferDrainAddress),
        .drainData_o(storeBufferDrainData),
        .drainAccess_o(storeBufferDrainAccess),
        .queryValid_i(loadIssueCandidate && !lsqForwardValid),
        .queryAddress_i(lsuAddress),
        .queryAccess_i(lsuMemoryAccess),
        .queryReady_o(),
        .queryConflict_o(storeBufferQueryConflict),
        .queryForwardValid_o(),
        .queryForwardData_o(),
        .empty_o(storeBufferEmpty),
        .full_o(storeBufferFull),
        .count_o()
    );

    // Uncommitted LSQ Stores are younger than every Store Buffer entry and
    // therefore retain forwarding priority.  A Load which overlaps any
    // committed Store Buffer entry waits for that entry to drain; disjoint
    // Loads may still pass.  The Store Buffer's byte-merge query remains
    // active for overlap detection, but its direct completion result is
    // deliberately ignored.  CoreMark exposed a completion/recovery race on
    // the zero-latency committed-Store forwarding path even though the
    // forwarded bytes themselves were correct.  This conservative policy has
    // negligible IPC cost and keeps memory ordering precise until forwarding
    // is reintroduced through a registered, ROB-tagged completion path.
    assign combinedLsqIssueReady = lsqIssueReady &&
        (lsqForwardValid || !storeBufferQueryConflict) &&
        (!loadIssueCandidate || !loadAddressIsMmio ||
         (storeBufferEmpty && lsqHeadEntry[0].valid &&
          (lsqHeadTag[0] == lsuTag)));
    assign combinedForwardValid = lsqForwardValid;
    assign combinedForwardData = lsqForwardData;

    // Break the shared-LSU stall counter into mutually exclusive causes.  A
    // blocked memory candidate may still permit the two ALU candidates to
    // issue through the fallback handshake.
    assign perfLsqOrderBlocked = memoryCandidateBlocked && !lsqIssueReady;
    assign perfStoreBufferAliasBlocked = memoryCandidateBlocked &&
        lsqIssueReady && loadIssueCandidate && !lsqForwardValid &&
        storeBufferQueryConflict;
    assign perfMmioOrderBlocked = memoryCandidateBlocked && lsqIssueReady &&
        (lsqForwardValid || !storeBufferQueryConflict) && loadIssueCandidate &&
        loadAddressIsMmio &&
        !(storeBufferEmpty && lsqHeadEntry[0].valid &&
          (lsqHeadTag[0] == lsuTag));
    assign perfDcacheRequestBlocked = memoryCandidateBlocked &&
        combinedLsqIssueReady && loadIssueCandidate && !combinedForwardValid &&
        !loadCacheRequestReady;
    assign perfLsuInternalBlocked = memoryCandidateBlocked &&
        !perfLsqOrderBlocked && !perfStoreBufferAliasBlocked &&
        !perfMmioOrderBlocked && !perfDcacheRequestBlocked;

/* Legacy inline execution instances retained temporarily for history; the
 * active execution datapath is now owned by BackendExecuteStage.
    OoOExecutionUnit integerExecutionUnit (
        .clk(clk),
        .rst(rst),
        .flush_i(flush_i || recoveryValid),
        .issueValid_i(issueValid[0] && (issueUop[0].fuClass != FU_MEMORY)),
        .issueUop_i(issueUop[0]),
        .sourceA_i(prfReadData[4]),
        .sourceB_i(prfReadData[5]),
        .csrReadData_i(csrReadData_i),
        .orderingReady_i(integerOrderingReady),
        .issueReady_o(integerIssueReady),
        .completionValid_o(integerCompletionValid),
        .completionRobTag_o(integerCompletionTag),
        .completionException_o(integerCompletionException),
        .completionCause_o(integerCompletionCause),
        .completionValue_o(integerCompletionValue),
        .writebackValid_o(integerWritebackValid),
        .writebackPhys_o(integerWritebackPhys),
        .writebackData_o(integerWritebackData),
        .branchResolved_o(branchResolved_o),
        .branchPc_o(branchPc_o),
        .branchIsConditional_o(branchIsConditional_o),
        .branchPredictorIndex_o(branchPredictorIndex_o),
        .branchTaken_o(branchTaken_o),
        .branchTarget_o(branchTarget_o),
        .branchMispredicted_o(branchMispredicted_o),
        .branchRedirect_o(branchRedirect_o),
        .csrValid_o(csrValid_o),
        .csrOp_o(csrOp_o),
        .csrAddr_o(csrAddr_o),
        .csrWriteData_o(csrWriteData_o),
        .completionReady_i(1'b1)
    );

    // Port 1 is deliberately restricted by the unified IQ to ordinary integer
    // uops, so this unit never produces branch/CSR side effects.
    OoOExecutionUnit secondaryIntegerExecutionUnit (
        .clk(clk),
        .rst(rst),
        .flush_i(flush_i || recoveryValid),
        .issueValid_i(issueValid[1]),
        .issueUop_i(issueUop[1]),
        .sourceA_i(prfReadData[6]),
        .sourceB_i(prfReadData[7]),
        .csrReadData_i('0),
        .orderingReady_i(1'b1),
        .issueReady_o(secondaryIssueReady),
        .completionValid_o(secondaryCompletionValid),
        .completionRobTag_o(secondaryCompletionTag),
        .completionException_o(secondaryCompletionException),
        .completionCause_o(secondaryCompletionCause),
        .completionValue_o(secondaryCompletionValue),
        .writebackValid_o(secondaryWritebackValid),
        .writebackPhys_o(secondaryWritebackPhys),
        .writebackData_o(secondaryWritebackData),
        .branchResolved_o(),
        .branchPc_o(),
        .branchIsConditional_o(),
        .branchPredictorIndex_o(),
        .branchTaken_o(),
        .branchTarget_o(),
        .branchMispredicted_o(),
        .branchRedirect_o(),
        .csrValid_o(),
        .csrOp_o(),
        .csrAddr_o(),
        .csrWriteData_o(),
        .completionReady_i(1'b1)
    );

    LoadStoreExecutionUnit loadStoreExecutionUnit (
        .clk(clk),
        .rst(rst),
        .flush_i(flush_i || recoveryValid),
        .issueValid_i(issueValid[0] && (issueUop[0].fuClass == FU_MEMORY)),
        .issueUop_i(issueUop[0]),
        .sourceA_i(prfReadData[4]),
        .sourceB_i(prfReadData[5]),
        .orderingReady_i(lsqIssueReady),
        .forwardValid_i(lsqForwardValid),
        .forwardData_i(lsqForwardData),
        .memoryPortReady_i(!commitStoreValid),
        .memoryReadData_i(memoryReadData_i),
        .issueReady_o(memoryIssueReady),
        .completionValid_o(lsuCompletionValid),
        .completionRobTag_o(lsuCompletionTag),
        .completionException_o(lsuCompletionException),
        .completionCause_o(lsuCompletionCause),
        .completionValue_o(lsuCompletionValue),
        .writebackValid_o(lsuWritebackValid),
        .writebackPhys_o(lsuWritebackPhys),
        .writebackData_o(lsuWritebackData),
        .executeValid_o(lsuExecuteValid),
        .loadReadValid_o(lsuLoadReadValid),
        .isStore_o(lsuIsStore),
        .address_o(lsuAddress),
        .storeData_o(lsuStoreData),
        .memoryAccess_o(lsuMemoryAccess),
        .lsqTag_o(lsuTag),
        .completionReady_i(1'b1)
    );

*/
    BackendExecuteStage executeStage (
        .clk(clk), .rst(rst), .flush_i(flush_i), .recoverValid_i(recoveryValid),
        .recoverYoungerMask_i(recoveryYoungerMask),
        .issueValid_i(issueValid), .issueUop_i(issueUop),
        .sourceA_i(executeSourceA), .sourceB_i(executeSourceB),
        .fallbackValid_i(issueFallbackValid),
        .fallbackUop_i(issueFallbackUop),
        .fallbackSourceA_i(fallbackSourceA),
        .fallbackSourceB_i(fallbackSourceB),
        .csrReadData_i(csrReadData_i), .integerOrderingReady_i(integerOrderingReady),
        .lsqIssueReady_i(combinedLsqIssueReady),
        .lsqForwardValid_i(combinedForwardValid),
        .lsqForwardData_i(combinedForwardData),
        .memoryRequestReady_i(loadCacheRequestReady),
        .memoryResponseValid_i(memoryResponseValid_i),
        .memoryResponseId_i(memoryResponseId_i),
        .memoryResponseData_i(memoryResponseData_i),
        .memoryResponseReady_o(memoryResponseReady_o),
        .issueReady_o(issueReady),
        .fallbackReady_o(issueFallbackReady),
        .memoryCandidateBlocked_o(memoryCandidateBlocked),
        .fallbackIssued_o(memoryFallbackIssued),
        .lsuCandidateValid_o(lsuCandidateValid),
        .completionValid_o(robCompleteValid), .completionTag_o(robCompleteTag),
        .completionException_o(robCompleteException), .completionCause_o(robCompleteCause),
        .completionValue_o(robCompleteValue), .writebackValid_o(prfWritebackValid),
        .writebackPhys_o(prfWritebackPhys), .writebackData_o(prfWritebackData),
        .branchResolved_o(branchResolved_o), .branchPc_o(branchPc_o),
        .branchIsConditional_o(branchIsConditional_o), .branchIsCall_o(branchIsCall_o),
        .branchIsReturn_o(branchIsReturn_o), .branchPredictorIndex_o(branchPredictorIndex_o),
        .branchTaken_o(branchTaken_o), .branchTarget_o(branchTarget_o),
        .branchMispredicted_o(branchMispredicted_o), .branchRedirect_o(branchRedirect_o),
        .branchRobTag_o(branchRobTag_o),
        .branchLane_o(branchIssueLane),
        .csrValid_o(csrValid_o), .csrOp_o(csrOp_o), .csrAddr_o(csrAddr_o),
        .csrWriteData_o(csrWriteData_o), .lsuExecuteValid_o(lsuExecuteValid),
        .lsuLoadReadValid_o(lsuLoadReadValid), .lsuIsStore_o(lsuIsStore),
        .lsuAddress_o(lsuAddress),
        .lsuStoreDataValid_o(lsuStoreDataValid),
        .lsuStoreData_o(lsuStoreData),
        .lsuMemoryAccess_o(lsuMemoryAccess), .lsuTag_o(lsuTag)
        ,.lsuLoadRequestId_o(lsuLoadRequestId)
    );

    LoadStoreQueue #(
        .MMIO_BASE_ADDR(MMIO_BASE_ADDR),
        .MMIO_LAST_ADDR(MMIO_LAST_ADDR)
    ) loadStoreQueue (
        .clk(clk),
        .rst(rst),
        .flush_i(flush_i),
        .recoverValid_i(recoveryValid),
        .recoverYoungerMask_i(recoveryYoungerMask),
        .allocValid_i(lsqAllocValid),
        .allocEntry_i(renameLsqEntry),
        .allocReady_o(lsqAllocReady),
        .allocTag_o(lsqAllocTag),
        .addressValid_i(lsqAddressValid),
        .addressTag_i(lsqAddressTag),
        .address_i(lsqAddress),
        .storeDataValid_i(lsqStoreDataValid),
        .storeDataTag_i(lsqStoreDataTag),
        .storeData_i(lsqStoreData),
        .dataWakeupValid_i(prfWritebackValid),
        .dataWakeupPhys_i(prfWritebackPhys),
        .dataWakeupValue_i(prfWritebackData),
        .issueValid_i(lsuCandidateValid),
        .issueTag_i(lsuTag),
        .issueAddress_i(lsuAddress),
        .issueMemCtr_i(lsuMemoryAccess),
        .issueReady_o(lsqIssueReady),
        .issueForwardValid_o(lsqForwardValid),
        .issueForwardData_o(lsqForwardData),
        .headEntry_o(lsqHeadEntry),
        .headTag_o(lsqHeadTag),
        .retireCount_i(lsqRetireCount),
        .empty_o(lsqEmpty),
        .full_o(lsqFull),
        .count_o(lsqCount_o)
    );

    // MMIO Stores remain precise and bypass the Store Buffer. Cached Loads
    // normally win the D$ port; a full Store Buffer forces one oldest entry to
    // drain so a stream of Loads cannot deadlock retirement.
    assign mmioStoreReady = storeBufferEmpty && memoryRequestReady_i;
    assign mmioStoreRequest = commitStoreValid && commitStoreMmio &&
                              storeBufferEmpty;
    assign forceStoreBufferDrain = storeBufferFull && storeBufferDrainValid;
    assign loadCacheRequestReady = memoryRequestReady_i &&
        !(commitStoreValid && commitStoreMmio) && !forceStoreBufferDrain;
    assign selectStoreBufferDrain = storeBufferDrainValid &&
        !mmioStoreRequest &&
        ((commitStoreValid && commitStoreMmio) || forceStoreBufferDrain ||
         !lsuLoadReadValid);
    assign selectLoadRequest = lsuLoadReadValid && !mmioStoreRequest &&
        !(commitStoreValid && commitStoreMmio) && !forceStoreBufferDrain;
    assign storeBufferDrainReady = selectStoreBufferDrain &&
                                   memoryRequestReady_i;

    assign memoryValid_o = mmioStoreRequest ||
                           selectStoreBufferDrain || selectLoadRequest;
    assign memoryWrite_o = mmioStoreRequest ||
                           selectStoreBufferDrain;
    assign memoryRequestId_o = selectLoadRequest ? lsuLoadRequestId : '0;
    assign memoryAddress_o = mmioStoreRequest ?
        commitStoreAddress : (selectStoreBufferDrain ?
                              storeBufferDrainAddress : lsuAddress);
    assign memoryWriteData_o = mmioStoreRequest ?
        commitStoreData : storeBufferDrainData;
    assign memoryAccess_o = mmioStoreRequest ?
        commitStoreAccess : (selectStoreBufferDrain ?
                             storeBufferDrainAccess : lsuMemoryAccess);

    assign retireCount_o = {1'b0, robRetireValid[0]} +
                           {1'b0, robRetireValid[1]};
    for (genvar commitLane = 0; commitLane < 2; commitLane = commitLane + 1) begin
        assign commitValid_o[commitLane] = robRetireValid[commitLane];
        assign commitPc_o[commitLane] = robCommitEntry[commitLane].pc;
        assign commitArchRd_o[commitLane] = robCommitEntry[commitLane].writesRd ?
                                             robCommitEntry[commitLane].archRd : '0;
        assign commitData_o[commitLane] = robCommitEntry[commitLane].writesRd ?
                                          prfReadData[commitLane+10] : '0;
    end

endmodule
