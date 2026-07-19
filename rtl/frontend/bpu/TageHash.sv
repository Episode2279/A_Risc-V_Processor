// Per-table TAGE key generation. Query-side direction folds are supplied by
// incremental state, while the non-critical retirement port reconstructs the
// same folds from prediction-time metadata.
//
// Index and Tag use different CRC polynomials, seeds, input permutations, and
// fold rotations. The CRC transformations are expanded into constant linear
// XOR matrices at elaboration time. Runtime prediction therefore uses parallel
// parity reductions rather than a serial feedback chain on the fetch path; the
// physical XOR-tree shape remains a synthesis-tool decision.
module TageHash
    import TypesPkg::*;
#(
    parameter int ENTRIES = TAGE_TABLE_ENTRIES,
    parameter int HISTORY_LENGTH = 4,
    parameter int TAG_WIDTH = 7,
    parameter int TABLE_ID = 0,
    parameter int INDEX_WIDTH = $clog2(ENTRIES)
)
(
    input  instruction_addr_t queryPc_i,
    input  logic [INDEX_WIDTH-1:0] queryIndexFold_i,
    input  logic [TAG_WIDTH-1:0] queryTagFoldA_i,
    input  logic [TAG_WIDTH-2:0] queryTagFoldB_i,
    input  tage_path_history_t queryPathHistory_i,
    output logic [INDEX_WIDTH-1:0] queryIndex_o,
    output logic [TAG_WIDTH-1:0] queryTag_o,

    input  instruction_addr_t queryPc1_i,
    input  logic [INDEX_WIDTH-1:0] queryIndexFold1_i,
    input  logic [TAG_WIDTH-1:0] queryTagFoldA1_i,
    input  logic [TAG_WIDTH-2:0] queryTagFoldB1_i,
    input  tage_path_history_t queryPathHistory1_i,
    output logic [INDEX_WIDTH-1:0] queryIndex1_o,
    output logic [TAG_WIDTH-1:0] queryTag1_o,

    input  instruction_addr_t updatePc_i,
    input  tage_history_t updateHistory_i,
    input  tage_path_history_t updatePathHistory_i,
    output logic [INDEX_WIDTH-1:0] updateIndex_o,
    output logic [TAG_WIDTH-1:0] updateTag_o
);

    localparam int PC_HASH_BITS = WORD_SIZE-2;

    localparam logic [INDEX_WIDTH-1:0] INDEX_POLYNOMIAL =
        (TABLE_ID == 0) ? INDEX_WIDTH'(8'h1d) :
        (TABLE_ID == 1) ? INDEX_WIDTH'(8'h2b) :
        (TABLE_ID == 2) ? INDEX_WIDTH'(8'h4d) :
        (TABLE_ID == 3) ? INDEX_WIDTH'(8'h87) :
                          INDEX_WIDTH'(8'hb9);
    localparam logic [INDEX_WIDTH-1:0] INDEX_SEED =
        (TABLE_ID == 0) ? INDEX_WIDTH'(8'h13) :
        (TABLE_ID == 1) ? INDEX_WIDTH'(8'h35) :
        (TABLE_ID == 2) ? INDEX_WIDTH'(8'h59) :
        (TABLE_ID == 3) ? INDEX_WIDTH'(8'ha7) :
                          INDEX_WIDTH'(8'hc3);
    localparam logic [TAG_WIDTH-1:0] TAG_POLYNOMIAL =
        (TABLE_ID == 0) ? TAG_WIDTH'(16'h005b) :
        (TABLE_ID == 1) ? TAG_WIDTH'(16'h00b7) :
        (TABLE_ID == 2) ? TAG_WIDTH'(16'h016d) :
        (TABLE_ID == 3) ? TAG_WIDTH'(16'h02d5) :
                          TAG_WIDTH'(16'h0539);
    localparam logic [TAG_WIDTH-1:0] TAG_SEED =
        (TABLE_ID == 0) ? TAG_WIDTH'(16'h0025) :
        (TABLE_ID == 1) ? TAG_WIDTH'(16'h0067) :
        (TABLE_ID == 2) ? TAG_WIDTH'(16'h00d3) :
        (TABLE_ID == 3) ? TAG_WIDTH'(16'h01a9) :
                          TAG_WIDTH'(16'h0357);

    function automatic logic [INDEX_WIDTH-1:0] rotateIndex(
        input logic [INDEX_WIDTH-1:0] value,
        input integer amount
    );
        integer rotation;
        begin
            rotation = amount % INDEX_WIDTH;
            if (rotation == 0)
                rotateIndex = value;
            else
                rotateIndex = (value << rotation) |
                              (value >> (INDEX_WIDTH-rotation));
        end
    endfunction

    function automatic logic [TAG_WIDTH-1:0] rotateTag(
        input logic [TAG_WIDTH-1:0] value,
        input integer amount
    );
        integer rotation;
        begin
            rotation = amount % TAG_WIDTH;
            if (rotation == 0)
                rotateTag = value;
            else
                rotateTag = (value << rotation) |
                            (value >> (TAG_WIDTH-rotation));
        end
    endfunction

    function automatic logic [INDEX_WIDTH-1:0] foldIndexHistory(
        input tage_history_t history
    );
        logic [INDEX_WIDTH-1:0] result;
        integer bitIndex;
        begin
            result = '0;
            for (bitIndex = 0; bitIndex < HISTORY_LENGTH;
                 bitIndex = bitIndex + 1)
                result[bitIndex % INDEX_WIDTH] =
                    result[bitIndex % INDEX_WIDTH] ^ history[bitIndex];
            foldIndexHistory = result;
        end
    endfunction

    function automatic logic [TAG_WIDTH-1:0] foldTagHistoryA(
        input tage_history_t history
    );
        logic [TAG_WIDTH-1:0] result;
        integer bitIndex;
        begin
            result = '0;
            for (bitIndex = 0; bitIndex < HISTORY_LENGTH;
                 bitIndex = bitIndex + 1)
                result[bitIndex % TAG_WIDTH] =
                    result[bitIndex % TAG_WIDTH] ^ history[bitIndex];
            foldTagHistoryA = result;
        end
    endfunction

    function automatic logic [TAG_WIDTH-2:0] foldTagHistoryB(
        input tage_history_t history
    );
        logic [TAG_WIDTH-2:0] result;
        integer bitIndex;
        begin
            result = '0;
            for (bitIndex = 0; bitIndex < HISTORY_LENGTH;
                 bitIndex = bitIndex + 1)
                result[bitIndex % (TAG_WIDTH-1)] =
                    result[bitIndex % (TAG_WIDTH-1)] ^ history[bitIndex];
            foldTagHistoryB = result;
        end
    endfunction

    function automatic logic [INDEX_WIDTH-1:0] indexCrcStep(
        input logic [INDEX_WIDTH-1:0] currentState,
        input logic inputBit
    );
        logic feedback;
        logic [INDEX_WIDTH-1:0] nextState;
        begin
            feedback = inputBit ^ currentState[INDEX_WIDTH-1];
            nextState = {currentState[INDEX_WIDTH-2:0], 1'b0};
            if (feedback)
                nextState = nextState ^ INDEX_POLYNOMIAL;
            indexCrcStep = nextState;
        end
    endfunction

    function automatic logic [TAG_WIDTH-1:0] tagCrcStep(
        input logic [TAG_WIDTH-1:0] currentState,
        input logic inputBit
    );
        logic feedback;
        logic [TAG_WIDTH-1:0] nextState;
        begin
            feedback = inputBit ^ currentState[TAG_WIDTH-1];
            nextState = {currentState[TAG_WIDTH-2:0], 1'b0};
            if (feedback)
                nextState = nextState ^ TAG_POLYNOMIAL;
            tagCrcStep = nextState;
        end
    endfunction

    function automatic logic [INDEX_WIDTH*PC_HASH_BITS-1:0]
        buildIndexPcMatrix();
        logic [INDEX_WIDTH*PC_HASH_BITS-1:0] matrix;
        logic [INDEX_WIDTH-1:0] state;
        integer inputIndex;
        integer stepIndex;
        integer outputIndex;
        begin
            matrix = '0;
            for (inputIndex = 0; inputIndex < PC_HASH_BITS;
                 inputIndex = inputIndex + 1) begin
                state = '0;
                for (stepIndex = 0; stepIndex < PC_HASH_BITS;
                     stepIndex = stepIndex + 1)
                    state = indexCrcStep(
                        state, stepIndex == inputIndex);
                for (stepIndex = 0;
                     stepIndex < TAGE_PATH_HISTORY_WIDTH;
                     stepIndex = stepIndex + 1)
                    state = indexCrcStep(state, 1'b0);
                for (outputIndex = 0; outputIndex < INDEX_WIDTH;
                     outputIndex = outputIndex + 1)
                    matrix[outputIndex*PC_HASH_BITS + inputIndex] =
                        state[outputIndex];
            end
            buildIndexPcMatrix = matrix;
        end
    endfunction

    function automatic logic
        [INDEX_WIDTH*TAGE_PATH_HISTORY_WIDTH-1:0]
        buildIndexPathMatrix();
        logic [INDEX_WIDTH*TAGE_PATH_HISTORY_WIDTH-1:0] matrix;
        logic [INDEX_WIDTH-1:0] state;
        integer inputIndex;
        integer stepIndex;
        integer pathIndex;
        integer outputIndex;
        begin
            matrix = '0;
            for (inputIndex = 0; inputIndex < TAGE_PATH_HISTORY_WIDTH;
                 inputIndex = inputIndex + 1) begin
                state = '0;
                for (stepIndex = 0; stepIndex < PC_HASH_BITS;
                     stepIndex = stepIndex + 1)
                    state = indexCrcStep(state, 1'b0);
                for (stepIndex = 0;
                     stepIndex < TAGE_PATH_HISTORY_WIDTH;
                     stepIndex = stepIndex + 1) begin
                    pathIndex = ((2*TABLE_ID+1)*stepIndex + TABLE_ID) %
                                TAGE_PATH_HISTORY_WIDTH;
                    state = indexCrcStep(state, pathIndex == inputIndex);
                end
                for (outputIndex = 0; outputIndex < INDEX_WIDTH;
                     outputIndex = outputIndex + 1)
                    matrix[outputIndex*TAGE_PATH_HISTORY_WIDTH +
                           inputIndex] = state[outputIndex];
            end
            buildIndexPathMatrix = matrix;
        end
    endfunction

    function automatic logic [INDEX_WIDTH-1:0] buildIndexFinalSeed();
        logic [INDEX_WIDTH-1:0] state;
        integer stepIndex;
        begin
            state = INDEX_SEED;
            for (stepIndex = 0;
                 stepIndex < PC_HASH_BITS + TAGE_PATH_HISTORY_WIDTH;
                 stepIndex = stepIndex + 1)
                state = indexCrcStep(state, 1'b0);
            buildIndexFinalSeed = state;
        end
    endfunction

    function automatic logic [TAG_WIDTH*PC_HASH_BITS-1:0]
        buildTagPcMatrix();
        logic [TAG_WIDTH*PC_HASH_BITS-1:0] matrix;
        logic [TAG_WIDTH-1:0] state;
        integer inputIndex;
        integer stepIndex;
        integer actualPcIndex;
        integer outputIndex;
        begin
            matrix = '0;
            for (inputIndex = 0; inputIndex < PC_HASH_BITS;
                 inputIndex = inputIndex + 1) begin
                state = '0;
                for (stepIndex = 0; stepIndex < PC_HASH_BITS;
                     stepIndex = stepIndex + 1) begin
                    actualPcIndex = PC_HASH_BITS-1-stepIndex;
                    state = tagCrcStep(
                        state, actualPcIndex == inputIndex);
                end
                for (stepIndex = 0;
                     stepIndex < TAGE_PATH_HISTORY_WIDTH;
                     stepIndex = stepIndex + 1)
                    state = tagCrcStep(state, 1'b0);
                for (outputIndex = 0; outputIndex < TAG_WIDTH;
                     outputIndex = outputIndex + 1)
                    matrix[outputIndex*PC_HASH_BITS + inputIndex] =
                        state[outputIndex];
            end
            buildTagPcMatrix = matrix;
        end
    endfunction

    function automatic logic [TAG_WIDTH*TAGE_PATH_HISTORY_WIDTH-1:0]
        buildTagPathMatrix();
        logic [TAG_WIDTH*TAGE_PATH_HISTORY_WIDTH-1:0] matrix;
        logic [TAG_WIDTH-1:0] state;
        integer inputIndex;
        integer stepIndex;
        integer pathIndex;
        integer outputIndex;
        begin
            matrix = '0;
            for (inputIndex = 0; inputIndex < TAGE_PATH_HISTORY_WIDTH;
                 inputIndex = inputIndex + 1) begin
                state = '0;
                for (stepIndex = 0; stepIndex < PC_HASH_BITS;
                     stepIndex = stepIndex + 1)
                    state = tagCrcStep(state, 1'b0);
                for (stepIndex = 0;
                     stepIndex < TAGE_PATH_HISTORY_WIDTH;
                     stepIndex = stepIndex + 1) begin
                    pathIndex = TAGE_PATH_HISTORY_WIDTH-1-
                        (((2*TABLE_ID+1)*stepIndex + TABLE_ID) %
                         TAGE_PATH_HISTORY_WIDTH);
                    state = tagCrcStep(state, pathIndex == inputIndex);
                end
                for (outputIndex = 0; outputIndex < TAG_WIDTH;
                     outputIndex = outputIndex + 1)
                    matrix[outputIndex*TAGE_PATH_HISTORY_WIDTH +
                           inputIndex] = state[outputIndex];
            end
            buildTagPathMatrix = matrix;
        end
    endfunction

    function automatic logic [TAG_WIDTH-1:0] buildTagFinalSeed();
        logic [TAG_WIDTH-1:0] state;
        integer stepIndex;
        begin
            state = TAG_SEED;
            for (stepIndex = 0;
                 stepIndex < PC_HASH_BITS + TAGE_PATH_HISTORY_WIDTH;
                 stepIndex = stepIndex + 1)
                state = tagCrcStep(state, 1'b0);
            buildTagFinalSeed = state;
        end
    endfunction

    localparam logic [INDEX_WIDTH*PC_HASH_BITS-1:0] INDEX_PC_MATRIX =
        buildIndexPcMatrix();
    localparam logic [INDEX_WIDTH*TAGE_PATH_HISTORY_WIDTH-1:0]
        INDEX_PATH_MATRIX = buildIndexPathMatrix();
    localparam logic [INDEX_WIDTH-1:0] INDEX_FINAL_SEED =
        buildIndexFinalSeed();
    localparam logic [TAG_WIDTH*PC_HASH_BITS-1:0] TAG_PC_MATRIX =
        buildTagPcMatrix();
    localparam logic [TAG_WIDTH*TAGE_PATH_HISTORY_WIDTH-1:0]
        TAG_PATH_MATRIX = buildTagPathMatrix();
    localparam logic [TAG_WIDTH-1:0] TAG_FINAL_SEED =
        buildTagFinalSeed();

    function automatic logic [INDEX_WIDTH-1:0] indexPcPathHash(
        input instruction_addr_t pc,
        input tage_path_history_t pathHistory
    );
        logic [INDEX_WIDTH-1:0] result;
        logic [PC_HASH_BITS-1:0] pcBits;
        logic [PC_HASH_BITS-1:0] pcMask;
        tage_path_history_t pathMask;
        integer outputIndex;
        begin
            pcBits = pc[WORD_SIZE-1:2];
            result = '0;
            for (outputIndex = 0; outputIndex < INDEX_WIDTH;
                 outputIndex = outputIndex + 1) begin
                pcMask = INDEX_PC_MATRIX[
                    outputIndex*PC_HASH_BITS +: PC_HASH_BITS];
                pathMask = INDEX_PATH_MATRIX[
                    outputIndex*TAGE_PATH_HISTORY_WIDTH +:
                    TAGE_PATH_HISTORY_WIDTH];
                result[outputIndex] = INDEX_FINAL_SEED[outputIndex] ^
                    ^(pcBits & pcMask) ^ ^(pathHistory & pathMask);
            end
            indexPcPathHash = result;
        end
    endfunction

    function automatic logic [TAG_WIDTH-1:0] tagPcPathHash(
        input instruction_addr_t pc,
        input tage_path_history_t pathHistory
    );
        logic [TAG_WIDTH-1:0] result;
        logic [PC_HASH_BITS-1:0] pcBits;
        logic [PC_HASH_BITS-1:0] pcMask;
        tage_path_history_t pathMask;
        integer outputIndex;
        begin
            pcBits = pc[WORD_SIZE-1:2];
            result = '0;
            for (outputIndex = 0; outputIndex < TAG_WIDTH;
                 outputIndex = outputIndex + 1) begin
                pcMask = TAG_PC_MATRIX[
                    outputIndex*PC_HASH_BITS +: PC_HASH_BITS];
                pathMask = TAG_PATH_MATRIX[
                    outputIndex*TAGE_PATH_HISTORY_WIDTH +:
                    TAGE_PATH_HISTORY_WIDTH];
                result[outputIndex] = TAG_FINAL_SEED[outputIndex] ^
                    ^(pcBits & pcMask) ^ ^(pathHistory & pathMask);
            end
            tagPcPathHash = result;
        end
    endfunction

    function automatic logic [INDEX_WIDTH-1:0] makeIndex(
        input instruction_addr_t pc,
        input logic [INDEX_WIDTH-1:0] historyFold,
        input tage_path_history_t pathHistory
    );
        begin
            makeIndex = indexPcPathHash(pc, pathHistory) ^
                        rotateIndex(historyFold, TABLE_ID+1);
        end
    endfunction

    function automatic logic [TAG_WIDTH-1:0] makeTag(
        input instruction_addr_t pc,
        input logic [TAG_WIDTH-1:0] historyFoldA,
        input logic [TAG_WIDTH-2:0] historyFoldB,
        input tage_path_history_t pathHistory
    );
        logic [TAG_WIDTH-1:0] expandedFoldB;
        begin
            expandedFoldB = {historyFoldB, 1'b0};
            makeTag = tagPcPathHash(pc, pathHistory) ^
                rotateTag(historyFoldA, TABLE_ID+1) ^
                rotateTag(expandedFoldB, 2*TABLE_ID+1);
        end
    endfunction

    always_comb begin
        queryIndex_o = makeIndex(
            queryPc_i, queryIndexFold_i, queryPathHistory_i);
        queryTag_o = makeTag(
            queryPc_i, queryTagFoldA_i, queryTagFoldB_i,
            queryPathHistory_i);
    end

    always_comb begin
        queryIndex1_o = makeIndex(
            queryPc1_i, queryIndexFold1_i, queryPathHistory1_i);
        queryTag1_o = makeTag(
            queryPc1_i, queryTagFoldA1_i, queryTagFoldB1_i,
            queryPathHistory1_i);
    end

    always_comb begin
        updateIndex_o = makeIndex(
            updatePc_i, foldIndexHistory(updateHistory_i),
            updatePathHistory_i);
        updateTag_o = makeTag(
            updatePc_i, foldTagHistoryA(updateHistory_i),
            foldTagHistoryB(updateHistory_i), updatePathHistory_i);
    end

endmodule
