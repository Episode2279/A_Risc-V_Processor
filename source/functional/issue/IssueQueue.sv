module IssueQueue
    import TypesPkg::*;
#(
    parameter int DEPTH = ISSUE_QUEUE_ENTRY_NUM,
    parameter int DISPATCH_WIDTH = 2,
    parameter int ISSUE_WIDTH = 2,
    parameter int WAKEUP_WIDTH = 2,
    parameter int AGE_W = 32
)
(
    input  logic clk,
    input  logic rst,
    input  logic flush_i,
    input  logic recoverValid_i,
    input  rob_tag_t recoverTag_i,
    input  logic [ROB_ENTRY_NUM-1:0] recoverYoungerMask_i,

    input  renamed_uop_t dispatchUop_i [DISPATCH_WIDTH],
    output logic [DISPATCH_WIDTH-1:0] dispatchReady_o,

    input  logic [WAKEUP_WIDTH-1:0] wakeupValid_i,
    input  phys_reg_addr_t wakeupPhys_i [WAKEUP_WIDTH],

    output logic [ISSUE_WIDTH-1:0] issueValid_o,
    output renamed_uop_t issueUop_o [ISSUE_WIDTH],
    input  logic [ISSUE_WIDTH-1:0] issueReady_i,

    output logic empty_o,
    output logic full_o,
    output logic [$clog2(DEPTH+1)-1:0] count_o
);

    renamed_uop_t entries [DEPTH];
    logic [AGE_W-1:0] ages [DEPTH];
    logic [AGE_W-1:0] nextAge;
    integer freeIndex [DISPATCH_WIDTH];
    integer freeSlot [DISPATCH_WIDTH];
    integer selectedIndex [ISSUE_WIDTH];
    integer combEntryIndex;
    integer combLane;
    integer seqEntryIndex;
    integer seqLane;
    integer freeSeen;
    integer dispatchOffset;
    integer occupiedCount;
    integer seqDispatchRank;
    logic [AGE_W-1:0] selectedAge [ISSUE_WIDTH];
    logic readyEntry [DEPTH];
    logic hasReadySpecial;

    function automatic logic sourceReadyNow(
        input phys_reg_addr_t sourcePhys,
        input logic storedReady,
        input logic sourceUsed
    );
        integer wakeLane;
        begin
            sourceReadyNow = storedReady || !sourceUsed || (sourcePhys == '0);
            for (wakeLane = 0; wakeLane < WAKEUP_WIDTH; wakeLane = wakeLane + 1) begin
                if (wakeupValid_i[wakeLane] && (wakeupPhys_i[wakeLane] == sourcePhys)) begin
                    sourceReadyNow = 1'b1;
                end
            end
        end
    endfunction

    always_comb begin
        for (combLane = 0; combLane < DISPATCH_WIDTH; combLane = combLane + 1) begin
            freeIndex[combLane] = -1;
            freeSlot[combLane] = -1;
            dispatchReady_o[combLane] = 1'b0;
        end

        freeSeen = 0;
        occupiedCount = 0;
        for (combEntryIndex = 0; combEntryIndex < DEPTH; combEntryIndex = combEntryIndex + 1) begin
            if (entries[combEntryIndex].valid) begin
                occupiedCount = occupiedCount + 1;
            end else if (freeSeen < DISPATCH_WIDTH) begin
                freeSlot[freeSeen] = combEntryIndex;
                freeSeen = freeSeen + 1;
            end
        end

        // Compact valid lanes onto free entries. This matters when lane 0 is
        // routed to the memory queue and lane 1 to the integer queue (or vice
        // versa): a lone lane 1 must use the first available slot.
        dispatchOffset = 0;
        for (combLane = 0; combLane < DISPATCH_WIDTH; combLane = combLane + 1) begin
            if (dispatchOffset < freeSeen) begin
                freeIndex[combLane] = freeSlot[dispatchOffset];
                dispatchReady_o[combLane] = 1'b1;
            end
            if (dispatchUop_i[combLane].valid && dispatchReady_o[combLane]) begin
                dispatchOffset = dispatchOffset + 1;
            end
        end

        for (combLane = 0; combLane < ISSUE_WIDTH; combLane = combLane + 1) begin
            selectedIndex[combLane] = -1;
            selectedAge[combLane] = '1;
            issueValid_o[combLane] = 1'b0;
            issueUop_o[combLane] = '0;
        end
        hasReadySpecial = 1'b0;
        for (combEntryIndex = 0; combEntryIndex < DEPTH; combEntryIndex = combEntryIndex + 1) begin
            readyEntry[combEntryIndex] = entries[combEntryIndex].valid &&
                sourceReadyNow(entries[combEntryIndex].src1Phys,
                               entries[combEntryIndex].src1Ready,
                               entries[combEntryIndex].useRs1) &&
                sourceReadyNow(entries[combEntryIndex].src2Phys,
                               entries[combEntryIndex].src2Ready,
                               entries[combEntryIndex].useRs2);
            if (readyEntry[combEntryIndex] &&
                (entries[combEntryIndex].fuClass != FU_INTEGER))
                hasReadySpecial = 1'b1;
        end

        // Port 0 accepts every FU class.  When possible, reserve it for a
        // branch/CSR/memory uop because port 1 is an integer-only ALU.  This
        // forms useful special+integer pairs instead of stranding the special
        // uop behind the port restriction.
        for (combEntryIndex = 0; combEntryIndex < DEPTH; combEntryIndex = combEntryIndex + 1) begin
            if (readyEntry[combEntryIndex] &&
                (!hasReadySpecial || (entries[combEntryIndex].fuClass != FU_INTEGER)) &&
                ((selectedIndex[0] < 0) || (ages[combEntryIndex] < selectedAge[0]))) begin
                selectedIndex[0] = combEntryIndex;
                selectedAge[0] = ages[combEntryIndex];
            end
        end

        // Port 1 accepts only ordinary integer uops and never selects the same
        // entry as port 0.
        for (combEntryIndex = 0; combEntryIndex < DEPTH; combEntryIndex = combEntryIndex + 1) begin
            if (readyEntry[combEntryIndex] &&
                (entries[combEntryIndex].fuClass == FU_INTEGER) &&
                (combEntryIndex != selectedIndex[0]) &&
                ((selectedIndex[1] < 0) || (ages[combEntryIndex] < selectedAge[1]))) begin
                selectedIndex[1] = combEntryIndex;
                selectedAge[1] = ages[combEntryIndex];
            end
        end

        for (combLane = 0; combLane < ISSUE_WIDTH; combLane = combLane + 1) begin
            issueValid_o[combLane] = (selectedIndex[combLane] >= 0);
            if (selectedIndex[combLane] >= 0) begin
                issueUop_o[combLane] = entries[selectedIndex[combLane]];
                issueUop_o[combLane].src1Ready = 1'b1;
                issueUop_o[combLane].src2Ready = 1'b1;
            end
        end

        count_o = occupiedCount[$clog2(DEPTH+1)-1:0];
        empty_o = (occupiedCount == 0);
        full_o = (occupiedCount == DEPTH);
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            nextAge <= '0;
            for (seqEntryIndex = 0; seqEntryIndex < DEPTH; seqEntryIndex = seqEntryIndex + 1) begin
                entries[seqEntryIndex] <= '0;
                ages[seqEntryIndex] <= '0;
            end
        end else if (flush_i) begin
            nextAge <= '0;
            for (seqEntryIndex = 0; seqEntryIndex < DEPTH; seqEntryIndex = seqEntryIndex + 1) begin
                entries[seqEntryIndex] <= '0;
                ages[seqEntryIndex] <= '0;
            end
        end else if (recoverValid_i) begin
            for (seqEntryIndex = 0; seqEntryIndex < DEPTH;
                 seqEntryIndex = seqEntryIndex + 1) begin
                if (entries[seqEntryIndex].valid &&
                    recoverYoungerMask_i[entries[seqEntryIndex].robTag]) begin
                    entries[seqEntryIndex] <= '0;
                end else if (entries[seqEntryIndex].valid) begin
                    for (seqLane = 0; seqLane < WAKEUP_WIDTH;
                         seqLane = seqLane + 1) begin
                        if (wakeupValid_i[seqLane]) begin
                            if (entries[seqEntryIndex].src1Phys ==
                                wakeupPhys_i[seqLane])
                                entries[seqEntryIndex].src1Ready <= 1'b1;
                            if (entries[seqEntryIndex].src2Phys ==
                                wakeupPhys_i[seqLane])
                                entries[seqEntryIndex].src2Ready <= 1'b1;
                        end
                    end
                end
            end
            // The resolving branch is preserved in the ROB but has completed
            // execution, so remove its IQ entry as part of recovery.
            for (seqLane = 0; seqLane < ISSUE_WIDTH; seqLane = seqLane + 1) begin
                if (issueValid_o[seqLane] && issueReady_i[seqLane] &&
                    (issueUop_o[seqLane].robTag == recoverTag_i))
                    entries[selectedIndex[seqLane]] <= '0;
            end
        end else begin
            for (seqEntryIndex = 0; seqEntryIndex < DEPTH; seqEntryIndex = seqEntryIndex + 1) begin
                if (entries[seqEntryIndex].valid) begin
                    for (seqLane = 0; seqLane < WAKEUP_WIDTH; seqLane = seqLane + 1) begin
                        if (wakeupValid_i[seqLane]) begin
                            if (entries[seqEntryIndex].src1Phys == wakeupPhys_i[seqLane]) begin
                                entries[seqEntryIndex].src1Ready <= 1'b1;
                            end
                            if (entries[seqEntryIndex].src2Phys == wakeupPhys_i[seqLane]) begin
                                entries[seqEntryIndex].src2Ready <= 1'b1;
                            end
                        end
                    end
                end
            end

            for (seqLane = 0; seqLane < ISSUE_WIDTH; seqLane = seqLane + 1)
                if (issueValid_o[seqLane] && issueReady_i[seqLane])
                    entries[selectedIndex[seqLane]] <= '0;

            seqDispatchRank = 0;
            for (seqLane = 0; seqLane < DISPATCH_WIDTH; seqLane = seqLane + 1) begin
                if (dispatchUop_i[seqLane].valid && dispatchReady_o[seqLane]) begin
                    entries[freeSlot[seqDispatchRank]] <= dispatchUop_i[seqLane];
                    // Age follows accepted program order, not the physical
                    // decoder lane number.  A lone lane 1 followed by a lane
                    // 0 operation must not receive duplicate ages.
                    ages[freeSlot[seqDispatchRank]] <= nextAge + seqDispatchRank;
                    if (!dispatchUop_i[seqLane].useRs1 ||
                        (dispatchUop_i[seqLane].src1Phys == '0)) begin
                        entries[freeSlot[seqDispatchRank]].src1Ready <= 1'b1;
                    end
                    if (!dispatchUop_i[seqLane].useRs2 ||
                        (dispatchUop_i[seqLane].src2Phys == '0)) begin
                        entries[freeSlot[seqDispatchRank]].src2Ready <= 1'b1;
                    end
                    for (seqEntryIndex = 0; seqEntryIndex < WAKEUP_WIDTH; seqEntryIndex = seqEntryIndex + 1) begin
                        if (wakeupValid_i[seqEntryIndex] &&
                            (wakeupPhys_i[seqEntryIndex] == dispatchUop_i[seqLane].src1Phys)) begin
                            entries[freeSlot[seqDispatchRank]].src1Ready <= 1'b1;
                        end
                        if (wakeupValid_i[seqEntryIndex] &&
                            (wakeupPhys_i[seqEntryIndex] == dispatchUop_i[seqLane].src2Phys)) begin
                            entries[freeSlot[seqDispatchRank]].src2Ready <= 1'b1;
                        end
                    end
                    seqDispatchRank = seqDispatchRank + 1;
                end
            end
            nextAge <= nextAge + seqDispatchRank;
        end
    end

endmodule
