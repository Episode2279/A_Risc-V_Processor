module TagePredictor
    import TypesPkg::*;
#(
    parameter int TABLE_ENTRIES = TAGE_TABLE_ENTRIES,
    parameter int INDEX_WIDTH = $clog2(TABLE_ENTRIES),
    parameter bit SC_ENABLE = 1'b1,
    parameter int SC_LOW_CONFIDENCE_THRESHOLD = 23,
    parameter int SC_WEAK_BASE_WEIGHT = 20,
    parameter int SC_STRONG_BASE_WEIGHT = 62
)
(
    input  logic clk,
    input  logic rst,
    input  logic flush_i,

    // Raw next-request context.  The tagged tables register this lookup while
    // fallbackPrediction_i describes the current registered BPU response.
    input  instruction_addr_t queryPc_i,
    input  logic fallbackPrediction_i,
    output tage_meta_t queryMeta_o,

    input  instruction_addr_t queryPc1_i,
    input  logic fallbackPrediction1_i,
    input  logic query0Conditional_i,
    input  logic query0Control_i,
    input  logic query0PathTaken_i,
    output tage_meta_t queryMeta1_o,

    // Direction history advances only for conditionals.  Path history has a
    // separate accepted-control event so JAL/JALR also contribute.
    input  logic speculateValid_i,
    input  logic speculateTaken_i,
    input  logic speculateValid1_i,
    input  logic speculateTaken1_i,
    input  logic speculateControlValid_i,
    input  logic speculateControlValid1_i,

    input  logic updateValid_i,
    input  logic updateIsConditional_i,
    input  instruction_addr_t updatePc_i,
    input  logic updateTaken_i,
    input  tage_meta_t updateMeta_i,
    output logic updateReady_o,

    input  logic recoverValid_i,
    input  instruction_addr_t recoverPc_i,
    input  logic recoverIsConditional_i,
    input  logic recoverTaken_i,
    input  rob_tag_t recoverRobTag_i,
    input  logic [1:0] checkpointAllocValid_i,
    input  rob_tag_t checkpointAllocTag_i [2],
    input  tage_history_t checkpointAllocHistory_i [2],
    input  tage_path_history_t checkpointAllocPathHistory_i [2]
);

    tage_history_t globalHistory;
    tage_history_t committedHistory;
    tage_history_t committedHistoryNext;
    tage_history_t speculativeHistoryNext;
    tage_history_t requestHistory;
    tage_history_t queryHistory1;
    tage_history_t predictionHistory;
    tage_history_t predictionHistory1;
    tage_history_t restoreHistory;
    tage_history_t robHistoryCheckpoint [ROB_ENTRY_NUM];

    tage_path_history_t globalPathHistory;
    tage_path_history_t committedPathHistory;
    tage_path_history_t committedPathHistoryNext;
    tage_path_history_t speculativePathHistoryNext;
    tage_path_history_t requestPathHistory;
    tage_path_history_t queryPathHistory1;
    tage_path_history_t predictionPathHistory;
    tage_path_history_t predictionPathHistory1;
    tage_path_history_t restorePathHistory;
    tage_path_history_t robPathHistoryCheckpoint [ROB_ENTRY_NUM];
    logic restoreHistoryValid;
    instruction_addr_t predictionPc;
    instruction_addr_t predictionPc1;

    logic tableHit [TAGE_TABLE_NUM];
    logic tablePrediction [TAGE_TABLE_NUM];
    logic [2:0] tableCounter [TAGE_TABLE_NUM];
    logic [1:0] tableUseful [TAGE_TABLE_NUM];
    tage_generation_t tableGeneration [TAGE_TABLE_NUM];
    logic tableHit1 [TAGE_TABLE_NUM];
    logic tablePrediction1 [TAGE_TABLE_NUM];
    logic [2:0] tableCounter1 [TAGE_TABLE_NUM];
    logic [1:0] tableUseful1 [TAGE_TABLE_NUM];
    tage_generation_t tableGeneration1 [TAGE_TABLE_NUM];
    logic tableUpdateMatch [TAGE_TABLE_NUM];
    logic tableReplaceable [TAGE_TABLE_NUM];
    logic [1:0] tableUpdateUseful [TAGE_TABLE_NUM];
    localparam int SC_GEHL_TABLE_NUM = 4;
    localparam int SC_FOLD_WIDTH = 7;
    logic [INDEX_WIDTH-1:0] tageIndexFold [TAGE_TABLE_NUM];
    logic [INDEX_WIDTH-1:0] tageIndexFold1 [TAGE_TABLE_NUM];
    logic [SC_FOLD_WIDTH-1:0] scQueryFold [SC_GEHL_TABLE_NUM];
    logic [SC_FOLD_WIDTH-1:0] scQueryFold1 [SC_GEHL_TABLE_NUM];

    logic [TAGE_TABLE_NUM-1:0] providerUpdate;
    logic [TAGE_TABLE_NUM-1:0] providerUsefulIncrement;
    logic [TAGE_TABLE_NUM-1:0] providerUsefulDecrement;
    logic [TAGE_TABLE_NUM-1:0] tableAllocate;
    logic [TAGE_TABLE_NUM-1:0] replacementUsefulDecrement;
    logic [TAGE_TABLE_NUM-1:0] eligibleAllocation;
    logic [TAGE_TABLE_NUM-1:0] freeAllocation;
    logic [TAGE_TABLE_NUM-1:0] firstAllocation;
    logic [TAGE_TABLE_NUM-1:0] remainingFreeAllocation;
    logic [TAGE_TABLE_NUM-1:0] secondAllocation;
    logic [TAGE_TABLE_NUM-1:0] protectedAllocation;
    logic [TAGE_TABLE_NUM-1:0] minimumUsefulAllocation;

    logic [2:0] selectedCounter;
    logic [1:0] selectedUseful;
    logic [2:0] selectedCounter1;
    logic [1:0] selectedUseful1;
    tage_meta_t tageBaseMeta;
    tage_meta_t tageBaseMeta1;
    logic scResponseValid;
    logic scPrediction;
    logic scPrediction1;
    logic scLowConfidence;
    logic scLowConfidence1;
    // Short (T0/T1), medium (T2/T3), and long (T4) providers each have
    // independent PC classes so unrelated new entries do not train one global
    // alternate-on-new decision.
    logic [3:0] useAlternateOnNew [6];
    logic [1:0] allocationPressure [3];
    logic [7:0] allocationLfsr;
    logic [1:0] updateHistoryGroup;
    logic [1:0] minimumProtectedUseful;
    logic allocationRequest;
    logic allocationAttempt;
    logic allocationSucceeded;
    logic noFreeAllocation;
    logic [7:0] ageCommitCounter;
    logic [INDEX_WIDTH-1:0] ageRow;
    logic ageValid;
    logic directionMispredict;
    tage_update_t queuedUpdateInput;
    tage_update_t queuedUpdate;
    logic updateAccepted;
    logic updateQueueEnqueue;
    logic updateQueueReady;
    logic updateQueueValid;
    logic [2:0] updateQueueCount;
    logic updateQueueFull;
    logic trainingValid;
    logic trainingIsConditional;
    instruction_addr_t trainingPc;
    logic trainingTaken;
    tage_meta_t trainingMeta;
    integer queryTableIndex;
    integer queryTableIndex1;
    integer updateTableIndex;
    integer pressureTableIndex;
    integer checkpointIndex;
    integer alternateGroupIndex;

    localparam logic [7:0] ALLOCATION_LFSR_RESET = 8'ha5;
    localparam logic [1:0] ALLOCATION_PRESSURE_THRESHOLD = 2'b11;
    localparam logic [2:0] TAGE_TABLE_COUNT = 3'(TAGE_TABLE_NUM);

    initial begin
        if ((SC_GEHL_TABLE_NUM * SC_FOLD_WIDTH) !=
            BPU_SC_FOLD_STORAGE_BITS)
            $fatal(1, "SC folded-history state disagrees with BPU budget");
        if (BPU_TOTAL_STORAGE_BITS > BPU_CBP_STORAGE_LIMIT_BITS)
            $fatal(1, "BPU logical state exceeds the CBP 4 KiB budget");
    end

    function automatic logic [1:0] providerHistoryGroup(
        input tage_provider_t provider
    );
        begin
            if (provider <= tage_provider_t'(1))
                providerHistoryGroup = 2'd0;
            else if (provider <= tage_provider_t'(3))
                providerHistoryGroup = 2'd1;
            else
                providerHistoryGroup = 2'd2;
        end
    endfunction

    function automatic logic [2:0] alternateGroup(
        input instruction_addr_t pc,
        input tage_provider_t provider
    );
        logic pcClass;
        logic [1:0] historyGroup;
        begin
            pcClass = pc[4] ^ pc[8];
            historyGroup = providerHistoryGroup(provider);
            alternateGroup = {historyGroup, 1'b0} +
                             {{2{1'b0}}, pcClass};
        end
    endfunction

    function automatic logic [2:0] normalizeAllocationStart(
        input logic [2:0] rawStart
    );
        begin
            // Avoid a divider in the retirement path. Values 5..7 wrap to
            // 0..2; the small bias is acceptable for this five-table policy,
            // and the LFSR changes the rotating start on every attempt.
            if (rawStart >= TAGE_TABLE_COUNT)
                normalizeAllocationStart = rawStart - TAGE_TABLE_COUNT;
            else
                normalizeAllocationStart = rawStart;
        end
    endfunction

    function automatic logic [TAGE_TABLE_NUM-1:0] pickAllocation(
        input logic [TAGE_TABLE_NUM-1:0] candidateMask,
        input logic [2:0] startIndex
    );
        logic found;
        integer offset;
        integer candidateIndex;
        begin
            pickAllocation = '0;
            found = 1'b0;
            for (offset = 0; offset < TAGE_TABLE_NUM;
                 offset = offset + 1) begin
                candidateIndex = int'(startIndex) + offset;
                if (candidateIndex >= TAGE_TABLE_NUM)
                    candidateIndex = candidateIndex - TAGE_TABLE_NUM;
                if (!found && candidateMask[candidateIndex]) begin
                    pickAllocation[candidateIndex] = 1'b1;
                    found = 1'b1;
                end
            end
        end
    endfunction

    function automatic tage_path_history_t advancePathHistory(
        input tage_path_history_t history,
        input instruction_addr_t branchPc,
        input logic pathTaken
    );
        logic pathBit;
        begin
            // One hashed path bit preserves the most recent 16 control-flow
            // events.  Direction is included because a BTB miss may make the
            // speculative fetch path differ from the raw TAGE direction.
            pathBit = branchPc[2] ^ branchPc[5] ^ branchPc[9] ^
                      branchPc[13] ^ pathTaken;
            advancePathHistory = {
                history[TAGE_PATH_HISTORY_WIDTH-2:0], pathBit};
        end
    endfunction

    always_comb begin
        queuedUpdateInput = '0;
        queuedUpdateInput.isConditional = updateIsConditional_i;
        queuedUpdateInput.pc = updatePc_i;
        queuedUpdateInput.taken = updateTaken_i;
        queuedUpdateInput.meta = updateMeta_i;
    end

    // Ready must depend only on queue state.  Depending on the current
    // branch's decoded type would feed ROB-retire information back into its
    // own ready path and create a combinational loop.
    assign updateReady_o = updateQueueReady;
    assign updateAccepted = updateValid_i && updateReady_o;
    assign updateQueueEnqueue = updateValid_i && updateIsConditional_i;
    assign trainingValid = updateQueueValid;
    assign trainingIsConditional = queuedUpdate.isConditional;
    assign trainingPc = queuedUpdate.pc;
    assign trainingTaken = queuedUpdate.taken;
    assign trainingMeta = queuedUpdate.meta;

    TageUpdateQueue #(.DEPTH(4)) updateQueue (
        .clk(clk), .rst(rst),
        .enqValid_i(updateQueueEnqueue),
        .enqReady_o(updateQueueReady),
        .enqData_i(queuedUpdateInput),
        .deqValid_o(updateQueueValid),
        .deqReady_i(1'b1),
        .deqData_o(queuedUpdate),
        .count_o(updateQueueCount),
        .full_o(updateQueueFull)
    );

    assign ageValid = trainingValid && trainingIsConditional &&
                      (ageCommitCounter == 8'hff);
    assign directionMispredict = trainingValid && trainingIsConditional &&
        (trainingMeta.tagePrediction != trainingTaken);

    // Construct all common next states once so normal speculation, recovery,
    // and a same-cycle commit+trap use identical history semantics.
    always_comb begin
        speculativeHistoryNext = globalHistory;
        if (speculateValid_i)
            speculativeHistoryNext = {
                speculativeHistoryNext[TAGE_HISTORY_WIDTH-2:0],
                speculateTaken_i};
        if (speculateValid1_i)
            speculativeHistoryNext = {
                speculativeHistoryNext[TAGE_HISTORY_WIDTH-2:0],
                speculateTaken1_i};

        speculativePathHistoryNext = globalPathHistory;
        if (speculateControlValid_i)
            speculativePathHistoryNext = advancePathHistory(
                speculativePathHistoryNext, predictionPc,
                speculateTaken_i);
        if (speculateControlValid1_i)
            speculativePathHistoryNext = advancePathHistory(
                speculativePathHistoryNext, predictionPc1,
                speculateTaken1_i);

        committedHistoryNext = committedHistory;
        if (updateAccepted && updateIsConditional_i)
            committedHistoryNext = {
                committedHistory[TAGE_HISTORY_WIDTH-2:0], updateTaken_i};

        committedPathHistoryNext = committedPathHistory;
        if (updateAccepted)
            committedPathHistoryNext = advancePathHistory(
                committedPathHistory, updatePc_i, updateTaken_i);

        restoreHistoryValid = flush_i || recoverValid_i;
        restoreHistory = committedHistoryNext;
        restorePathHistory = committedPathHistoryNext;
        if (!flush_i && recoverValid_i) begin
            restoreHistory = robHistoryCheckpoint[recoverRobTag_i];
            if (recoverIsConditional_i)
                restoreHistory = {
                    robHistoryCheckpoint[recoverRobTag_i]
                        [TAGE_HISTORY_WIDTH-2:0],
                    recoverTaken_i};
            // Every resolved control-flow instruction contributes to PHIST,
            // including target-only JAL/JALR mispredictions.
            restorePathHistory = advancePathHistory(
                robPathHistoryCheckpoint[recoverRobTag_i],
                recoverPc_i, recoverTaken_i);
        end

        // The synchronous table request launched at this edge must already use
        // the state that will become architecturally visible after the edge.
        // Redirect recovery wins over normal accepted-response speculation.
        requestHistory = restoreHistoryValid ?
            restoreHistory : speculativeHistoryNext;
        requestPathHistory = restoreHistoryValid ?
            restorePathHistory : speculativePathHistoryNext;

        // Slot 1 is useful only on slot 0's fall-through path.  Hashing it with
        // a fixed NT outcome is therefore exact for every consumed slot-1
        // prediction and removes a synchronous slot0-to-slot1 dependency.
        queryHistory1 = requestHistory;
        if (query0Conditional_i)
            queryHistory1 = {
                requestHistory[TAGE_HISTORY_WIDTH-2:0], 1'b0};

        queryPathHistory1 = requestPathHistory;
        if (query0Control_i)
            queryPathHistory1 = advancePathHistory(
                requestPathHistory, queryPc_i, 1'b0);
    end

    // Scan from the shortest to the longest table. Every later hit replaces
    // the provider and demotes the prior provider to alternate.
    always_comb begin
        tageBaseMeta = '0;
        tageBaseMeta.history = predictionHistory;
        tageBaseMeta.pathHistory = predictionPathHistory;
        tageBaseMeta.alternatePrediction = fallbackPrediction_i;
        tageBaseMeta.tagePrediction = fallbackPrediction_i;
        tageBaseMeta.finalPrediction = fallbackPrediction_i;
        selectedCounter = '0;
        selectedUseful = '0;
        for (queryTableIndex = 0; queryTableIndex < TAGE_TABLE_NUM;
             queryTableIndex = queryTableIndex + 1) begin
            if (tableHit[queryTableIndex]) begin
                if (tageBaseMeta.providerValid)
                    tageBaseMeta.alternatePrediction =
                        tageBaseMeta.providerPrediction;
                tageBaseMeta.providerValid = 1'b1;
                tageBaseMeta.provider = tage_provider_t'(queryTableIndex);
                tageBaseMeta.providerGeneration =
                    tableGeneration[queryTableIndex];
                tageBaseMeta.providerPrediction =
                    tablePrediction[queryTableIndex];
                selectedCounter = tableCounter[queryTableIndex];
                selectedUseful = tableUseful[queryTableIndex];
            end
        end
        if (tageBaseMeta.providerValid) begin
            tageBaseMeta.providerWeak = (selectedUseful == 2'b00) &&
                ((selectedCounter == 3'b011) ||
                 (selectedCounter == 3'b100));
            tageBaseMeta.tagePrediction =
                (tageBaseMeta.providerWeak &&
                  useAlternateOnNew[
                      alternateGroup(predictionPc,
                                     tageBaseMeta.provider)][3]) ?
                tageBaseMeta.alternatePrediction :
                tageBaseMeta.providerPrediction;
        end
        tageBaseMeta.finalPrediction = tageBaseMeta.tagePrediction;
    end

    always_comb begin
        tageBaseMeta1 = '0;
        tageBaseMeta1.history = predictionHistory1;
        tageBaseMeta1.pathHistory = predictionPathHistory1;
        tageBaseMeta1.alternatePrediction = fallbackPrediction1_i;
        tageBaseMeta1.tagePrediction = fallbackPrediction1_i;
        tageBaseMeta1.finalPrediction = fallbackPrediction1_i;
        selectedCounter1 = '0;
        selectedUseful1 = '0;
        for (queryTableIndex1 = 0; queryTableIndex1 < TAGE_TABLE_NUM;
             queryTableIndex1 = queryTableIndex1 + 1) begin
            if (tableHit1[queryTableIndex1]) begin
                if (tageBaseMeta1.providerValid)
                    tageBaseMeta1.alternatePrediction =
                        tageBaseMeta1.providerPrediction;
                tageBaseMeta1.providerValid = 1'b1;
                tageBaseMeta1.provider = tage_provider_t'(queryTableIndex1);
                tageBaseMeta1.providerGeneration =
                    tableGeneration1[queryTableIndex1];
                tageBaseMeta1.providerPrediction =
                    tablePrediction1[queryTableIndex1];
                selectedCounter1 = tableCounter1[queryTableIndex1];
                selectedUseful1 = tableUseful1[queryTableIndex1];
            end
        end
        if (tageBaseMeta1.providerValid) begin
            tageBaseMeta1.providerWeak = (selectedUseful1 == 2'b00) &&
                ((selectedCounter1 == 3'b011) ||
                 (selectedCounter1 == 3'b100));
            tageBaseMeta1.tagePrediction =
                (tageBaseMeta1.providerWeak &&
                  useAlternateOnNew[
                      alternateGroup(predictionPc1,
                                     tageBaseMeta1.provider)][3]) ?
                tageBaseMeta1.alternatePrediction :
                tageBaseMeta1.providerPrediction;
        end
        tageBaseMeta1.finalPrediction = tageBaseMeta1.tagePrediction;
    end

    always_comb begin
        queryMeta_o = tageBaseMeta;
        if (SC_ENABLE && scResponseValid) begin
            queryMeta_o.finalPrediction = scPrediction;
            queryMeta_o.scLowConfidence = scLowConfidence;
        end
    end

    always_comb begin
        queryMeta1_o = tageBaseMeta1;
        if (SC_ENABLE && scResponseValid) begin
            queryMeta1_o.finalPrediction = scPrediction1;
            queryMeta1_o.scLowConfidence = scLowConfidence1;
        end
    end

    // A final direction miss allocates only when the Provider itself was
    // wrong (or absent). This suppresses pollution when alternate-on-new was
    // the sole source of the error. A reproducible LFSR rotates priority among
    // free longer-history candidates; one quarter of attempts may allocate a
    // second distinct table. If every candidate is protected, a per-history-
    // group pressure counter occasionally decrements one random minimum-u row.
    always_comb begin
        providerUpdate = '0;
        providerUsefulIncrement = '0;
        providerUsefulDecrement = '0;
        tableAllocate = '0;
        replacementUsefulDecrement = '0;
        eligibleAllocation = '0;
        freeAllocation = '0;
        firstAllocation = '0;
        remainingFreeAllocation = '0;
        secondAllocation = '0;
        protectedAllocation = '0;
        minimumUsefulAllocation = '0;
        minimumProtectedUseful = 2'b11;
        updateHistoryGroup = 2'd0;

        if (trainingValid && trainingIsConditional &&
            trainingMeta.providerValid) begin
            providerUpdate[trainingMeta.provider] = 1'b1;
            if (trainingMeta.providerPrediction !=
                trainingMeta.alternatePrediction) begin
                if (trainingMeta.providerPrediction == trainingTaken)
                    providerUsefulIncrement[trainingMeta.provider] = 1'b1;
                else
                    providerUsefulDecrement[trainingMeta.provider] = 1'b1;
            end
        end

        allocationRequest = directionMispredict &&
            (!trainingMeta.providerValid ||
             (trainingMeta.providerPrediction != trainingTaken));

        for (updateTableIndex = 0; updateTableIndex < TAGE_TABLE_NUM;
             updateTableIndex = updateTableIndex + 1) begin
            if (allocationRequest &&
                (!trainingMeta.providerValid ||
                 (updateTableIndex > trainingMeta.provider))) begin
                eligibleAllocation[updateTableIndex] = 1'b1;
                freeAllocation[updateTableIndex] =
                    tableReplaceable[updateTableIndex];
                protectedAllocation[updateTableIndex] =
                    !tableReplaceable[updateTableIndex];
            end
        end

        firstAllocation = pickAllocation(
            freeAllocation,
            normalizeAllocationStart(allocationLfsr[2:0]));
        remainingFreeAllocation = freeAllocation & ~firstAllocation;
        if ((allocationLfsr[4:3] == 2'b00) &&
            (remainingFreeAllocation != '0))
            secondAllocation = pickAllocation(
                remainingFreeAllocation,
                normalizeAllocationStart(allocationLfsr[7:5]));
        tableAllocate = firstAllocation | secondAllocation;

        if (protectedAllocation != '0) begin
            for (pressureTableIndex = 0;
                 pressureTableIndex < TAGE_TABLE_NUM;
                 pressureTableIndex = pressureTableIndex + 1) begin
                if (protectedAllocation[pressureTableIndex] &&
                    (tableUpdateUseful[pressureTableIndex] <
                     minimumProtectedUseful))
                    minimumProtectedUseful =
                        tableUpdateUseful[pressureTableIndex];
            end
            for (pressureTableIndex = 0;
                 pressureTableIndex < TAGE_TABLE_NUM;
                 pressureTableIndex = pressureTableIndex + 1) begin
                if (protectedAllocation[pressureTableIndex] &&
                    (tableUpdateUseful[pressureTableIndex] ==
                     minimumProtectedUseful))
                    minimumUsefulAllocation[pressureTableIndex] = 1'b1;
            end
        end

        if (trainingMeta.providerValid)
            updateHistoryGroup = providerHistoryGroup(
                trainingMeta.provider);

        allocationAttempt = allocationRequest &&
                            (eligibleAllocation != '0);
        allocationSucceeded = tableAllocate != '0;
        noFreeAllocation = allocationAttempt &&
                           (freeAllocation == '0);
        if (noFreeAllocation &&
            (allocationPressure[updateHistoryGroup] ==
             ALLOCATION_PRESSURE_THRESHOLD))
            replacementUsefulDecrement = pickAllocation(
                minimumUsefulAllocation,
                normalizeAllocationStart(allocationLfsr[7:5]));
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            globalHistory <= '0;
            committedHistory <= '0;
            globalPathHistory <= '0;
            committedPathHistory <= '0;
            predictionPc <= RESET_VECTOR;
            predictionPc1 <= RESET_VECTOR + 32'd4;
            predictionHistory <= '0;
            predictionHistory1 <= '0;
            predictionPathHistory <= '0;
            predictionPathHistory1 <= '0;
            for (alternateGroupIndex = 0; alternateGroupIndex < 6;
                 alternateGroupIndex = alternateGroupIndex + 1)
                useAlternateOnNew[alternateGroupIndex] <= 4'b0111;
            for (alternateGroupIndex = 0; alternateGroupIndex < 3;
                 alternateGroupIndex = alternateGroupIndex + 1)
                allocationPressure[alternateGroupIndex] <= '0;
            allocationLfsr <= ALLOCATION_LFSR_RESET;
            ageCommitCounter <= '0;
            ageRow <= '0;
            for (checkpointIndex = 0; checkpointIndex < ROB_ENTRY_NUM;
                 checkpointIndex = checkpointIndex + 1) begin
                robHistoryCheckpoint[checkpointIndex] <= '0;
                robPathHistoryCheckpoint[checkpointIndex] <= '0;
            end
        end else begin
            committedHistory <= committedHistoryNext;
            committedPathHistory <= committedPathHistoryNext;

            // These snapshots describe the same request sampled by every
            // synchronous TageTable instance at this edge.
            predictionPc <= queryPc_i;
            predictionPc1 <= queryPc1_i;
            predictionHistory <= requestHistory;
            predictionHistory1 <= queryHistory1;
            predictionPathHistory <= requestPathHistory;
            predictionPathHistory1 <= queryPathHistory1;

            if (flush_i) begin
                globalHistory <= committedHistoryNext;
                globalPathHistory <= committedPathHistoryNext;
            end else if (recoverValid_i) begin
                globalHistory <= restoreHistory;
                globalPathHistory <= restorePathHistory;
            end else begin
                globalHistory <= speculativeHistoryNext;
                globalPathHistory <= speculativePathHistoryNext;
            end

            if (trainingValid && trainingIsConditional) begin
                if (ageCommitCounter == 8'hff) begin
                    ageCommitCounter <= '0;
                    ageRow <= ageRow +
                        {{(INDEX_WIDTH-1){1'b0}}, 1'b1};
                end else begin
                    ageCommitCounter <= ageCommitCounter + 8'd1;
                end

                if (trainingMeta.providerValid &&
                    trainingMeta.providerWeak &&
                    (trainingMeta.providerPrediction !=
                     trainingMeta.alternatePrediction)) begin
                    if ((trainingMeta.alternatePrediction == trainingTaken) &&
                        (useAlternateOnNew[
                            alternateGroup(trainingPc,
                                trainingMeta.provider)] != 4'hf))
                        useAlternateOnNew[
                            alternateGroup(trainingPc,
                                trainingMeta.provider)] <=
                            useAlternateOnNew[
                                alternateGroup(trainingPc,
                                    trainingMeta.provider)] + 4'd1;
                    else if ((trainingMeta.providerPrediction ==
                              trainingTaken) &&
                             (useAlternateOnNew[
                                alternateGroup(trainingPc,
                                    trainingMeta.provider)] != 4'h0))
                        useAlternateOnNew[
                            alternateGroup(trainingPc,
                                trainingMeta.provider)] <=
                            useAlternateOnNew[
                                alternateGroup(trainingPc,
                                    trainingMeta.provider)] - 4'd1;
                end
            end

            if (allocationAttempt) begin
                allocationLfsr <= {
                    allocationLfsr[6:0],
                    allocationLfsr[7] ^ allocationLfsr[5] ^
                    allocationLfsr[4] ^ allocationLfsr[3]};
                if (allocationSucceeded)
                    allocationPressure[updateHistoryGroup] <= '0;
                else if (noFreeAllocation) begin
                    if (allocationPressure[updateHistoryGroup] ==
                        ALLOCATION_PRESSURE_THRESHOLD)
                        allocationPressure[updateHistoryGroup] <= '0;
                    else
                        allocationPressure[updateHistoryGroup] <=
                            allocationPressure[updateHistoryGroup] + 2'd1;
                end
            end

            // A redirect invalidates any simultaneous younger dispatch.
            if (!flush_i && !recoverValid_i) begin
                for (checkpointIndex = 0; checkpointIndex < 2;
                     checkpointIndex = checkpointIndex + 1) begin
                    if (checkpointAllocValid_i[checkpointIndex]) begin
                        robHistoryCheckpoint[
                            checkpointAllocTag_i[checkpointIndex]] <=
                            checkpointAllocHistory_i[checkpointIndex];
                        robPathHistoryCheckpoint[
                            checkpointAllocTag_i[checkpointIndex]] <=
                            checkpointAllocPathHistory_i[checkpointIndex];
                    end
                end
            end
        end
    end

    // Dedicated SC folds use the empirically selected 3/7/15/31 histories.
    // They are incrementally maintained just like the TAGE folds, adding only
    // 4*7 bits of logical state and no extra prediction pipeline stage.
    generate
        for (genvar generatedScFold = 0;
             generatedScFold < SC_GEHL_TABLE_NUM;
             generatedScFold = generatedScFold + 1) begin : generateScFolds
            localparam int SC_HISTORY_LENGTH =
                (generatedScFold == 0) ? 3 :
                (generatedScFold == 1) ? 7 :
                (generatedScFold == 2) ? 15 : 31;

            TageFoldedHistory #(
                .HISTORY_LENGTH(SC_HISTORY_LENGTH),
                .FOLD_WIDTH(SC_FOLD_WIDTH)
            ) scHistoryFold (
                .clk(clk), .rst(rst), .globalHistory_i(globalHistory),
                .query0Conditional_i(query0Conditional_i),
                .query0Taken_i(query0PathTaken_i),
                .queryFold_o(scQueryFold[generatedScFold]),
                .queryFold1_o(scQueryFold1[generatedScFold]),
                .speculateValid_i(speculateValid_i),
                .speculateTaken_i(speculateTaken_i),
                .speculateValid1_i(speculateValid1_i),
                .speculateTaken1_i(speculateTaken1_i),
                .restoreValid_i(restoreHistoryValid),
                .restoreHistory_i(restoreHistory)
            );
        end
    endgenerate

    // The SC reads in parallel with the tagged tables and receives their raw
    // TAGE/UAN decision in the response cycle.  Retirement uses the history
    // saved in tage_meta_t, so only nonsquashed conditional branches train it.
    StatisticalCorrector #(
        .HISTORY_FOLD_NUM(SC_GEHL_TABLE_NUM),
        .HISTORY_FOLD_WIDTH(SC_FOLD_WIDTH),
        .LOW_CONFIDENCE_THRESHOLD(SC_LOW_CONFIDENCE_THRESHOLD),
        .WEAK_BASE_WEIGHT(SC_WEAK_BASE_WEIGHT),
        .STRONG_BASE_WEIGHT(SC_STRONG_BASE_WEIGHT)
    ) statisticalCorrector (
        .clk(clk), .rst(rst),
        .queryValid_i(SC_ENABLE),
        .queryPc_i(queryPc_i), .queryPc1_i(queryPc1_i),
        .queryHistoryFold_i(scQueryFold),
        .queryHistoryFold1_i(scQueryFold1),
        .queryPath_i(requestPathHistory),
        .queryPath1_i(queryPathHistory1),
        .basePrediction_i(tageBaseMeta.tagePrediction),
        .baseStrong_i(tageBaseMeta.providerValid &&
                      !tageBaseMeta.providerWeak),
        .basePrediction1_i(tageBaseMeta1.tagePrediction),
        .baseStrong1_i(tageBaseMeta1.providerValid &&
                       !tageBaseMeta1.providerWeak),
        .responseValid_o(scResponseValid),
        .predictTaken_o(scPrediction),
        .predictTaken1_o(scPrediction1),
        .lowConfidence_o(scLowConfidence),
        .lowConfidence1_o(scLowConfidence1),
        .score_o(), .score1_o(),
        .updateValid_i(SC_ENABLE && trainingValid &&
                       trainingIsConditional),
        .updatePc_i(trainingPc),
        .updateHistory_i(trainingMeta.history),
        .updatePath_i(trainingMeta.pathHistory),
        .updateTaken_i(trainingTaken),
        .updateFinalPrediction_i(trainingMeta.finalPrediction),
        .updateLowConfidence_i(trainingMeta.scLowConfidence)
    );

    generate
        for (genvar generatedTable = 0;
             generatedTable < TAGE_TABLE_NUM;
             generatedTable = generatedTable + 1) begin : generateTageTables
            localparam int TABLE_HISTORY_LENGTH =
                (generatedTable == 0) ? 4 :
                (generatedTable == 1) ? 8 :
                (generatedTable == 2) ? 16 :
                (generatedTable == 3) ? 32 : 64;
            localparam int TABLE_TAG_WIDTH =
                (generatedTable == 0) ? 7 :
                (generatedTable == 1) ? 8 :
                (generatedTable == 2) ? 9 :
                (generatedTable == 3) ? 10 : 11;

            logic [TABLE_TAG_WIDTH-1:0] queryTagFoldA;
            logic [TABLE_TAG_WIDTH-1:0] queryTagFoldA1;
            logic [TABLE_TAG_WIDTH-2:0] queryTagFoldB;
            logic [TABLE_TAG_WIDTH-2:0] queryTagFoldB1;
            logic [INDEX_WIDTH-1:0] queryIndex;
            logic [INDEX_WIDTH-1:0] queryIndex1;
            logic [INDEX_WIDTH-1:0] updateIndex;
            logic [TABLE_TAG_WIDTH-1:0] queryTag;
            logic [TABLE_TAG_WIDTH-1:0] queryTag1;
            logic [TABLE_TAG_WIDTH-1:0] updateTag;

            TageFoldedHistory #(
                .HISTORY_LENGTH(TABLE_HISTORY_LENGTH),
                .FOLD_WIDTH(INDEX_WIDTH)
            ) indexHistoryFold (
                .clk(clk), .rst(rst), .globalHistory_i(globalHistory),
                .query0Conditional_i(query0Conditional_i),
                .query0Taken_i(query0PathTaken_i),
                .queryFold_o(tageIndexFold[generatedTable]),
                .queryFold1_o(tageIndexFold1[generatedTable]),
                .speculateValid_i(speculateValid_i),
                .speculateTaken_i(speculateTaken_i),
                .speculateValid1_i(speculateValid1_i),
                .speculateTaken1_i(speculateTaken1_i),
                .restoreValid_i(restoreHistoryValid),
                .restoreHistory_i(restoreHistory)
            );

            TageFoldedHistory #(
                .HISTORY_LENGTH(TABLE_HISTORY_LENGTH),
                .FOLD_WIDTH(TABLE_TAG_WIDTH)
            ) tagHistoryFoldA (
                .clk(clk), .rst(rst), .globalHistory_i(globalHistory),
                .query0Conditional_i(query0Conditional_i),
                .query0Taken_i(query0PathTaken_i),
                .queryFold_o(queryTagFoldA),
                .queryFold1_o(queryTagFoldA1),
                .speculateValid_i(speculateValid_i),
                .speculateTaken_i(speculateTaken_i),
                .speculateValid1_i(speculateValid1_i),
                .speculateTaken1_i(speculateTaken1_i),
                .restoreValid_i(restoreHistoryValid),
                .restoreHistory_i(restoreHistory)
            );

            TageFoldedHistory #(
                .HISTORY_LENGTH(TABLE_HISTORY_LENGTH),
                .FOLD_WIDTH(TABLE_TAG_WIDTH-1)
            ) tagHistoryFoldB (
                .clk(clk), .rst(rst), .globalHistory_i(globalHistory),
                .query0Conditional_i(query0Conditional_i),
                .query0Taken_i(query0PathTaken_i),
                .queryFold_o(queryTagFoldB),
                .queryFold1_o(queryTagFoldB1),
                .speculateValid_i(speculateValid_i),
                .speculateTaken_i(speculateTaken_i),
                .speculateValid1_i(speculateValid1_i),
                .speculateTaken1_i(speculateTaken1_i),
                .restoreValid_i(restoreHistoryValid),
                .restoreHistory_i(restoreHistory)
            );

            TageHash #(
                .ENTRIES(TABLE_ENTRIES),
                .HISTORY_LENGTH(TABLE_HISTORY_LENGTH),
                .TAG_WIDTH(TABLE_TAG_WIDTH),
                .TABLE_ID(generatedTable)
            ) tableHash (
                .queryPc_i(queryPc_i),
                .queryIndexFold_i(tageIndexFold[generatedTable]),
                .queryTagFoldA_i(queryTagFoldA),
                .queryTagFoldB_i(queryTagFoldB),
                .queryPathHistory_i(requestPathHistory),
                .queryIndex_o(queryIndex), .queryTag_o(queryTag),
                .queryPc1_i(queryPc1_i),
                .queryIndexFold1_i(tageIndexFold1[generatedTable]),
                .queryTagFoldA1_i(queryTagFoldA1),
                .queryTagFoldB1_i(queryTagFoldB1),
                .queryPathHistory1_i(queryPathHistory1),
                .queryIndex1_o(queryIndex1), .queryTag1_o(queryTag1),
                .updatePc_i(trainingPc),
                .updateHistory_i(trainingMeta.history),
                .updatePathHistory_i(trainingMeta.pathHistory),
                .updateIndex_o(updateIndex), .updateTag_o(updateTag)
            );

            TageTable #(
                .ENTRIES(TABLE_ENTRIES),
                .TAG_WIDTH(TABLE_TAG_WIDTH)
            ) tageTableInstance (
                .clk(clk), .rst(rst),
                .queryIndex_i(queryIndex), .queryTag_i(queryTag),
                .queryBank_i(queryIndex[0]),
                .queryHit_o(tableHit[generatedTable]),
                .queryPrediction_o(tablePrediction[generatedTable]),
                .queryCounter_o(tableCounter[generatedTable]),
                .queryUseful_o(tableUseful[generatedTable]),
                .queryGeneration_o(tableGeneration[generatedTable]),
                .queryIndex1_i(queryIndex1), .queryTag1_i(queryTag1),
                .queryBank1_i(queryIndex1[0]),
                .queryHit1_o(tableHit1[generatedTable]),
                .queryPrediction1_o(tablePrediction1[generatedTable]),
                .queryCounter1_o(tableCounter1[generatedTable]),
                .queryUseful1_o(tableUseful1[generatedTable]),
                .queryGeneration1_o(tableGeneration1[generatedTable]),
                .updateIndex_i(updateIndex), .updateTag_i(updateTag),
                .updateBank_i(updateIndex[0]),
                .updateGeneration_i(trainingMeta.providerGeneration),
                .updateMatch_o(tableUpdateMatch[generatedTable]),
                .updateReplaceable_o(tableReplaceable[generatedTable]),
                .updateUseful_o(tableUpdateUseful[generatedTable]),
                .providerUpdateValid_i(providerUpdate[generatedTable]),
                .updateTaken_i(trainingTaken),
                .providerUsefulIncrement_i(
                    providerUsefulIncrement[generatedTable]),
                .providerUsefulDecrement_i(
                    providerUsefulDecrement[generatedTable]),
                .allocateValid_i(tableAllocate[generatedTable]),
                .replacementUsefulDecrement_i(
                    replacementUsefulDecrement[generatedTable]),
                .ageValid_i(ageValid), .ageIndex_i(ageRow)
            );
        end
    endgenerate

endmodule
