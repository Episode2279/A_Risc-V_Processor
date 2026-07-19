// Compact GEHL-style statistical corrector for the TAGE direction predictor.
//
// Persistent SC counter state (CBP logical accounting):
//     PC bias: 256 entries * 6 bits                 = 1536 bits
//     GEHL:    4 tables * 128 entries * 6 bits     = 3072 bits
//                                                   ------------
//                                                   = 4608 bits
//
// Four incremental 7-bit folds for histories 3/7/15/31 are maintained by
// TagePredictor.  They add 28 bits to the complete predictor-state budget but
// keep the request path from folding a 64-bit GHR combinationally every cycle.
// The bias component is counted twice in the signed score; this is arithmetic
// weighting and does not duplicate its storage.
module StatisticalCorrector
    import TypesPkg::*;
#(
    parameter int BIAS_TABLE_ENTRIES = 256,
    parameter int GEHL_TABLE_NUM = 4,
    parameter int GEHL_TABLE_ENTRIES = 128,
    parameter int COUNTER_WIDTH = 6,
    parameter int BIAS_SCORE_WEIGHT = 2,
    parameter int SCORE_WIDTH = 10,
    parameter int HISTORY_FOLD_NUM = GEHL_TABLE_NUM,
    parameter int HISTORY_FOLD_WIDTH = $clog2(GEHL_TABLE_ENTRIES),
    parameter int LOW_CONFIDENCE_THRESHOLD = 23,
    parameter int WEAK_BASE_WEIGHT = 20,
    parameter int STRONG_BASE_WEIGHT = 62,
    parameter int BIAS_INDEX_WIDTH = $clog2(BIAS_TABLE_ENTRIES),
    parameter int GEHL_INDEX_WIDTH = $clog2(GEHL_TABLE_ENTRIES)
)
(
    input  logic clk,
    input  logic rst,

    // Both lanes launch together.  The table values are registered so the SC
    // response is aligned with the synchronous TAGE-table response.
    input  logic queryValid_i,
    input  instruction_addr_t queryPc_i,
    input  instruction_addr_t queryPc1_i,
    input  logic [HISTORY_FOLD_WIDTH-1:0]
        queryHistoryFold_i [HISTORY_FOLD_NUM],
    input  logic [HISTORY_FOLD_WIDTH-1:0]
        queryHistoryFold1_i [HISTORY_FOLD_NUM],
    input  tage_path_history_t queryPath_i,
    input  tage_path_history_t queryPath1_i,

    input  logic basePrediction_i,
    input  logic baseStrong_i,
    input  logic basePrediction1_i,
    input  logic baseStrong1_i,

    output logic responseValid_o,
    output logic predictTaken_o,
    output logic predictTaken1_o,
    output logic lowConfidence_o,
    output logic lowConfidence1_o,
    output logic signed [SCORE_WIDTH-1:0] score_o,
    output logic signed [SCORE_WIDTH-1:0] score1_o,

    // One nonsquashed conditional retirement update per cycle.  Prediction
    // metadata supplies the exact GHR/path context used at fetch time.
    input  logic updateValid_i,
    input  instruction_addr_t updatePc_i,
    input  tage_history_t updateHistory_i,
    input  tage_path_history_t updatePath_i,
    input  logic updateTaken_i,
    input  logic updateFinalPrediction_i,
    input  logic updateLowConfidence_i
);

    localparam logic signed [COUNTER_WIDTH-1:0] COUNTER_MAX =
        {1'b0, {(COUNTER_WIDTH-1){1'b1}}};
    localparam logic signed [COUNTER_WIDTH-1:0] COUNTER_MIN =
        {1'b1, {(COUNTER_WIDTH-1){1'b0}}};
    localparam int LOGICAL_COUNTER_STORAGE_BITS =
        (BIAS_TABLE_ENTRIES * COUNTER_WIDTH) +
        (GEHL_TABLE_NUM * GEHL_TABLE_ENTRIES * COUNTER_WIDTH);

    // A physical FPGA implementation may bank or replicate these logical
    // tables for 2R1W access.  Such replication is real physical cost, but CBP
    // capacity accounting charges each logical table only once.
    logic signed [COUNTER_WIDTH-1:0]
        biasTable [BIAS_TABLE_ENTRIES];
    logic signed [COUNTER_WIDTH-1:0]
        gehlTable [GEHL_TABLE_NUM][GEHL_TABLE_ENTRIES];

    logic [BIAS_INDEX_WIDTH-1:0] queryBiasIndex;
    logic [BIAS_INDEX_WIDTH-1:0] queryBiasIndex1;
    logic [BIAS_INDEX_WIDTH-1:0] updateBiasIndex;
    logic [GEHL_INDEX_WIDTH-1:0] queryGehlIndex [GEHL_TABLE_NUM];
    logic [GEHL_INDEX_WIDTH-1:0] queryGehlIndex1 [GEHL_TABLE_NUM];
    logic [GEHL_INDEX_WIDTH-1:0] updateGehlIndex [GEHL_TABLE_NUM];
    logic [HISTORY_FOLD_WIDTH-1:0] updateFold [GEHL_TABLE_NUM];

    logic signed [COUNTER_WIDTH-1:0] responseBiasCounter;
    logic signed [COUNTER_WIDTH-1:0] responseBiasCounter1;
    logic signed [COUNTER_WIDTH-1:0] responseGehlCounter [GEHL_TABLE_NUM];
    logic signed [COUNTER_WIDTH-1:0] responseGehlCounter1 [GEHL_TABLE_NUM];
    logic signed [COUNTER_WIDTH-1:0] updatedBiasCounter;
    logic signed [COUNTER_WIDTH-1:0] updatedGehlCounter [GEHL_TABLE_NUM];
    logic trainUpdate;

    // Fail elaboration if a parameter override silently violates either the
    // reserved 4608-bit SC allocation or the complete 4 KiB budget.
    initial begin
        if (HISTORY_FOLD_NUM != GEHL_TABLE_NUM)
            $fatal(1, "SC must receive one history fold per GEHL table");
        if (HISTORY_FOLD_WIDTH != GEHL_INDEX_WIDTH)
            $fatal(1, "SC fold width must match the GEHL index width");
        if (LOGICAL_COUNTER_STORAGE_BITS != BPU_SC_STORAGE_BITS)
            $fatal(1, "SC counter state must remain exactly 4608 bits");
        if (BPU_TOTAL_STORAGE_BITS > BPU_CBP_STORAGE_LIMIT_BITS)
            $fatal(1, "BPU logical state exceeds the CBP 4 KiB budget");
    end

    function automatic integer historyLengthForTable(input integer tableId);
        begin
            case (tableId)
                0: historyLengthForTable = 3;
                1: historyLengthForTable = 7;
                2: historyLengthForTable = 15;
                default: historyLengthForTable = 31;
            endcase
        end
    endfunction

    function automatic logic [GEHL_INDEX_WIDTH-1:0] rotateIndex(
        input logic [GEHL_INDEX_WIDTH-1:0] value,
        input integer amount
    );
        integer rotation;
        begin
            rotation = amount % GEHL_INDEX_WIDTH;
            if (rotation == 0)
                rotateIndex = value;
            else
                rotateIndex = (value << rotation) |
                              (value >> (GEHL_INDEX_WIDTH-rotation));
        end
    endfunction

    // XOR the word-PC chunks into an eight-bit static-branch signature.
    // This larger table reduces destructive aliasing in the branch bias term.
    function automatic logic [BIAS_INDEX_WIDTH-1:0] hashBiasIndex(
        input instruction_addr_t pc
    );
        logic [BIAS_INDEX_WIDTH-1:0] result;
        integer bitIndex;
        begin
            result = '0;
            for (bitIndex = 2; bitIndex < WORD_SIZE;
                 bitIndex = bitIndex + 1)
                result[(bitIndex-2) % BIAS_INDEX_WIDTH] =
                    result[(bitIndex-2) % BIAS_INDEX_WIDTH] ^ pc[bitIndex];
            hashBiasIndex = result;
        end
    endfunction

    // Independent PC/history polynomials for H=3/7/15/31.  Path history is
    // mixed only into the two longer components, where it improves separation
    // without destabilising the short-history correlations.
    function automatic logic [GEHL_INDEX_WIDTH-1:0] hashGehlIndex(
        input instruction_addr_t pc,
        input logic [HISTORY_FOLD_WIDTH-1:0] historyFold,
        input tage_path_history_t path,
        input integer tableId
    );
        logic [GEHL_INDEX_WIDTH-1:0] pcFold0;
        logic [GEHL_INDEX_WIDTH-1:0] pcFold1;
        logic [GEHL_INDEX_WIDTH-1:0] pcFold2;
        logic [GEHL_INDEX_WIDTH-1:0] pcFold3;
        logic [GEHL_INDEX_WIDTH-1:0] pathFold;
        integer bitIndex;
        integer pcGroup;
        begin
            pcFold0 = '0;
            pcFold1 = '0;
            pcFold2 = '0;
            pcFold3 = '0;
            pathFold = '0;

            for (bitIndex = 2; bitIndex < WORD_SIZE;
                 bitIndex = bitIndex + 1) begin
                pcGroup = ((bitIndex-2) / GEHL_INDEX_WIDTH) % 4;
                case (pcGroup)
                    0: pcFold0[(bitIndex-2) % GEHL_INDEX_WIDTH] =
                        pcFold0[(bitIndex-2) % GEHL_INDEX_WIDTH] ^
                        pc[bitIndex];
                    1: pcFold1[(bitIndex-2) % GEHL_INDEX_WIDTH] =
                        pcFold1[(bitIndex-2) % GEHL_INDEX_WIDTH] ^
                        pc[bitIndex];
                    2: pcFold2[(bitIndex-2) % GEHL_INDEX_WIDTH] =
                        pcFold2[(bitIndex-2) % GEHL_INDEX_WIDTH] ^
                        pc[bitIndex];
                    default: pcFold3[(bitIndex-2) % GEHL_INDEX_WIDTH] =
                        pcFold3[(bitIndex-2) % GEHL_INDEX_WIDTH] ^
                        pc[bitIndex];
                endcase
            end

            for (bitIndex = 0; bitIndex < TAGE_PATH_HISTORY_WIDTH;
                 bitIndex = bitIndex + 1)
                pathFold[bitIndex % GEHL_INDEX_WIDTH] =
                    pathFold[bitIndex % GEHL_INDEX_WIDTH] ^ path[bitIndex];

            case (tableId)
                0: hashGehlIndex = rotateIndex(pcFold0, 1) ^ pcFold1 ^
                    rotateIndex(pcFold3, 3) ^
                    rotateIndex(historyFold, 2) ^
                    GEHL_INDEX_WIDTH'(7'h17);
                1: hashGehlIndex = rotateIndex(pcFold0, 3) ^
                    rotateIndex(pcFold2, 1) ^ pcFold3 ^
                    rotateIndex(historyFold, 5) ^
                    GEHL_INDEX_WIDTH'(7'h2d);
                2: hashGehlIndex = pcFold0 ^ rotateIndex(pcFold1, 4) ^
                    rotateIndex(pcFold2, 2) ^
                    rotateIndex(historyFold, 1) ^
                    rotateIndex(pathFold, 2) ^
                    GEHL_INDEX_WIDTH'(7'h43);
                default: hashGehlIndex = rotateIndex(pcFold0, 5) ^
                    pcFold1 ^ rotateIndex(pcFold3, 1) ^
                    rotateIndex(historyFold, 6) ^
                    rotateIndex(pathFold, 4) ^
                    GEHL_INDEX_WIDTH'(7'h65);
            endcase
        end
    endfunction

    function automatic logic [HISTORY_FOLD_WIDTH-1:0] rebuildHistoryFold(
        input tage_history_t history,
        input integer tableId
    );
        logic [HISTORY_FOLD_WIDTH-1:0] result;
        integer historyLength;
        integer bitIndex;
        begin
            result = '0;
            historyLength = historyLengthForTable(tableId);
            for (bitIndex = 0; bitIndex < TAGE_HISTORY_WIDTH;
                 bitIndex = bitIndex + 1)
                if (bitIndex < historyLength)
                    result[bitIndex % HISTORY_FOLD_WIDTH] =
                        result[bitIndex % HISTORY_FOLD_WIDTH] ^
                        history[bitIndex];
            rebuildHistoryFold = result;
        end
    endfunction

    function automatic logic signed [COUNTER_WIDTH-1:0] trainCounter(
        input logic signed [COUNTER_WIDTH-1:0] value,
        input logic taken
    );
        begin
            if (taken) begin
                if (value == COUNTER_MAX)
                    trainCounter = value;
                else
                    trainCounter = value + COUNTER_WIDTH'(1);
            end else begin
                if (value == COUNTER_MIN)
                    trainCounter = value;
                else
                    trainCounter = value - COUNTER_WIDTH'(1);
            end
        end
    endfunction

    function automatic integer signed counterAsInteger(
        input logic signed [COUNTER_WIDTH-1:0] value
    );
        begin
            counterAsInteger =
                {{(32-COUNTER_WIDTH){value[COUNTER_WIDTH-1]}}, value};
        end
    endfunction

    always_comb begin : buildIndices
        integer tableIndex;

        trainUpdate = updateValid_i &&
            ((updateFinalPrediction_i != updateTaken_i) ||
             updateLowConfidence_i);

        queryBiasIndex = hashBiasIndex(queryPc_i);
        queryBiasIndex1 = hashBiasIndex(queryPc1_i);
        updateBiasIndex = hashBiasIndex(updatePc_i);
        updatedBiasCounter = trainCounter(
            biasTable[updateBiasIndex], updateTaken_i);

        for (tableIndex = 0; tableIndex < GEHL_TABLE_NUM;
             tableIndex = tableIndex + 1) begin
            updateFold[tableIndex] = rebuildHistoryFold(
                updateHistory_i, tableIndex);
            queryGehlIndex[tableIndex] = hashGehlIndex(
                queryPc_i, queryHistoryFold_i[tableIndex],
                queryPath_i, tableIndex);
            queryGehlIndex1[tableIndex] = hashGehlIndex(
                queryPc1_i, queryHistoryFold1_i[tableIndex],
                queryPath1_i, tableIndex);
            updateGehlIndex[tableIndex] = hashGehlIndex(
                updatePc_i, updateFold[tableIndex],
                updatePath_i, tableIndex);
            updatedGehlCounter[tableIndex] = trainCounter(
                gehlTable[tableIndex][updateGehlIndex[tableIndex]],
                updateTaken_i);
        end
    end

    // Same-edge write/read collisions forward the post-training value.  This
    // keeps simulation semantics independent of inferred RAM read-during-write
    // mode and lets a younger lookup observe the retired update immediately.
    always_ff @(posedge clk or negedge rst) begin
        integer tableIndex;
        integer entryIndex;

        if (!rst) begin
            responseValid_o <= 1'b0;
            responseBiasCounter <= '0;
            responseBiasCounter1 <= '0;
            for (entryIndex = 0; entryIndex < BIAS_TABLE_ENTRIES;
                 entryIndex = entryIndex + 1)
                biasTable[entryIndex] = '0;
            for (tableIndex = 0; tableIndex < GEHL_TABLE_NUM;
                 tableIndex = tableIndex + 1) begin
                responseGehlCounter[tableIndex] <= '0;
                responseGehlCounter1[tableIndex] <= '0;
                for (entryIndex = 0; entryIndex < GEHL_TABLE_ENTRIES;
                     entryIndex = entryIndex + 1)
                    gehlTable[tableIndex][entryIndex] = '0;
            end
        end else begin
            responseValid_o <= queryValid_i;

            if (trainUpdate && (updateBiasIndex == queryBiasIndex))
                responseBiasCounter <= updatedBiasCounter;
            else
                responseBiasCounter <= biasTable[queryBiasIndex];
            if (trainUpdate && (updateBiasIndex == queryBiasIndex1))
                responseBiasCounter1 <= updatedBiasCounter;
            else
                responseBiasCounter1 <= biasTable[queryBiasIndex1];
            if (trainUpdate)
                biasTable[updateBiasIndex] <= updatedBiasCounter;

            for (tableIndex = 0; tableIndex < GEHL_TABLE_NUM;
                 tableIndex = tableIndex + 1) begin
                if (trainUpdate &&
                    (updateGehlIndex[tableIndex] ==
                     queryGehlIndex[tableIndex]))
                    responseGehlCounter[tableIndex] <=
                        updatedGehlCounter[tableIndex];
                else
                    responseGehlCounter[tableIndex] <=
                        gehlTable[tableIndex][queryGehlIndex[tableIndex]];

                if (trainUpdate &&
                    (updateGehlIndex[tableIndex] ==
                     queryGehlIndex1[tableIndex]))
                    responseGehlCounter1[tableIndex] <=
                        updatedGehlCounter[tableIndex];
                else
                    responseGehlCounter1[tableIndex] <=
                        gehlTable[tableIndex][queryGehlIndex1[tableIndex]];

                if (trainUpdate)
                    gehlTable[tableIndex][updateGehlIndex[tableIndex]] <=
                        updatedGehlCounter[tableIndex];
            end
        end
    end

    always_comb begin : buildScore0
        integer signed accumulatedScore;
        integer signed componentScore;
        integer tableIndex;

        componentScore = BIAS_SCORE_WEIGHT *
            counterAsInteger(responseBiasCounter);
        for (tableIndex = 0; tableIndex < GEHL_TABLE_NUM;
             tableIndex = tableIndex + 1)
            componentScore = componentScore +
                counterAsInteger(responseGehlCounter[tableIndex]);

        accumulatedScore = componentScore + (basePrediction_i ?
            (baseStrong_i ? STRONG_BASE_WEIGHT : WEAK_BASE_WEIGHT) :
            -(baseStrong_i ? STRONG_BASE_WEIGHT : WEAK_BASE_WEIGHT));
        score_o = SCORE_WIDTH'(accumulatedScore);

        if (accumulatedScore > 0)
            predictTaken_o = 1'b1;
        else if (accumulatedScore < 0)
            predictTaken_o = 1'b0;
        else
            predictTaken_o = basePrediction_i;

        // Confidence is measured on the complete decision.  Measuring only
        // the residual component sum overtrains SC and creates harmful flips.
        lowConfidence_o =
            (accumulatedScore <= LOW_CONFIDENCE_THRESHOLD) &&
            (accumulatedScore >= -LOW_CONFIDENCE_THRESHOLD);
    end

    always_comb begin : buildScore1
        integer signed accumulatedScore;
        integer signed componentScore;
        integer tableIndex;

        componentScore = BIAS_SCORE_WEIGHT *
            counterAsInteger(responseBiasCounter1);
        for (tableIndex = 0; tableIndex < GEHL_TABLE_NUM;
             tableIndex = tableIndex + 1)
            componentScore = componentScore +
                counterAsInteger(responseGehlCounter1[tableIndex]);

        accumulatedScore = componentScore + (basePrediction1_i ?
            (baseStrong1_i ? STRONG_BASE_WEIGHT : WEAK_BASE_WEIGHT) :
            -(baseStrong1_i ? STRONG_BASE_WEIGHT : WEAK_BASE_WEIGHT));
        score1_o = SCORE_WIDTH'(accumulatedScore);

        if (accumulatedScore > 0)
            predictTaken1_o = 1'b1;
        else if (accumulatedScore < 0)
            predictTaken1_o = 1'b0;
        else
            predictTaken1_o = basePrediction1_i;

        lowConfidence1_o =
            (accumulatedScore <= LOW_CONFIDENCE_THRESHOLD) &&
            (accumulatedScore >= -LOW_CONFIDENCE_THRESHOLD);
    end

endmodule
