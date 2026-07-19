// Two-bank, two-read TAGE storage.  Each query lane owns a replicated Tag RAM
// read port; both replicas receive the same allocation writes.  Counter,
// usefulness, valid, and generation state remain small shadow arrays so a
// retired Provider can be updated without consuming a prediction-read port.
//
// Query results are registered.  The explicit post-write forwarding below
// makes read-during-write behavior independent of the target SRAM/BRAM mode.
module TageTable
    import TypesPkg::*;
#(
    parameter int ENTRIES = TAGE_TABLE_ENTRIES,
    parameter int TAG_WIDTH = 7,
    parameter int INDEX_WIDTH = $clog2(ENTRIES)
)
(
    input  logic clk,
    input  logic rst,

    input  logic [INDEX_WIDTH-1:0] queryIndex_i,
    input  logic [TAG_WIDTH-1:0] queryTag_i,
    input  logic queryBank_i,
    output logic queryHit_o,
    output logic queryPrediction_o,
    output logic [2:0] queryCounter_o,
    output logic [1:0] queryUseful_o,
    output tage_generation_t queryGeneration_o,

    input  logic [INDEX_WIDTH-1:0] queryIndex1_i,
    input  logic [TAG_WIDTH-1:0] queryTag1_i,
    input  logic queryBank1_i,
    output logic queryHit1_o,
    output logic queryPrediction1_o,
    output logic [2:0] queryCounter1_o,
    output logic [1:0] queryUseful1_o,
    output tage_generation_t queryGeneration1_o,

    input  logic [INDEX_WIDTH-1:0] updateIndex_i,
    input  logic [TAG_WIDTH-1:0] updateTag_i,
    input  logic updateBank_i,
    input  tage_generation_t updateGeneration_i,
    output logic updateMatch_o,
    output logic updateReplaceable_o,
    output logic [1:0] updateUseful_o,

    input  logic providerUpdateValid_i,
    input  logic updateTaken_i,
    input  logic providerUsefulIncrement_i,
    input  logic providerUsefulDecrement_i,
    input  logic allocateValid_i,
    input  logic replacementUsefulDecrement_i,

    input  logic ageValid_i,
    input  logic [INDEX_WIDTH-1:0] ageIndex_i
);

    localparam int BANK_COUNT = 2;
    localparam int ROWS_PER_BANK = ENTRIES/BANK_COUNT;
    localparam int ROW_WIDTH = $clog2(ROWS_PER_BANK);

    // Hash Index bit zero selects the physical Bank and the upper bits select
    // its Row. Replication supplies one independent synchronous Tag read for
    // each prediction lane without discarding any logical Index information.
    (* ram_style = "block" *)
    logic [TAG_WIDTH-1:0] tagLane0Bank0 [ROWS_PER_BANK];
    (* ram_style = "block" *)
    logic [TAG_WIDTH-1:0] tagLane0Bank1 [ROWS_PER_BANK];
    (* ram_style = "block" *)
    logic [TAG_WIDTH-1:0] tagLane1Bank0 [ROWS_PER_BANK];
    (* ram_style = "block" *)
    logic [TAG_WIDTH-1:0] tagLane1Bank1 [ROWS_PER_BANK];
    logic validTable [BANK_COUNT][ROWS_PER_BANK];
    logic [2:0] counterTable [BANK_COUNT][ROWS_PER_BANK];
    logic [1:0] usefulTable [BANK_COUNT][ROWS_PER_BANK];
    tage_generation_t generationTable [BANK_COUNT][ROWS_PER_BANK];

    logic [ROW_WIDTH-1:0] queryRow;
    logic [ROW_WIDTH-1:0] queryRow1;
    logic [ROW_WIDTH-1:0] updateRow;
    logic [ROW_WIDTH-1:0] ageRow;
    logic ageBank;

    logic updateCurrentValid;
    logic [2:0] updateCurrentCounter;
    logic [1:0] updateCurrentUseful;
    tage_generation_t updateCurrentGeneration;

    logic functionalWrite;
    logic functionalWriteValid;
    logic [2:0] functionalWriteCounter;
    logic [1:0] functionalWriteUseful;
    tage_generation_t functionalWriteGeneration;
    logic ageWrite;
    logic [1:0] ageWriteUseful;

    logic queryReadValid;
    logic [TAG_WIDTH-1:0] queryReadTag;
    logic [TAG_WIDTH-1:0] queryRequestedTag;
    logic [2:0] queryReadCounter;
    logic [1:0] queryReadUseful;
    tage_generation_t queryReadGeneration;
    logic queryReadValid1;
    logic [TAG_WIDTH-1:0] queryReadTag1;
    logic [TAG_WIDTH-1:0] queryRequestedTag1;
    logic [2:0] queryReadCounter1;
    logic [1:0] queryReadUseful1;
    tage_generation_t queryReadGeneration1;

    integer bankIndex;
    integer rowIndex;

    assign queryRow = queryIndex_i[INDEX_WIDTH-1:1];
    assign queryRow1 = queryIndex1_i[INDEX_WIDTH-1:1];
    assign updateRow = updateIndex_i[INDEX_WIDTH-1:1];
    assign ageRow = ageIndex_i[INDEX_WIDTH-1:1];
    assign ageBank = ageIndex_i[0];

    always_comb begin
        updateCurrentValid = validTable[updateBank_i][updateRow];
        updateCurrentCounter = counterTable[updateBank_i][updateRow];
        updateCurrentUseful = usefulTable[updateBank_i][updateRow];
        updateCurrentGeneration = generationTable[updateBank_i][updateRow];
        // Allocation is the only operation that changes a Tag.  A generation
        // snapshot therefore revalidates an in-flight Provider without an
        // asynchronous Tag-RAM read on the update side.
        updateMatch_o = updateCurrentValid &&
                        (updateCurrentGeneration == updateGeneration_i);
        updateReplaceable_o = !updateCurrentValid ||
                              (updateCurrentUseful == 2'b00);
        updateUseful_o = updateCurrentUseful;
    end

    always_comb begin
        functionalWrite = 1'b0;
        functionalWriteValid = updateCurrentValid;
        functionalWriteCounter = updateCurrentCounter;
        functionalWriteUseful = updateCurrentUseful;
        functionalWriteGeneration = updateCurrentGeneration;

        if (allocateValid_i) begin
            functionalWrite = 1'b1;
            functionalWriteValid = 1'b1;
            functionalWriteCounter = updateTaken_i ? 3'b100 : 3'b011;
            functionalWriteUseful = 2'b00;
            functionalWriteGeneration = updateCurrentGeneration +
                                        tage_generation_t'(1);
        end else if (providerUpdateValid_i && updateMatch_o) begin
            functionalWrite = 1'b1;
            if (updateTaken_i && (updateCurrentCounter != 3'b111))
                functionalWriteCounter = updateCurrentCounter + 3'b001;
            else if (!updateTaken_i && (updateCurrentCounter != 3'b000))
                functionalWriteCounter = updateCurrentCounter - 3'b001;

            if (providerUsefulIncrement_i &&
                (updateCurrentUseful != 2'b11))
                functionalWriteUseful = updateCurrentUseful + 2'b01;
            else if (providerUsefulDecrement_i &&
                     (updateCurrentUseful != 2'b00))
                functionalWriteUseful = updateCurrentUseful - 2'b01;
        end else if (replacementUsefulDecrement_i &&
                     (updateCurrentUseful != 2'b00)) begin
            functionalWrite = 1'b1;
            functionalWriteUseful = updateCurrentUseful - 2'b01;
        end
    end

    assign ageWrite = ageValid_i &&
        !(functionalWrite && (ageBank == updateBank_i) &&
          (ageRow == updateRow));
    assign ageWriteUseful = {1'b0, usefulTable[ageBank][ageRow][1]};

    assign queryHit_o = queryReadValid &&
                        (queryReadTag == queryRequestedTag);
    assign queryPrediction_o = queryReadCounter[2];
    assign queryCounter_o = queryReadCounter;
    assign queryUseful_o = queryReadUseful;
    assign queryGeneration_o = queryReadGeneration;
    assign queryHit1_o = queryReadValid1 &&
                         (queryReadTag1 == queryRequestedTag1);
    assign queryPrediction1_o = queryReadCounter1[2];
    assign queryCounter1_o = queryReadCounter1;
    assign queryUseful1_o = queryReadUseful1;
    assign queryGeneration1_o = queryReadGeneration1;

    // Tag memories and their output registers deliberately have no reset.
    // Reset valid bits make their contents unobservable, while keeping this
    // process reset-free preserves ordinary synchronous BRAM inference.
    always_ff @(posedge clk) begin
        if (queryBank_i)
            queryReadTag <= tagLane0Bank1[queryRow];
        else
            queryReadTag <= tagLane0Bank0[queryRow];
        queryRequestedTag <= queryTag_i;

        if (queryBank1_i)
            queryReadTag1 <= tagLane1Bank1[queryRow1];
        else
            queryReadTag1 <= tagLane1Bank0[queryRow1];
        queryRequestedTag1 <= queryTag1_i;

        if (rst && allocateValid_i) begin
            if (updateBank_i) begin
                tagLane0Bank1[updateRow] <= updateTag_i;
                tagLane1Bank1[updateRow] <= updateTag_i;
            end else begin
                tagLane0Bank0[updateRow] <= updateTag_i;
                tagLane1Bank0[updateRow] <= updateTag_i;
            end

            // Allocation is the only operation that changes a Tag. Forward
            // its new value to either simultaneous read of the same location.
            if ((queryBank_i == updateBank_i) &&
                (queryRow == updateRow))
                queryReadTag <= updateTag_i;
            if ((queryBank1_i == updateBank_i) &&
                (queryRow1 == updateRow))
                queryReadTag1 <= updateTag_i;
        end
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            queryReadValid <= 1'b0;
            queryReadCounter <= 3'b011;
            queryReadUseful <= '0;
            queryReadGeneration <= '0;
            queryReadValid1 <= 1'b0;
            queryReadCounter1 <= 3'b011;
            queryReadUseful1 <= '0;
            queryReadGeneration1 <= '0;
            // Tag RAM contents are intentionally not reset.  Cleared valid
            // shadows make those bits unobservable and permit BRAM inference.
            for (bankIndex = 0; bankIndex < BANK_COUNT;
                 bankIndex = bankIndex + 1) begin
                for (rowIndex = 0; rowIndex < ROWS_PER_BANK;
                     rowIndex = rowIndex + 1) begin
                    validTable[bankIndex][rowIndex] = 1'b0;
                    counterTable[bankIndex][rowIndex] = 3'b011;
                    usefulTable[bankIndex][rowIndex] = 2'b00;
                    generationTable[bankIndex][rowIndex] = '0;
                end
            end
        end else begin
            // Synchronous prediction reads.  Lane replication removes
            // same-bank conflicts between the dual-fetch queries.
            queryReadValid <= validTable[queryBank_i][queryRow];
            queryReadCounter <= counterTable[queryBank_i][queryRow];
            queryReadUseful <= usefulTable[queryBank_i][queryRow];
            queryReadGeneration <= generationTable[queryBank_i][queryRow];

            queryReadValid1 <= validTable[queryBank1_i][queryRow1];
            queryReadCounter1 <= counterTable[queryBank1_i][queryRow1];
            queryReadUseful1 <= usefulTable[queryBank1_i][queryRow1];
            queryReadGeneration1 <= generationTable[queryBank1_i][queryRow1];

            // Aging is a low-priority write and is also forwarded into a
            // simultaneous prediction read.
            if (ageWrite) begin
                usefulTable[ageBank][ageRow] <= ageWriteUseful;
                if ((queryBank_i == ageBank) && (queryRow == ageRow))
                    queryReadUseful <= ageWriteUseful;
                if ((queryBank1_i == ageBank) && (queryRow1 == ageRow))
                    queryReadUseful1 <= ageWriteUseful;
            end

            if (functionalWrite) begin
                validTable[updateBank_i][updateRow] <= functionalWriteValid;
                counterTable[updateBank_i][updateRow] <=
                    functionalWriteCounter;
                usefulTable[updateBank_i][updateRow] <=
                    functionalWriteUseful;
                generationTable[updateBank_i][updateRow] <=
                    functionalWriteGeneration;

                // Explicit post-write forwarding defines SRAM/BRAM
                // read-during-write semantics for both prediction lanes.
                if ((queryBank_i == updateBank_i) &&
                    (queryRow == updateRow)) begin
                    queryReadValid <= functionalWriteValid;
                    queryReadCounter <= functionalWriteCounter;
                    queryReadUseful <= functionalWriteUseful;
                    queryReadGeneration <= functionalWriteGeneration;
                end
                if ((queryBank1_i == updateBank_i) &&
                    (queryRow1 == updateRow)) begin
                    queryReadValid1 <= functionalWriteValid;
                    queryReadCounter1 <= functionalWriteCounter;
                    queryReadUseful1 <= functionalWriteUseful;
                    queryReadGeneration1 <= functionalWriteGeneration;
                end
            end
        end
    end

endmodule
