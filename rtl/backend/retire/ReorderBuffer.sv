module ReorderBuffer
    import TypesPkg::*;
#(
    parameter int DEPTH = ROB_ENTRY_NUM,
    parameter int ALLOC_WIDTH = 2,
    parameter int COMPLETE_WIDTH = 2,
    parameter int COMMIT_WIDTH = 2,
    parameter int PTR_W = $clog2(DEPTH)
)
(
    input  logic clk,
    input  logic rst,
    input  logic flush_i,
    input  logic recoverValid_i,
    input  rob_tag_t recoverTag_i,
    output logic [DEPTH-1:0] recoverYoungerMask_o,

    input  logic queryBranchValid_i,
    input  rob_tag_t queryBranchTag_i,
    output logic queryHasOlderUnresolvedBranch_o,

    input  logic [ALLOC_WIDTH-1:0] allocValid_i,
    input  rob_entry_t allocEntry_i [ALLOC_WIDTH],
    output logic [ALLOC_WIDTH-1:0] allocReady_o,
    output rob_tag_t allocTag_o [ALLOC_WIDTH],

    input  logic [COMPLETE_WIDTH-1:0] completeValid_i,
    input  rob_tag_t completeTag_i [COMPLETE_WIDTH],
    input  logic [COMPLETE_WIDTH-1:0] completeException_i,
    input  logic [5:0] completeCause_i [COMPLETE_WIDTH],
    input  word_t completeValue_i [COMPLETE_WIDTH],

    input  logic branchResolveValid_i,
    input  rob_tag_t branchResolveTag_i,
    input  logic branchTaken_i,
    input  instruction_addr_t branchTarget_i,
    input  logic branchMispredicted_i,

    output logic [COMMIT_WIDTH-1:0] commitValid_o,
    output rob_tag_t commitTag_o [COMMIT_WIDTH],
    output rob_entry_t commitEntry_o [COMMIT_WIDTH],
    input  logic [COMMIT_WIDTH-1:0] commitReady_i,

    output logic empty_o,
    output logic full_o,
    output logic [$clog2(DEPTH+1)-1:0] count_o
);

    rob_entry_t entries [DEPTH];
    logic [PTR_W-1:0] headPtr;
    logic [PTR_W-1:0] tailPtr;
    integer entryCount;
    integer combLane;
    integer readyLane;
    integer seqLane;
    integer entryIndex;
    integer allocAccepted;
    integer commitAccepted;
    integer allocOffset;
    logic lane0Accepted;
    logic contiguousComplete;
    logic [PTR_W-1:0] commitPtr;
    integer recoverOffset;
    integer recoverIndex;
    integer recoverKeepCount;
    logic recoverFound;
    logic queryFound;
    integer queryOffset;
    integer queryIndex;

    function automatic logic [PTR_W-1:0] addPtr(
        input logic [PTR_W-1:0] base,
        input integer increment
    );
        integer sum;
        begin
            sum = integer'(base) + increment;
            while (sum >= DEPTH) sum = sum - DEPTH;
            addPtr = sum[PTR_W-1:0];
        end
    endfunction

    always_comb begin
        allocAccepted = 0;
        allocOffset = 0;
        for (combLane = 0; combLane < ALLOC_WIDTH; combLane = combLane + 1) begin
            allocReady_o[combLane] = ((DEPTH - entryCount) > allocOffset);
            allocTag_o[combLane] = rob_tag_t'(addPtr(tailPtr, allocOffset));
            if (allocValid_i[combLane] && allocReady_o[combLane]) begin
                allocOffset = allocOffset + 1;
                allocAccepted = allocAccepted + 1;
            end
        end

        contiguousComplete = 1'b1;
        for (combLane = 0; combLane < COMMIT_WIDTH; combLane = combLane + 1) begin
            commitValid_o[combLane] = 1'b0;
            commitEntry_o[combLane] = '0;
            commitPtr = addPtr(headPtr, combLane);
            commitTag_o[combLane] = rob_tag_t'(commitPtr);
            if (contiguousComplete && (entryCount > combLane) &&
                entries[commitPtr].valid && entries[commitPtr].complete) begin
                commitValid_o[combLane] = 1'b1;
                commitEntry_o[combLane] = entries[commitPtr];
            end else begin
                contiguousComplete = 1'b0;
            end
        end

        empty_o = (entryCount == 0);
        full_o = (entryCount == DEPTH);
        count_o = entryCount[$clog2(DEPTH+1)-1:0];
    end

    always_comb begin
        recoverYoungerMask_o = '0;
        recoverKeepCount = entryCount;
        recoverFound = 1'b0;
        recoverIndex = 0;
        if (recoverValid_i) begin
            recoverKeepCount = 0;
            for (recoverOffset = 0; recoverOffset < DEPTH;
                 recoverOffset = recoverOffset + 1) begin
                recoverIndex = integer'(addPtr(headPtr, recoverOffset));
                if (recoverOffset < entryCount) begin
                    if (recoverFound) begin
                        recoverYoungerMask_o[recoverIndex] = 1'b1;
                    end else begin
                        recoverKeepCount = recoverKeepCount + 1;
                    end
                    if (recoverIndex == integer'(recoverTag_i))
                        recoverFound = 1'b1;
                end
            end
            if (!recoverFound) begin
                recoverYoungerMask_o = '0;
                recoverKeepCount = entryCount;
            end
        end

    end

    always_comb begin
        queryHasOlderUnresolvedBranch_o = 1'b0;
        queryFound = 1'b0;
        queryIndex = 0;
        if (queryBranchValid_i) begin
            for (queryOffset = 0; queryOffset < DEPTH;
                 queryOffset = queryOffset + 1) begin
                queryIndex = integer'(addPtr(headPtr, queryOffset));
                if ((queryOffset < entryCount) && !queryFound) begin
                    if (queryIndex == integer'(queryBranchTag_i)) begin
                        queryFound = 1'b1;
                    end else if (entries[queryIndex].valid &&
                                 entries[queryIndex].isBranch &&
                                 !entries[queryIndex].complete) begin
                        queryHasOlderUnresolvedBranch_o = 1'b1;
                    end
                end
            end
        end
    end

    always_comb begin
        // Retirement is contiguous: lane 1 cannot pass a blocked lane 0.
        commitAccepted = 0;
        lane0Accepted = 1'b1;
        for (readyLane = 0; readyLane < COMMIT_WIDTH; readyLane = readyLane + 1) begin
            if (lane0Accepted && commitValid_o[readyLane] && commitReady_i[readyLane]) begin
                commitAccepted = commitAccepted + 1;
            end else begin
                lane0Accepted = 1'b0;
            end
        end

    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            headPtr <= '0;
            tailPtr <= '0;
            entryCount <= '0;
            for (entryIndex = 0; entryIndex < DEPTH; entryIndex = entryIndex + 1) begin
                entries[entryIndex] <= '0;
            end
        end else if (flush_i) begin
            headPtr <= '0;
            tailPtr <= '0;
            entryCount <= '0;
            for (entryIndex = 0; entryIndex < DEPTH; entryIndex = entryIndex + 1) begin
                entries[entryIndex] <= '0;
            end
        end else if (recoverValid_i) begin
            for (entryIndex = 0; entryIndex < DEPTH;
                 entryIndex = entryIndex + 1) begin
                if (recoverYoungerMask_o[entryIndex])
                    entries[entryIndex] <= '0;
            end
            for (seqLane = 0; seqLane < COMPLETE_WIDTH;
                 seqLane = seqLane + 1) begin
                if (completeValid_i[seqLane] &&
                    entries[completeTag_i[seqLane]].valid &&
                    !recoverYoungerMask_o[completeTag_i[seqLane]]) begin
                    entries[completeTag_i[seqLane]].complete <= 1'b1;
                    entries[completeTag_i[seqLane]].exception <=
                        completeException_i[seqLane];
                    entries[completeTag_i[seqLane]].exceptionCause <=
                        completeCause_i[seqLane];
                    entries[completeTag_i[seqLane]].exceptionValue <=
                        completeValue_i[seqLane];
                end
            end
            entries[recoverTag_i].complete <= 1'b1;
            entries[recoverTag_i].branchTaken <= branchTaken_i;
            entries[recoverTag_i].branchTarget <= branchTarget_i;
            entries[recoverTag_i].branchMispredicted <= branchMispredicted_i;
            tailPtr <= addPtr(headPtr, recoverKeepCount);
            entryCount <= recoverKeepCount;
        end else begin
            for (seqLane = 0; seqLane < COMMIT_WIDTH; seqLane = seqLane + 1) begin
                if (seqLane < commitAccepted) begin
                    entries[addPtr(headPtr, seqLane)] <= '0;
                end
            end

            for (seqLane = 0; seqLane < ALLOC_WIDTH; seqLane = seqLane + 1) begin
                if (allocValid_i[seqLane] && allocReady_o[seqLane]) begin
                    entries[allocTag_o[seqLane]] <= allocEntry_i[seqLane];
                    entries[allocTag_o[seqLane]].valid <= 1'b1;
                    entries[allocTag_o[seqLane]].complete <= 1'b0;
                end
            end

            for (seqLane = 0; seqLane < COMPLETE_WIDTH; seqLane = seqLane + 1) begin
                if (completeValid_i[seqLane] && entries[completeTag_i[seqLane]].valid) begin
                    entries[completeTag_i[seqLane]].complete <= 1'b1;
                    entries[completeTag_i[seqLane]].exception <= completeException_i[seqLane];
                    entries[completeTag_i[seqLane]].exceptionCause <= completeCause_i[seqLane];
                    entries[completeTag_i[seqLane]].exceptionValue <= completeValue_i[seqLane];
                end
            end

            if (branchResolveValid_i && entries[branchResolveTag_i].valid) begin
                entries[branchResolveTag_i].branchTaken <= branchTaken_i;
                entries[branchResolveTag_i].branchTarget <= branchTarget_i;
                entries[branchResolveTag_i].branchMispredicted <= branchMispredicted_i;
            end

            headPtr <= addPtr(headPtr, commitAccepted);
            tailPtr <= addPtr(tailPtr, allocAccepted);
            entryCount <= entryCount + allocAccepted - commitAccepted;
        end
    end

endmodule
