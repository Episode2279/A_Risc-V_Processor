module OoOBackend
    import TypesPkg::*;
(
    input  logic clk,
    input  logic rst,
    input  logic flush_i,

    IdExeBusIf.sink decode0_bus,
    IdExeBusIf.sink decode1_bus,
    output logic [1:0] dispatchAccept_o,
    output logic dispatchStall_o,

    input  word_t memoryReadData_i,
    output logic memoryValid_o,
    output logic memoryWrite_o,
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
    output logic [$clog2(ISSUE_QUEUE_ENTRY_NUM+LSQ_ENTRY_NUM+1)-1:0] issueCount_o,
    output logic [$clog2(LSQ_ENTRY_NUM+1)-1:0] lsqCount_o,
    output logic [63:0] perfDualIssueCycles_o, perfSingleIssueCycles_o, perfIqNoReadyCycles_o,
    output logic [63:0] perfPort0LsuBlockedCycles_o, perfPort0BranchBlockedCycles_o,
    output logic [63:0] perfRobFullCycles_o, perfIqFullCycles_o, perfLsqFullCycles_o, perfPrfEmptyCycles_o,
    output logic [63:0] perfBranchCount_o, perfBranchMispredictCount_o, perfJumpSerializationCycles_o
    ,output logic [63:0] perfConditionalCount_o,perfConditionalMispredictCount_o,
    output logic [63:0] perfDirectionMispredictCount_o,perfTargetMispredictCount_o,perfBtbMissCount_o,
    output logic [63:0] perfJalMispredictCount_o,perfJalrMispredictCount_o,perfRasMissCount_o
);

    localparam int PRF_READ_PORTS = 10;

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
    rob_entry_t robCommitEntry [2];
    logic robEmpty;
    logic robFull;

    renamed_uop_t issueDispatchUop [2];
    logic [1:0] issueDispatchReady;
    logic [1:0] issueValid;
    renamed_uop_t issueUop [2];
    logic [1:0] issueReady;
    logic issueEmpty;
    logic issueFull;
    logic [$clog2(ISSUE_QUEUE_ENTRY_NUM+LSQ_ENTRY_NUM+1)-1:0] issueCount;

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
    logic [PRF_READ_PORTS-1:0] prfReadReady;
    logic [1:0] prfWritebackValid;
    phys_reg_addr_t prfWritebackPhys [2];
    word_t prfWritebackData [2];

    logic lsuExecuteValid;
    logic lsuLoadReadValid;
    logic lsuIsStore;
    word_t lsuAddress;
    word_t lsuStoreData;
    mem_access_t lsuMemoryAccess;
    lsq_tag_t lsuTag;

    logic commitStoreValid;
    word_t commitStoreAddress;
    word_t commitStoreData;
    mem_access_t commitStoreAccess;
    integer prepLane;

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

        backendDrained = (robCount_o == '0) && issueEmpty && lsqEmpty;
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
        prfReadAddr[8] = robCommitEntry[0].newPhys;
        prfReadAddr[9] = robCommitEntry[1].newPhys;
        executeSourceA[0] = prfReadData[4];
        executeSourceB[0] = prfReadData[5];
        executeSourceA[1] = prfReadData[6];
        executeSourceB[1] = prfReadData[7];

        robAllocValid = dispatchAccept_o & laneValid;
        branchCheckpointValid_o[0] = robAllocValid[0] && (decode0_bus.branchCtr != BR_NONE);
        branchCheckpointValid_o[1] = robAllocValid[1] && (decode1_bus.branchCtr != BR_NONE);
        branchCheckpointTag_o[0] = robAllocTag[0];
        branchCheckpointTag_o[1] = robAllocTag[1];
        branchCheckpointHistory_o[0] = decode0_bus.historySnapshot;
        branchCheckpointHistory_o[1] = decode1_bus.historySnapshot;
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
        lsqStoreDataValid[0] = lsuExecuteValid && lsuIsStore;

        issueCount_o = issueCount;
        recoveryValid = branchMispredicted_o;
        recoveryTag = branchRobTag_o;
        integerOrderingReady = 1'b1;
    end

    BackendCommitStage commitStage (
        .recoveryValid_i(recoveryValid),
        .robCommitValid_i(robCommitValid), .robCommitEntry_i(robCommitEntry),
        .lsqHeadEntry_i(lsqHeadEntry), .lsqHeadTag_i(lsqHeadTag),
        .robCommitReady_o(robCommitReady), .robRetireValid_o(robRetireValid),
        .lsqRetireCount_o(lsqRetireCount), .storeValid_o(commitStoreValid),
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
        .commitValid_o(robCommitValid),
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
        .empty_o(issueEmpty),
        .full_o(issueFull),
        .count_o(issueCount)
    );

    BackendPerformanceCounters performanceCounters (
        .clk(clk), .rst(rst), .issueValid_i(issueValid), .issueReady_i(issueReady),
        .issueUop_i(issueUop), .issueCount_i(issueCount), .robFull_i(robFull),
        .iqFull_i(issueFull), .lsqFull_i(lsqFull), .prfEmpty_i(freePhysCount == 0),
        .branchResolved_i(branchResolved_o), .branchMispredicted_i(branchMispredicted_o),
        .branchConditional_i(branchIsConditional_o),
        .branchDirectionMispredict_i(branchIsConditional_o && (issueUop[branchIssueLane].predictedTaken != branchTaken_o)),
        .branchTargetMispredict_i(branchTaken_o && issueUop[branchIssueLane].predictedTaken &&
            (issueUop[branchIssueLane].predictedTarget != branchTarget_o)),
        .branchBtbMiss_i(branchTaken_o && !issueUop[branchIssueLane].predictedBtbHit &&
            !issueUop[branchIssueLane].predictedRasUsed && (issueUop[branchIssueLane].branchCtr != BR_JAL)),
        .branchJal_i(issueUop[branchIssueLane].branchCtr == BR_JAL), .branchJalr_i(issueUop[branchIssueLane].branchCtr == BR_JALR),
        .branchRasMiss_i(issueUop[branchIssueLane].isReturn && (!issueUop[branchIssueLane].predictedRasUsed || branchMispredicted_o)),
        .jumpSerializing_i(jumpSerializing), .dualIssueCycles_o(perfDualIssueCycles_o),
        .singleIssueCycles_o(perfSingleIssueCycles_o), .iqNoReadyCycles_o(perfIqNoReadyCycles_o),
        .port0LsuBlockedCycles_o(perfPort0LsuBlockedCycles_o),
        .port0BranchBlockedCycles_o(perfPort0BranchBlockedCycles_o), .robFullCycles_o(perfRobFullCycles_o),
        .iqFullCycles_o(perfIqFullCycles_o), .lsqFullCycles_o(perfLsqFullCycles_o),
        .prfEmptyCycles_o(perfPrfEmptyCycles_o), .branchCount_o(perfBranchCount_o),
        .branchMispredictCount_o(perfBranchMispredictCount_o),
        .jumpSerializationCycles_o(perfJumpSerializationCycles_o)
        ,.conditionalCount_o(perfConditionalCount_o),.conditionalMispredictCount_o(perfConditionalMispredictCount_o),
        .directionMispredictCount_o(perfDirectionMispredictCount_o),.targetMispredictCount_o(perfTargetMispredictCount_o),
        .btbMissCount_o(perfBtbMissCount_o),.jalMispredictCount_o(perfJalMispredictCount_o),
        .jalrMispredictCount_o(perfJalrMispredictCount_o),.rasMissCount_o(perfRasMissCount_o)
    );

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
        .csrReadData_i(csrReadData_i), .integerOrderingReady_i(integerOrderingReady),
        .lsqIssueReady_i(lsqIssueReady), .lsqForwardValid_i(lsqForwardValid),
        .lsqForwardData_i(lsqForwardData), .memoryPortReady_i(!commitStoreValid),
        .memoryReadData_i(memoryReadData_i), .issueReady_o(issueReady),
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
        .lsuAddress_o(lsuAddress), .lsuStoreData_o(lsuStoreData),
        .lsuMemoryAccess_o(lsuMemoryAccess), .lsuTag_o(lsuTag)
    );

    LoadStoreQueue loadStoreQueue (
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
        .issueValid_i(issueValid[0] && (issueUop[0].fuClass == FU_MEMORY)),
        .issueTag_i(issueUop[0].lsqTag),
        .issueAddress_i(lsuAddress),
        .issueMemCtr_i(issueUop[0].memCtr),
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

    // The only externally visible Store request is generated by an accepted
    // ROB retirement. Loads use the port only when they are not forwarded.
    assign memoryValid_o = commitStoreValid || lsuLoadReadValid;
    assign memoryWrite_o = commitStoreValid;
    assign memoryAddress_o = commitStoreValid ? commitStoreAddress : lsuAddress;
    assign memoryWriteData_o = commitStoreValid ? commitStoreData : lsuStoreData;
    assign memoryAccess_o = commitStoreValid ? commitStoreAccess : lsuMemoryAccess;

    assign retireCount_o = {1'b0, robRetireValid[0]} +
                           {1'b0, robRetireValid[1]};
    for (genvar commitLane = 0; commitLane < 2; commitLane = commitLane + 1) begin
        assign commitValid_o[commitLane] = robRetireValid[commitLane];
        assign commitPc_o[commitLane] = robCommitEntry[commitLane].pc;
        assign commitArchRd_o[commitLane] = robCommitEntry[commitLane].writesRd ?
                                             robCommitEntry[commitLane].archRd : '0;
        assign commitData_o[commitLane] = robCommitEntry[commitLane].writesRd ?
                                          prfReadData[commitLane+8] : '0;
    end

endmodule
