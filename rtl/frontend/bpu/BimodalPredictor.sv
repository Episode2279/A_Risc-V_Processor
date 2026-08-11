// Simple PC-indexed base direction predictor for TAGE.  Unlike GShare, this
// table carries no speculative history state: every static branch selects a
// two-bit saturating counter using its word PC.
module BimodalPredictor
    import TypesPkg::*;
#(
    parameter int INDEX_W = BPU_BASE_INDEX_WIDTH,
    parameter int PHT_ENTRIES = (1 << INDEX_W)
)
(
    input  logic clk,
    input  logic rst,

    input  instruction_addr_t queryPc_i,
    output logic predictTaken_o,
    output bpu_index_t queryIndex_o,
    input  instruction_addr_t queryPc1_i,
    output logic predictTaken1_o,
    output bpu_index_t queryIndex1_o,

    input  logic updateValid_i,
    input  logic updateIsConditional_i,
    input  bpu_index_t updateIndex_i,
    input  logic updateTaken_i
);

    logic [1:0] patternTable [PHT_ENTRIES];
    logic [1:0] updateCounter;
    integer entryIndex;

    assign queryIndex_o =
        bpu_index_t'(queryPc_i[INDEX_W+1:2]);
    assign queryIndex1_o =
        bpu_index_t'(queryPc1_i[INDEX_W+1:2]);
    assign predictTaken_o = patternTable[queryIndex_o][1];
    assign predictTaken1_o = patternTable[queryIndex1_o][1];
    assign updateCounter = patternTable[updateIndex_i];

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            // Weak not-taken is a neutral cold-start policy for conditional
            // branches and matches the former base predictor initialization.
            for (entryIndex = 0; entryIndex < PHT_ENTRIES;
                 entryIndex = entryIndex + 1)
                patternTable[entryIndex] = 2'b01;
        end else if (updateValid_i && updateIsConditional_i) begin
            if (updateTaken_i) begin
                if (updateCounter != 2'b11)
                    patternTable[updateIndex_i] <= updateCounter + 2'b01;
            end else if (updateCounter != 2'b00) begin
                patternTable[updateIndex_i] <= updateCounter - 2'b01;
            end
        end
    end

endmodule
