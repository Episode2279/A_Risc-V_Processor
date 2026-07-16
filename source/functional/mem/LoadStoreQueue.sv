module LoadStoreQueue
    import TypesPkg::*;
#(
    parameter int DEPTH = LSQ_ENTRY_NUM,
    parameter int ALLOC_WIDTH = 2,
    parameter int UPDATE_WIDTH = 2,
    parameter int RETIRE_WIDTH = 2,
    parameter int PTR_W = $clog2(DEPTH)
)
(
    input  logic clk,
    input  logic rst,
    input  logic flush_i,
    input  logic recoverValid_i,
    input  logic [ROB_ENTRY_NUM-1:0] recoverYoungerMask_i,

    input  logic [ALLOC_WIDTH-1:0] allocValid_i,
    input  lsq_entry_t allocEntry_i [ALLOC_WIDTH],
    output logic [ALLOC_WIDTH-1:0] allocReady_o,
    output lsq_tag_t allocTag_o [ALLOC_WIDTH],

    input  logic [UPDATE_WIDTH-1:0] addressValid_i,
    input  lsq_tag_t addressTag_i [UPDATE_WIDTH],
    input  word_t address_i [UPDATE_WIDTH],
    input  logic [UPDATE_WIDTH-1:0] storeDataValid_i,
    input  lsq_tag_t storeDataTag_i [UPDATE_WIDTH],
    input  word_t storeData_i [UPDATE_WIDTH],

    // Ordering query for the oldest ready memory-queue operation. Stores may
    // always calculate their address/data. A load waits for every older store
    // address, and either reads memory or forwards from the youngest older
    // store that fully covers the requested bytes.
    input  logic issueValid_i,
    input  lsq_tag_t issueTag_i,
    input  word_t issueAddress_i,
    input  mem_access_t issueMemCtr_i,
    output logic issueReady_o,
    output logic issueForwardValid_o,
    output word_t issueForwardData_o,

    output lsq_entry_t headEntry_o [RETIRE_WIDTH],
    output lsq_tag_t headTag_o [RETIRE_WIDTH],
    input  logic [$clog2(RETIRE_WIDTH+1)-1:0] retireCount_i,

    output logic empty_o,
    output logic full_o,
    output logic [$clog2(DEPTH+1)-1:0] count_o
);

    lsq_entry_t entries [DEPTH];
    logic [PTR_W-1:0] headPtr;
    logic [PTR_W-1:0] tailPtr;
    integer entryCount;
    integer combLane;
    integer seqLane;
    integer entryIndex;
    integer allocAccepted;
    integer allocOffset;
    integer retireAccepted;
    integer queryOffset;
    integer queryIndex;
    logic queryFound;
    logic [3:0] queryLoadMask;
    logic [3:0] olderStoreMask;
    word_t expandedStoreData;
    integer recoveryRetainedCount;

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

    function automatic logic [3:0] loadByteMask(
        input mem_access_t accessMode,
        input logic [1:0] offset
    );
        begin
            unique case (accessMode)
                MEM_BYTE, MEM_BYTE_U: loadByteMask = 4'b0001 << offset;
                MEM_HALF, MEM_HALF_U: loadByteMask = 4'b0011 << offset;
                default: loadByteMask = 4'b1111;
            endcase
        end
    endfunction

    function automatic logic [3:0] storeByteMask(
        input mem_access_t accessMode,
        input logic [1:0] offset
    );
        begin
            unique case (accessMode)
                MEM_BYTE: storeByteMask = 4'b0001 << offset;
                MEM_HALF: storeByteMask = (offset == 2'd3) ? 4'b0000 :
                                                (4'b0011 << offset);
                default: storeByteMask = 4'b1111;
            endcase
        end
    endfunction

    function automatic word_t expandStoreData(
        input word_t storeData,
        input mem_access_t accessMode,
        input logic [1:0] offset
    );
        begin
            unique case (accessMode)
                MEM_BYTE: expandStoreData = word_t'(storeData[7:0]) << (offset * 8);
                MEM_HALF: expandStoreData = word_t'(storeData[15:0]) << (offset * 8);
                default: expandStoreData = storeData;
            endcase
        end
    endfunction

    function automatic word_t formatForwardedLoad(
        input word_t rawWord,
        input mem_access_t accessMode,
        input logic [1:0] offset
    );
        word_t shiftedWord;
        begin
            shiftedWord = rawWord >> (offset * 8);
            unique case (accessMode)
                MEM_BYTE:   formatForwardedLoad = {{24{shiftedWord[7]}}, shiftedWord[7:0]};
                MEM_HALF:   formatForwardedLoad = {{16{shiftedWord[15]}}, shiftedWord[15:0]};
                MEM_BYTE_U: formatForwardedLoad = {24'd0, shiftedWord[7:0]};
                MEM_HALF_U: formatForwardedLoad = {16'd0, shiftedWord[15:0]};
                default:    formatForwardedLoad = rawWord;
            endcase
        end
    endfunction

    always_comb begin
        allocAccepted = 0;
        allocOffset = 0;
        for (combLane = 0; combLane < ALLOC_WIDTH; combLane = combLane + 1) begin
            allocReady_o[combLane] = ((DEPTH - entryCount) > allocOffset);
            allocTag_o[combLane] = lsq_tag_t'(addPtr(tailPtr, allocOffset));
            if (allocValid_i[combLane] && allocReady_o[combLane]) begin
                allocOffset = allocOffset + 1;
                allocAccepted = allocAccepted + 1;
            end
        end

        for (combLane = 0; combLane < RETIRE_WIDTH; combLane = combLane + 1) begin
            headEntry_o[combLane] = '0;
            headTag_o[combLane] = '0;
            if (entryCount > combLane) begin
                headEntry_o[combLane] = entries[addPtr(headPtr, combLane)];
                headTag_o[combLane] = lsq_tag_t'(addPtr(headPtr, combLane));
            end
        end

        retireAccepted = integer'(retireCount_i);
        if (retireAccepted > entryCount) retireAccepted = entryCount;
        if (retireAccepted > RETIRE_WIDTH) retireAccepted = RETIRE_WIDTH;

        empty_o = (entryCount == 0);
        full_o = (entryCount == DEPTH);
        count_o = entryCount[$clog2(DEPTH+1)-1:0];

        issueReady_o = 1'b0;
        issueForwardValid_o = 1'b0;
        issueForwardData_o = '0;
        queryFound = 1'b0;
        queryIndex = 0;
        queryLoadMask = loadByteMask(issueMemCtr_i, issueAddress_i[1:0]);
        olderStoreMask = '0;
        expandedStoreData = '0;
        recoveryRetainedCount = 0;
        for (queryOffset = 0; queryOffset < DEPTH;
             queryOffset = queryOffset + 1) begin
            queryIndex = integer'(addPtr(headPtr, queryOffset));
            if ((queryOffset < entryCount) && entries[queryIndex].valid &&
                !recoverYoungerMask_i[entries[queryIndex].robTag]) begin
                recoveryRetainedCount = recoveryRetainedCount + 1;
            end
        end

        if (issueValid_i && entries[issueTag_i].valid) begin
            if (entries[issueTag_i].isStore) begin
                issueReady_o = 1'b1;
                queryFound = 1'b1;
            end else if (entries[issueTag_i].isLoad) begin
                issueReady_o = 1'b1;
                for (queryOffset = 0; queryOffset < DEPTH; queryOffset = queryOffset + 1) begin
                    queryIndex = integer'(addPtr(headPtr, queryOffset));
                    if ((queryOffset < entryCount) && !queryFound) begin
                        if (queryIndex == integer'(issueTag_i)) begin
                            queryFound = 1'b1;
                        end else if (entries[queryIndex].valid &&
                                     entries[queryIndex].isStore) begin
                            if (!entries[queryIndex].addressReady) begin
                                issueReady_o = 1'b0;
                            end else if (entries[queryIndex].address[WORD_SIZE-1:2] ==
                                         issueAddress_i[WORD_SIZE-1:2]) begin
                                olderStoreMask = storeByteMask(
                                    entries[queryIndex].memCtr,
                                    entries[queryIndex].address[1:0]);
                                if ((olderStoreMask & queryLoadMask) != 4'b0000) begin
                                    if (((olderStoreMask & queryLoadMask) == queryLoadMask) &&
                                        entries[queryIndex].dataReady) begin
                                        expandedStoreData = expandStoreData(
                                            entries[queryIndex].storeData,
                                            entries[queryIndex].memCtr,
                                            entries[queryIndex].address[1:0]);
                                        issueForwardValid_o = 1'b1;
                                        issueForwardData_o = formatForwardedLoad(
                                            expandedStoreData,
                                            issueMemCtr_i,
                                            issueAddress_i[1:0]);
                                    end else begin
                                        // Partial overlap or missing store data
                                        // must wait until that store retires.
                                        issueReady_o = 1'b0;
                                    end
                                end
                            end
                        end
                    end
                end
                if (!queryFound) issueReady_o = 1'b0;
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
                if (entries[entryIndex].valid &&
                    recoverYoungerMask_i[entries[entryIndex].robTag]) begin
                    entries[entryIndex] <= '0;
                end
            end
            for (seqLane = 0; seqLane < UPDATE_WIDTH;
                 seqLane = seqLane + 1) begin
                if (addressValid_i[seqLane] &&
                    entries[addressTag_i[seqLane]].valid &&
                    !recoverYoungerMask_i[
                        entries[addressTag_i[seqLane]].robTag]) begin
                    entries[addressTag_i[seqLane]].addressReady <= 1'b1;
                    entries[addressTag_i[seqLane]].address <= address_i[seqLane];
                end
                if (storeDataValid_i[seqLane] &&
                    entries[storeDataTag_i[seqLane]].valid &&
                    !recoverYoungerMask_i[
                        entries[storeDataTag_i[seqLane]].robTag]) begin
                    entries[storeDataTag_i[seqLane]].dataReady <= 1'b1;
                    entries[storeDataTag_i[seqLane]].storeData <=
                        storeData_i[seqLane];
                end
            end
            tailPtr <= addPtr(headPtr, recoveryRetainedCount);
            entryCount <= recoveryRetainedCount;
        end else begin
            for (seqLane = 0; seqLane < RETIRE_WIDTH; seqLane = seqLane + 1) begin
                if (seqLane < retireAccepted) entries[addPtr(headPtr, seqLane)] <= '0;
            end

            for (seqLane = 0; seqLane < ALLOC_WIDTH; seqLane = seqLane + 1) begin
                if (allocValid_i[seqLane] && allocReady_o[seqLane]) begin
                    entries[allocTag_o[seqLane]] <= allocEntry_i[seqLane];
                    entries[allocTag_o[seqLane]].valid <= 1'b1;
                end
            end

            for (seqLane = 0; seqLane < UPDATE_WIDTH; seqLane = seqLane + 1) begin
                if (addressValid_i[seqLane] && entries[addressTag_i[seqLane]].valid) begin
                    entries[addressTag_i[seqLane]].addressReady <= 1'b1;
                    entries[addressTag_i[seqLane]].address <= address_i[seqLane];
                end
                if (storeDataValid_i[seqLane] && entries[storeDataTag_i[seqLane]].valid) begin
                    entries[storeDataTag_i[seqLane]].dataReady <= 1'b1;
                    entries[storeDataTag_i[seqLane]].storeData <= storeData_i[seqLane];
                end
            end

            headPtr <= addPtr(headPtr, retireAccepted);
            tailPtr <= addPtr(tailPtr, allocAccepted);
            entryCount <= entryCount + allocAccepted - retireAccepted;
        end
    end

endmodule
