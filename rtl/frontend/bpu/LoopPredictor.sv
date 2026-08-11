// Counted-loop predictor with a small speculative action log.
//
// Persistent entries learn a loop's repeated direction and trip count only
// from retired conditional branches.  Fetch-time iteration movement is held in
// an action log instead of modifying the learned table.  A ROB checkpoint
// stores the action-tail value from loop_meta_t; recovery truncates the log and
// optionally appends the resolving branch's actual outcome.
module LoopPredictor
    import TypesPkg::*;
#(
    parameter int ENTRIES = LOOP_TABLE_ENTRIES,
    parameter int ACTION_DEPTH = LOOP_ACTION_DEPTH,
    parameter int INDEX_WIDTH = $clog2(ENTRIES),
    parameter int ACTION_WIDTH = $clog2(ACTION_DEPTH)
)
(
    input  logic clk,
    input  logic rst,
    input  logic flush_i,

    input  instruction_addr_t queryPc_i,
    input  instruction_addr_t queryPc1_i,
    input  logic response0Conditional_i,
    output loop_meta_t queryMeta_o,
    output loop_meta_t queryMeta1_o,

    input  logic speculateValid_i,
    input  logic speculateTaken_i,
    input  logic speculateValid1_i,
    input  logic speculateTaken1_i,

    input  logic updateValid_i,
    input  instruction_addr_t updatePc_i,
    input  instruction_addr_t updateTarget_i,
    input  logic updateTaken_i,
    input  loop_meta_t updateMeta_i,

    input  logic recoverValid_i,
    input  logic recoverIsConditional_i,
    input  logic recoverTaken_i,
    input  rob_tag_t recoverRobTag_i,
    input  logic [1:0] checkpointAllocValid_i,
    input  rob_tag_t checkpointAllocTag_i [2],
    input  loop_meta_t checkpointAllocMeta_i [2]
);

    localparam logic [LOOP_CONFIDENCE_WIDTH-1:0] CONFIDENCE_MAX = '1;
    localparam logic [LOOP_AGE_WIDTH-1:0] AGE_MAX = '1;

    logic validTable [ENTRIES];
    loop_tag_t tagTable [ENTRIES];
    loop_iter_t tripTable [ENTRIES];
    loop_iter_t committedIterTable [ENTRIES];
    logic [LOOP_CONFIDENCE_WIDTH-1:0] confidenceTable [ENTRIES];
    logic [LOOP_AGE_WIDTH-1:0] ageTable [ENTRIES];
    logic directionTable [ENTRIES];
    loop_generation_t generationTable [ENTRIES];

    loop_index_t responseIndex;
    loop_index_t responseIndex1;
    loop_tag_t responseRequestedTag;
    loop_tag_t responseRequestedTag1;
    logic responseValid;
    logic responseValid1;
    loop_tag_t responseTag;
    loop_tag_t responseTag1;
    loop_iter_t responseTrip;
    loop_iter_t responseTrip1;
    loop_iter_t responseCommittedIter;
    loop_iter_t responseCommittedIter1;
    logic [LOOP_CONFIDENCE_WIDTH-1:0] responseConfidence;
    logic [LOOP_CONFIDENCE_WIDTH-1:0] responseConfidence1;
    logic responseDirection;
    logic responseDirection1;
    loop_generation_t responseGeneration;
    loop_generation_t responseGeneration1;

    logic actionValid [ACTION_DEPTH];
    loop_index_t actionIndex [ACTION_DEPTH];
    loop_tag_t actionTag [ACTION_DEPTH];
    loop_generation_t actionGeneration [ACTION_DEPTH];
    loop_iter_t actionNextIter [ACTION_DEPTH];
    loop_action_ptr_t actionTail;
    loop_meta_t robCheckpoint [ROB_ENTRY_NUM];

    logic responseHit;
    logic responseHit1;
    logic actionSlot0Free;
    logic actionSlot1Free;
    logic reserveAction0;
    logic allocateAction0;
    logic allocateAction1;
    loop_action_ptr_t slot1Tail;
    loop_iter_t speculativeIter;
    loop_iter_t speculativeIter1;
    loop_index_t updateIndex;
    loop_tag_t updateTag;
    logic updateMatch;

    integer entryIndex;
    integer actionEntry;
    integer checkpointIndex;

    function automatic loop_index_t pcIndex(input instruction_addr_t pc);
        pcIndex = loop_index_t'(pc[INDEX_WIDTH+1:2]);
    endfunction

    function automatic loop_tag_t pcTag(input instruction_addr_t pc);
        logic [LOOP_TAG_WIDTH-1:0] lower;
        logic [LOOP_TAG_WIDTH-1:0] upper;
        begin
            lower = loop_tag_t'(pc >> (INDEX_WIDTH + 2));
            upper = loop_tag_t'(pc >> (INDEX_WIDTH + 2 +
                                        LOOP_TAG_WIDTH));
            pcTag = lower ^ upper;
        end
    endfunction

    function automatic loop_action_ptr_t nextAction(
        input loop_action_ptr_t value
    );
        nextAction = value + loop_action_ptr_t'(1);
    endfunction

    function automatic loop_iter_t advanceIteration(
        input loop_iter_t current,
        input logic outcome,
        input logic loopDirection
    );
        begin
            if (outcome != loopDirection)
                advanceIteration = '0;
            else if (current == {LOOP_ITER_WIDTH{1'b1}})
                advanceIteration = current;
            else
                advanceIteration = current + loop_iter_t'(1);
        end
    endfunction

    // Find the youngest speculative result for this entry by walking backward
    // from the tail. Holes left by retired actions are harmless.
    always_comb begin : scanActions
        integer offset;
        integer scanIndex;
        logic found;

        speculativeIter = responseCommittedIter;
        found = 1'b0;
        for (offset = 1; offset <= ACTION_DEPTH; offset = offset + 1) begin
            scanIndex = (integer'(actionTail) + ACTION_DEPTH - offset) %
                        ACTION_DEPTH;
            if (!found && actionValid[scanIndex] &&
                (actionIndex[scanIndex] == responseIndex) &&
                (actionTag[scanIndex] == responseTag) &&
                (actionGeneration[scanIndex] == responseGeneration)) begin
                speculativeIter = actionNextIter[scanIndex];
                found = 1'b1;
            end
        end

        speculativeIter1 = responseCommittedIter1;
        found = 1'b0;
        for (offset = 1; offset <= ACTION_DEPTH; offset = offset + 1) begin
            scanIndex = (integer'(actionTail) + ACTION_DEPTH - offset) %
                        ACTION_DEPTH;
            if (!found && actionValid[scanIndex] &&
                (actionIndex[scanIndex] == responseIndex1) &&
                (actionTag[scanIndex] == responseTag1) &&
                (actionGeneration[scanIndex] == responseGeneration1)) begin
                speculativeIter1 = actionNextIter[scanIndex];
                found = 1'b1;
            end
        end
    end

    always_comb begin
        responseHit = responseValid &&
            (responseTag == responseRequestedTag);
        responseHit1 = responseValid1 &&
            (responseTag1 == responseRequestedTag1);

        actionSlot0Free = !actionValid[actionTail];
        reserveAction0 = response0Conditional_i && responseHit &&
                         actionSlot0Free;
        slot1Tail = reserveAction0 ? nextAction(actionTail) : actionTail;
        actionSlot1Free = !actionValid[slot1Tail];

        queryMeta_o = '0;
        queryMeta_o.hit = responseHit && actionSlot0Free;
        queryMeta_o.confident = queryMeta_o.hit &&
            (responseConfidence == CONFIDENCE_MAX) &&
            (responseTrip != '0);
        queryMeta_o.prediction =
            (speculativeIter >= responseTrip) ?
                !responseDirection : responseDirection;
        queryMeta_o.used = queryMeta_o.confident;
        queryMeta_o.tableIndex = responseIndex;
        queryMeta_o.tag = responseTag;
        queryMeta_o.generation = responseGeneration;
        queryMeta_o.iterationBefore = speculativeIter;
        queryMeta_o.tripCount = responseTrip;
        queryMeta_o.direction = responseDirection;
        queryMeta_o.checkpointTail = actionTail;

        queryMeta1_o = '0;
        queryMeta1_o.hit = responseHit1 && actionSlot1Free;
        queryMeta1_o.confident = queryMeta1_o.hit &&
            (responseConfidence1 == CONFIDENCE_MAX) &&
            (responseTrip1 != '0);
        queryMeta1_o.prediction =
            (speculativeIter1 >= responseTrip1) ?
                !responseDirection1 : responseDirection1;
        queryMeta1_o.used = queryMeta1_o.confident;
        queryMeta1_o.tableIndex = responseIndex1;
        queryMeta1_o.tag = responseTag1;
        queryMeta1_o.generation = responseGeneration1;
        queryMeta1_o.iterationBefore = speculativeIter1;
        queryMeta1_o.tripCount = responseTrip1;
        queryMeta1_o.direction = responseDirection1;
        queryMeta1_o.checkpointTail = slot1Tail;

        updateIndex = pcIndex(updatePc_i);
        updateTag = pcTag(updatePc_i);
        updateMatch = validTable[updateIndex] &&
                      (tagTable[updateIndex] == updateTag);
    end

    assign allocateAction0 = speculateValid_i && responseHit &&
                             actionSlot0Free;
    assign allocateAction1 = speculateValid1_i && responseHit1 &&
                             actionSlot1Free;

    always_ff @(posedge clk or negedge rst) begin : updateState
        integer distanceFromCheckpoint;
        integer distanceToTail;
        loop_meta_t recoveryMeta;
        loop_iter_t observedTrip;

        if (!rst) begin
            actionTail <= '0;
            responseIndex <= '0;
            responseIndex1 <= '0;
            responseRequestedTag <= '0;
            responseRequestedTag1 <= '0;
            responseValid <= 1'b0;
            responseValid1 <= 1'b0;
            responseTag <= '0;
            responseTag1 <= '0;
            responseTrip <= '0;
            responseTrip1 <= '0;
            responseCommittedIter <= '0;
            responseCommittedIter1 <= '0;
            responseConfidence <= '0;
            responseConfidence1 <= '0;
            responseDirection <= 1'b0;
            responseDirection1 <= 1'b0;
            responseGeneration <= '0;
            responseGeneration1 <= '0;
            for (entryIndex = 0; entryIndex < ENTRIES;
                 entryIndex = entryIndex + 1) begin
                validTable[entryIndex] = 1'b0;
                tagTable[entryIndex] = '0;
                tripTable[entryIndex] = '0;
                committedIterTable[entryIndex] = '0;
                confidenceTable[entryIndex] = '0;
                ageTable[entryIndex] = '0;
                directionTable[entryIndex] = 1'b0;
                generationTable[entryIndex] = '0;
            end
            for (actionEntry = 0; actionEntry < ACTION_DEPTH;
                 actionEntry = actionEntry + 1) begin
                actionValid[actionEntry] = 1'b0;
                actionIndex[actionEntry] = '0;
                actionTag[actionEntry] = '0;
                actionGeneration[actionEntry] = '0;
                actionNextIter[actionEntry] = '0;
            end
            for (checkpointIndex = 0; checkpointIndex < ROB_ENTRY_NUM;
                 checkpointIndex = checkpointIndex + 1)
                robCheckpoint[checkpointIndex] = '0;
        end else begin
            // Synchronous two-lane table lookup.
            responseIndex <= pcIndex(queryPc_i);
            responseIndex1 <= pcIndex(queryPc1_i);
            responseRequestedTag <= pcTag(queryPc_i);
            responseRequestedTag1 <= pcTag(queryPc1_i);
            responseValid <= validTable[pcIndex(queryPc_i)];
            responseValid1 <= validTable[pcIndex(queryPc1_i)];
            responseTag <= tagTable[pcIndex(queryPc_i)];
            responseTag1 <= tagTable[pcIndex(queryPc1_i)];
            responseTrip <= tripTable[pcIndex(queryPc_i)];
            responseTrip1 <= tripTable[pcIndex(queryPc1_i)];
            responseCommittedIter <=
                committedIterTable[pcIndex(queryPc_i)];
            responseCommittedIter1 <=
                committedIterTable[pcIndex(queryPc1_i)];
            responseConfidence <= confidenceTable[pcIndex(queryPc_i)];
            responseConfidence1 <= confidenceTable[pcIndex(queryPc1_i)];
            responseDirection <= directionTable[pcIndex(queryPc_i)];
            responseDirection1 <= directionTable[pcIndex(queryPc1_i)];
            responseGeneration <= generationTable[pcIndex(queryPc_i)];
            responseGeneration1 <= generationTable[pcIndex(queryPc1_i)];

            // Retired state is never rolled back.
            if (updateValid_i) begin
                if (updateMeta_i.hit)
                    actionValid[updateMeta_i.checkpointTail] <= 1'b0;

                if (updateMatch) begin
                    if (updateTaken_i == directionTable[updateIndex]) begin
                        committedIterTable[updateIndex] <=
                            advanceIteration(
                                committedIterTable[updateIndex],
                                updateTaken_i,
                                directionTable[updateIndex]);
                    end else begin
                        observedTrip = committedIterTable[updateIndex];
                        committedIterTable[updateIndex] <= '0;
                        if ((observedTrip != '0) &&
                            (tripTable[updateIndex] == observedTrip)) begin
                            if (confidenceTable[updateIndex] !=
                                CONFIDENCE_MAX)
                                confidenceTable[updateIndex] <=
                                    confidenceTable[updateIndex] +
                                    LOOP_CONFIDENCE_WIDTH'(1);
                            if (ageTable[updateIndex] != AGE_MAX)
                                ageTable[updateIndex] <=
                                    ageTable[updateIndex] +
                                    LOOP_AGE_WIDTH'(1);
                        end else begin
                            tripTable[updateIndex] <= observedTrip;
                            confidenceTable[updateIndex] <= '0;
                            if (ageTable[updateIndex] != '0)
                                ageTable[updateIndex] <=
                                    ageTable[updateIndex] -
                                    LOOP_AGE_WIDTH'(1);
                        end
                    end
                end else if (updateTaken_i &&
                             (updateTarget_i < updatePc_i) &&
                             (!validTable[updateIndex] ||
                              (ageTable[updateIndex] == '0))) begin
                    validTable[updateIndex] <= 1'b1;
                    tagTable[updateIndex] <= updateTag;
                    tripTable[updateIndex] <= '0;
                    committedIterTable[updateIndex] <= loop_iter_t'(1);
                    confidenceTable[updateIndex] <= '0;
                    ageTable[updateIndex] <= LOOP_AGE_WIDTH'(1);
                    directionTable[updateIndex] <= 1'b1;
                    generationTable[updateIndex] <=
                        generationTable[updateIndex] +
                        LOOP_GENERATION_WIDTH'(1);
                end else begin
                    if (ageTable[updateIndex] != '0)
                        ageTable[updateIndex] <=
                            ageTable[updateIndex] -
                            LOOP_AGE_WIDTH'(1);
                end
            end

            if (flush_i) begin
                actionTail <= '0;
                for (actionEntry = 0; actionEntry < ACTION_DEPTH;
                     actionEntry = actionEntry + 1)
                    actionValid[actionEntry] <= 1'b0;
            end else if (recoverValid_i) begin
                recoveryMeta = robCheckpoint[recoverRobTag_i];
                distanceToTail =
                    (integer'(actionTail) + ACTION_DEPTH -
                     integer'(recoveryMeta.checkpointTail)) % ACTION_DEPTH;
                for (actionEntry = 0; actionEntry < ACTION_DEPTH;
                     actionEntry = actionEntry + 1) begin
                    distanceFromCheckpoint =
                        (actionEntry + ACTION_DEPTH -
                         integer'(recoveryMeta.checkpointTail)) %
                        ACTION_DEPTH;
                    if (distanceFromCheckpoint < distanceToTail)
                        actionValid[actionEntry] <= 1'b0;
                end
                actionTail <= recoveryMeta.checkpointTail;
                if (recoverIsConditional_i && recoveryMeta.hit &&
                    validTable[recoveryMeta.tableIndex] &&
                    (tagTable[recoveryMeta.tableIndex] ==
                     recoveryMeta.tag) &&
                    (generationTable[recoveryMeta.tableIndex] ==
                     recoveryMeta.generation)) begin
                    actionValid[recoveryMeta.checkpointTail] <= 1'b1;
                    actionIndex[recoveryMeta.checkpointTail] <=
                        recoveryMeta.tableIndex;
                    actionTag[recoveryMeta.checkpointTail] <=
                        recoveryMeta.tag;
                    actionGeneration[recoveryMeta.checkpointTail] <=
                        recoveryMeta.generation;
                    actionNextIter[recoveryMeta.checkpointTail] <=
                        advanceIteration(
                            recoveryMeta.iterationBefore,
                            recoverTaken_i,
                            directionTable[recoveryMeta.tableIndex]);
                    actionTail <= nextAction(
                        recoveryMeta.checkpointTail);
                end
            end else begin
                if (allocateAction0) begin
                    actionValid[actionTail] <= 1'b1;
                    actionIndex[actionTail] <= responseIndex;
                    actionTag[actionTail] <= responseTag;
                    actionGeneration[actionTail] <= responseGeneration;
                    actionNextIter[actionTail] <= advanceIteration(
                        speculativeIter, speculateTaken_i,
                        responseDirection);
                end
                if (allocateAction1) begin
                    actionValid[slot1Tail] <= 1'b1;
                    actionIndex[slot1Tail] <= responseIndex1;
                    actionTag[slot1Tail] <= responseTag1;
                    actionGeneration[slot1Tail] <= responseGeneration1;
                    actionNextIter[slot1Tail] <= advanceIteration(
                        speculativeIter1, speculateTaken1_i,
                        responseDirection1);
                end
                if (allocateAction1)
                    actionTail <= nextAction(slot1Tail);
                else if (allocateAction0)
                    actionTail <= nextAction(actionTail);

                for (checkpointIndex = 0; checkpointIndex < 2;
                     checkpointIndex = checkpointIndex + 1)
                    if (checkpointAllocValid_i[checkpointIndex])
                        robCheckpoint[
                            checkpointAllocTag_i[checkpointIndex]] <=
                            checkpointAllocMeta_i[checkpointIndex];
            end
        end
    end

endmodule
