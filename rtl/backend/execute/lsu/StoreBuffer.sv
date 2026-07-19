module StoreBuffer
    import TypesPkg::*;
#(
    parameter int DEPTH = 8,
    parameter int PTR_W = $clog2(DEPTH),
    parameter int COUNT_W = $clog2(DEPTH + 1)
)
(
    input  logic        clk,
    input  logic        rst,

    // Only architecturally committed, cacheable Stores may enter this FIFO.
    // Consequently there is intentionally no flush or recovery input.
    input  logic        enqueueValid_i,
    output logic        enqueueReady_o,
    input  word_t       enqueueAddress_i,
    input  word_t       enqueueData_i,
    input  mem_access_t enqueueAccess_i,

    // The oldest Store drains first.  Once the consumer accepts this request,
    // it owns the Store and the FIFO entry may be released immediately.
    output logic        drainValid_o,
    input  logic        drainReady_i,
    output word_t       drainAddress_o,
    output word_t       drainData_o,
    output mem_access_t drainAccess_o,

    // Query all still-buffered Stores for a younger Load.  Matching bytes are
    // collected newest-to-oldest so the youngest Store wins each byte lane.
    // A partial overlap must wait because the backing cache still holds stale
    // bytes; a fully covered Load may be forwarded without accessing memory.
    input  logic        queryValid_i,
    input  word_t       queryAddress_i,
    input  mem_access_t queryAccess_i,
    output logic        queryReady_o,
    output logic        queryConflict_o,
    output logic        queryForwardValid_o,
    output word_t       queryForwardData_o,

    output logic        empty_o,
    output logic        full_o,
    output logic [COUNT_W-1:0] count_o
);

    word_t       addressArray [DEPTH];
    word_t       dataArray [DEPTH];
    mem_access_t accessArray [DEPTH];

    logic [PTR_W-1:0] headPtr;
    logic [PTR_W-1:0] tailPtr;
    logic [COUNT_W-1:0] entryCount;

    logic enqueueFire;
    logic drainFire;

    logic [3:0] queryLoadMask;
    logic [3:0] queryCoveredMask;
    logic [3:0] queryStoreMask;
    logic [3:0] queryNewMask;
    word_t queryRawData;
    word_t queryExpandedStoreData;
    integer queryOffset;
    integer queryIndex;
    integer queryLane;

    function automatic logic [PTR_W-1:0] incrementPtr(
        input logic [PTR_W-1:0] pointer
    );
        begin
            if (pointer == PTR_W'(DEPTH - 1))
                incrementPtr = '0;
            else
                incrementPtr = pointer + 1'b1;
        end
    endfunction

    function automatic logic [PTR_W-1:0] subtractPtr(
        input logic [PTR_W-1:0] pointer,
        input integer decrement
    );
        integer difference;
        begin
            difference = integer'(pointer) - decrement;
            while (difference < 0) difference = difference + DEPTH;
            subtractPtr = difference[PTR_W-1:0];
        end
    endfunction

    function automatic logic [3:0] loadByteMask(
        input mem_access_t accessMode,
        input logic [1:0] byteOffset
    );
        begin
            unique case (accessMode)
                MEM_BYTE, MEM_BYTE_U: loadByteMask = 4'b0001 << byteOffset;
                MEM_HALF, MEM_HALF_U: loadByteMask =
                    (byteOffset == 2'd3) ? 4'b0000 :
                                            (4'b0011 << byteOffset);
                default: loadByteMask = (byteOffset == 2'd0) ?
                                            4'b1111 : 4'b0000;
            endcase
        end
    endfunction

    function automatic logic [3:0] storeByteMask(
        input mem_access_t accessMode,
        input logic [1:0] byteOffset
    );
        begin
            unique case (accessMode)
                MEM_BYTE: storeByteMask = 4'b0001 << byteOffset;
                MEM_HALF: storeByteMask = (byteOffset == 2'd3) ?
                                               4'b0000 :
                                               (4'b0011 << byteOffset);
                default: storeByteMask = (byteOffset == 2'd0) ?
                                             4'b1111 : 4'b0000;
            endcase
        end
    endfunction

    function automatic word_t alignStoreData(
        input word_t storeData,
        input mem_access_t accessMode,
        input logic [1:0] byteOffset
    );
        begin
            unique case (accessMode)
                MEM_BYTE: alignStoreData =
                    word_t'(storeData[7:0]) << (byteOffset * 8);
                MEM_HALF: alignStoreData =
                    word_t'(storeData[15:0]) << (byteOffset * 8);
                default: alignStoreData = storeData;
            endcase
        end
    endfunction

    function automatic word_t formatLoadData(
        input word_t rawData,
        input mem_access_t accessMode,
        input logic [1:0] byteOffset
    );
        word_t shiftedData;
        begin
            shiftedData = rawData >> (byteOffset * 8);
            unique case (accessMode)
                MEM_BYTE:   formatLoadData =
                    {{24{shiftedData[7]}}, shiftedData[7:0]};
                MEM_HALF:   formatLoadData =
                    {{16{shiftedData[15]}}, shiftedData[15:0]};
                MEM_BYTE_U: formatLoadData = {24'd0, shiftedData[7:0]};
                MEM_HALF_U: formatLoadData = {16'd0, shiftedData[15:0]};
                default:    formatLoadData = rawData;
            endcase
        end
    endfunction

    assign empty_o = (entryCount == '0);
    assign full_o = (entryCount == COUNT_W'(DEPTH));
    assign count_o = entryCount;

    assign drainValid_o = !empty_o;
    assign drainAddress_o = empty_o ? '0 : addressArray[headPtr];
    assign drainData_o = empty_o ? '0 : dataArray[headPtr];
    assign drainAccess_o = empty_o ? MEM_WORD : accessArray[headPtr];
    assign drainFire = drainValid_o && drainReady_i;

    // A simultaneous drain frees the slot used by a same-cycle enqueue even
    // when the FIFO starts the cycle full.
    assign enqueueReady_o = !full_o || drainFire;
    assign enqueueFire = enqueueValid_i && enqueueReady_o;

    always_comb begin
        queryReady_o = 1'b1;
        queryConflict_o = 1'b0;
        queryForwardValid_o = 1'b0;
        queryForwardData_o = '0;
        queryLoadMask = loadByteMask(queryAccess_i, queryAddress_i[1:0]);
        queryCoveredMask = '0;
        queryStoreMask = '0;
        queryNewMask = '0;
        queryRawData = '0;
        queryExpandedStoreData = '0;
        queryIndex = 0;

        // tailPtr denotes the next free entry, so tailPtr-1 is the youngest
        // buffered Store.  Only the first writer encountered for each byte is
        // used, which naturally implements youngest-Store priority.
        if (queryValid_i) begin
            for (queryOffset = 0; queryOffset < DEPTH;
                 queryOffset = queryOffset + 1) begin
                queryIndex = integer'(subtractPtr(tailPtr, queryOffset + 1));
                if ((queryOffset < integer'(entryCount)) &&
                    (addressArray[queryIndex][WORD_SIZE-1:2] ==
                     queryAddress_i[WORD_SIZE-1:2])) begin
                    queryStoreMask = storeByteMask(
                        accessArray[queryIndex], addressArray[queryIndex][1:0]);
                    queryExpandedStoreData = alignStoreData(
                        dataArray[queryIndex], accessArray[queryIndex],
                        addressArray[queryIndex][1:0]);
                    queryNewMask = queryStoreMask & queryLoadMask &
                                   ~queryCoveredMask;
                    for (queryLane = 0; queryLane < 4;
                         queryLane = queryLane + 1) begin
                        if (queryNewMask[queryLane])
                            queryRawData[queryLane*8 +: 8] =
                                queryExpandedStoreData[queryLane*8 +: 8];
                    end
                    queryCoveredMask = queryCoveredMask |
                                       (queryStoreMask & queryLoadMask);
                end
            end

            queryConflict_o = |queryCoveredMask;
            queryForwardValid_o = (queryLoadMask != 4'b0000) &&
                ((queryCoveredMask & queryLoadMask) == queryLoadMask);
            queryReady_o = !queryConflict_o || queryForwardValid_o;
            if (queryForwardValid_o)
                queryForwardData_o = formatLoadData(
                    queryRawData, queryAccess_i, queryAddress_i[1:0]);
        end
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            headPtr <= '0;
            tailPtr <= '0;
            entryCount <= '0;
        end else begin
            if (drainFire)
                headPtr <= incrementPtr(headPtr);

            if (enqueueFire) begin
                addressArray[tailPtr] <= enqueueAddress_i;
                dataArray[tailPtr] <= enqueueData_i;
                accessArray[tailPtr] <= enqueueAccess_i;
                tailPtr <= incrementPtr(tailPtr);
            end

            unique case ({enqueueFire, drainFire})
                2'b10: entryCount <= entryCount + 1'b1;
                2'b01: entryCount <= entryCount - 1'b1;
                default: entryCount <= entryCount;
            endcase
        end
    end

    initial begin
        if ((DEPTH < 2) || ((DEPTH & (DEPTH - 1)) != 0))
            $error("StoreBuffer DEPTH must be a power of two >= 2");
    end

endmodule
