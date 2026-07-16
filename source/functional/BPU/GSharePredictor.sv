module GSharePredictor
    import TypesPkg::*;
#(
    parameter int HISTORY_W = BPU_HISTORY_WIDTH,
    parameter int PHT_ENTRIES = (1 << HISTORY_W)
)
(
    input  logic clk,
    input  logic rst,

    input  instruction_addr_t queryPc_i,
    output logic predictTaken_o,
    output bpu_index_t queryIndex_o,
    input instruction_addr_t queryPc1_i,
    input logic query0Conditional_i,
    input logic query0PredictedTaken_i,
    output logic predictTaken1_o,
    output bpu_index_t queryIndex1_o,
    output logic [HISTORY_W-1:0] queryHistory_o,
    output logic [HISTORY_W-1:0] queryHistory1_o,

    input logic speculateValid_i,
    input logic speculateTaken_i,
    input logic speculateValid1_i,
    input logic speculateTaken1_i,

    input  logic updateValid_i,
    input  logic updateIsConditional_i,
    input  bpu_index_t updateIndex_i,
    input  logic updateTaken_i,
    input  logic updateMispredicted_i,
    input  rob_tag_t updateRobTag_i,
    input  logic [1:0] checkpointAllocValid_i,
    input  rob_tag_t checkpointAllocTag_i [2],
    input  logic [HISTORY_W-1:0] checkpointAllocHistory_i [2]
);

    logic [HISTORY_W-1:0] globalHistory;
    logic [1:0] patternTable [PHT_ENTRIES];
    logic [1:0] updateCounter;
    logic [HISTORY_W-1:0] robHistoryCheckpoint [ROB_ENTRY_NUM];
    integer checkpointIndex;
    integer entryIndex;

    assign queryIndex_o = bpu_index_t'(
        queryPc_i[HISTORY_W+1:2] ^ globalHistory);
    assign predictTaken_o = patternTable[queryIndex_o][1];
    assign queryHistory_o = globalHistory;
    assign queryHistory1_o = query0Conditional_i ?
        {globalHistory[HISTORY_W-2:0], query0PredictedTaken_i} : globalHistory;
    assign queryIndex1_o = bpu_index_t'(queryPc1_i[HISTORY_W+1:2] ^
        (query0Conditional_i ? {globalHistory[HISTORY_W-2:0], query0PredictedTaken_i} : globalHistory));
    assign predictTaken1_o = patternTable[queryIndex1_o][1];
    assign updateCounter = patternTable[updateIndex_i];

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            globalHistory <= '0;
            for (entryIndex = 0; entryIndex < PHT_ENTRIES;
                 entryIndex = entryIndex + 1) begin
                patternTable[entryIndex] = 2'b01;
            end
            for (checkpointIndex = 0; checkpointIndex < ROB_ENTRY_NUM;
                 checkpointIndex = checkpointIndex + 1)
                robHistoryCheckpoint[checkpointIndex] = '0;
        end else if (updateValid_i) begin
            if (updateIsConditional_i && updateTaken_i) begin
                if (updateCounter != 2'b11)
                    patternTable[updateIndex_i] <= updateCounter + 2'b01;
            end else if (updateIsConditional_i) begin
                if (updateCounter != 2'b00)
                    patternTable[updateIndex_i] <= updateCounter - 2'b01;
            end
            if (updateMispredicted_i) begin
                if (updateIsConditional_i)
                    globalHistory <= {robHistoryCheckpoint[updateRobTag_i][HISTORY_W-2:0], updateTaken_i};
                else
                    globalHistory <= robHistoryCheckpoint[updateRobTag_i];
            end
        end
        if (rst && (speculateValid_i || speculateValid1_i) &&
            !(updateValid_i && updateMispredicted_i)) begin
            if (speculateValid1_i)
                globalHistory <= speculateValid_i ?
                    {globalHistory[HISTORY_W-3:0], speculateTaken_i, speculateTaken1_i} :
                    {globalHistory[HISTORY_W-2:0], speculateTaken1_i};
            else
                globalHistory <= {globalHistory[HISTORY_W-2:0], speculateTaken_i};
        end
        if (rst) begin
            for (checkpointIndex = 0; checkpointIndex < 2; checkpointIndex = checkpointIndex + 1)
                if (checkpointAllocValid_i[checkpointIndex])
                    robHistoryCheckpoint[checkpointAllocTag_i[checkpointIndex]] <=
                        checkpointAllocHistory_i[checkpointIndex];
        end
    end

endmodule
