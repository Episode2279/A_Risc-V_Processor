// TAGE-SC-L-style statistical corrector.
//
// The corrector combines five feature families:
//   * two independently indexed bias tables,
//   * six global-history GEHL tables,
//   * four local-history GEHL tables backed by a per-PC LHT,
//   * three IMLI GEHL tables indexed by the speculative loop iteration,
//   * three dedicated control-path GEHL tables.
//
// All prediction tables are read synchronously. The LHT is a small
// combinationally indexed state array so its value can select the Local GEHL
// SRAMs on the same edge. Retirement metadata preserves the exact Local/IMLI
// context used by the prediction.
module StatisticalCorrector
    import TypesPkg::*;
#(
    parameter int BIAS_TABLE_NUM = SC_BIAS_TABLE_NUM,
    parameter int BIAS_TABLE_ENTRIES = SC_BIAS_TABLE_ENTRIES,
    parameter int GLOBAL_GEHL_TABLE_NUM = SC_GLOBAL_GEHL_TABLE_NUM,
    parameter int GLOBAL_GEHL_TABLE_ENTRIES =
        SC_GLOBAL_GEHL_TABLE_ENTRIES,
    parameter int LOCAL_HISTORY_ENTRIES = SC_LOCAL_HISTORY_ENTRIES,
    parameter int LOCAL_GEHL_TABLE_NUM = SC_LOCAL_GEHL_TABLE_NUM,
    parameter int LOCAL_GEHL_TABLE_ENTRIES = SC_LOCAL_GEHL_TABLE_ENTRIES,
    parameter int IMLI_GEHL_TABLE_NUM = SC_IMLI_GEHL_TABLE_NUM,
    parameter int IMLI_GEHL_TABLE_ENTRIES = SC_IMLI_GEHL_TABLE_ENTRIES,
    parameter int PATH_GEHL_TABLE_NUM = SC_PATH_GEHL_TABLE_NUM,
    parameter int PATH_GEHL_TABLE_ENTRIES = SC_PATH_GEHL_TABLE_ENTRIES,
    parameter int THRESHOLD_TABLE_ENTRIES = SC_THRESHOLD_TABLE_ENTRIES,
    parameter int COUNTER_WIDTH = SC_COUNTER_WIDTH,
    parameter int THRESHOLD_COUNTER_WIDTH = SC_THRESHOLD_COUNTER_WIDTH,
    parameter int SCORE_WIDTH = SC_SCORE_WIDTH,
    parameter int GLOBAL_FOLD_WIDTH =
        $clog2(GLOBAL_GEHL_TABLE_ENTRIES),
    parameter int LOW_CONFIDENCE_THRESHOLD = 23,
    parameter int WEAK_BASE_WEIGHT = 20,
    parameter int STRONG_BASE_WEIGHT = 62,
    parameter int BIAS_INDEX_WIDTH = $clog2(BIAS_TABLE_ENTRIES),
    parameter int GLOBAL_INDEX_WIDTH =
        $clog2(GLOBAL_GEHL_TABLE_ENTRIES),
    parameter int LOCAL_HISTORY_INDEX_WIDTH =
        $clog2(LOCAL_HISTORY_ENTRIES),
    parameter int LOCAL_INDEX_WIDTH = $clog2(LOCAL_GEHL_TABLE_ENTRIES),
    parameter int IMLI_INDEX_WIDTH = $clog2(IMLI_GEHL_TABLE_ENTRIES),
    parameter int PATH_INDEX_WIDTH = $clog2(PATH_GEHL_TABLE_ENTRIES),
    parameter int THRESHOLD_INDEX_WIDTH =
        $clog2(THRESHOLD_TABLE_ENTRIES)
)
(
    input  logic clk,
    input  logic rst,

    input  logic queryValid_i,
    input  instruction_addr_t queryPc_i,
    input  instruction_addr_t queryPc1_i,
    input  logic [GLOBAL_FOLD_WIDTH-1:0]
        queryGlobalFold_i [GLOBAL_GEHL_TABLE_NUM],
    input  logic [GLOBAL_FOLD_WIDTH-1:0]
        queryGlobalFold1_i [GLOBAL_GEHL_TABLE_NUM],
    input  tage_path_history_t queryPath_i,
    input  tage_path_history_t queryPath1_i,
    input  sc_imli_t queryImli_i,
    input  sc_imli_t queryImli1_i,

    input  logic basePrediction_i,
    input  logic baseStrong_i,
    input  logic basePrediction1_i,
    input  logic baseStrong1_i,

    output logic responseValid_o,
    output logic predictTaken_o,
    output logic predictTaken1_o,
    output logic lowConfidence_o,
    output logic lowConfidence1_o,
    output sc_score_t score_o,
    output sc_score_t score1_o,
    output logic [SC_FEATURE_FAMILY_NUM-1:0] familyTaken_o,
    output logic [SC_FEATURE_FAMILY_NUM-1:0] familyTaken1_o,
    output logic [SC_FEATURE_FAMILY_NUM-1:0] familyValid_o,
    output logic [SC_FEATURE_FAMILY_NUM-1:0] familyValid1_o,
    output sc_local_history_t localHistory_o,
    output sc_local_history_t localHistory1_o,

    input  logic updateValid_i,
    input  instruction_addr_t updatePc_i,
    input  tage_history_t updateHistory_i,
    input  tage_path_history_t updatePath_i,
    input  sc_local_history_t updateLocalHistory_i,
    input  sc_imli_t updateImli_i,
    input  logic updateTaken_i,
    input  logic updateBasePrediction_i,
    input  logic updateBaseStrong_i,
    input  logic updateFinalPrediction_i,
    input  sc_score_t updateScore_i,
    input  logic updateLowConfidence_i
);

    localparam logic signed [THRESHOLD_COUNTER_WIDTH-1:0]
        THRESHOLD_MAX =
        {1'b0, {(THRESHOLD_COUNTER_WIDTH-1){1'b1}}};
    localparam logic signed [THRESHOLD_COUNTER_WIDTH-1:0]
        THRESHOLD_MIN =
        {1'b1, {(THRESHOLD_COUNTER_WIDTH-1){1'b0}}};
    localparam int LOGICAL_COUNTER_STORAGE_BITS =
        BIAS_TABLE_NUM * BIAS_TABLE_ENTRIES * COUNTER_WIDTH +
        GLOBAL_GEHL_TABLE_NUM * GLOBAL_GEHL_TABLE_ENTRIES *
            COUNTER_WIDTH +
        LOCAL_GEHL_TABLE_NUM * LOCAL_GEHL_TABLE_ENTRIES * COUNTER_WIDTH +
        IMLI_GEHL_TABLE_NUM * IMLI_GEHL_TABLE_ENTRIES * COUNTER_WIDTH +
        PATH_GEHL_TABLE_NUM * PATH_GEHL_TABLE_ENTRIES * COUNTER_WIDTH;

    sc_local_history_t localHistoryTable [LOCAL_HISTORY_ENTRIES];
    logic signed [THRESHOLD_COUNTER_WIDTH-1:0]
        thresholdTable [THRESHOLD_TABLE_ENTRIES];

    logic [BIAS_TABLE_NUM-1:0][BIAS_INDEX_WIDTH-1:0] queryBiasIndex;
    logic [BIAS_TABLE_NUM-1:0][BIAS_INDEX_WIDTH-1:0] queryBiasIndex1;
    logic [BIAS_TABLE_NUM-1:0][BIAS_INDEX_WIDTH-1:0] updateBiasIndex;
    logic [LOCAL_HISTORY_INDEX_WIDTH-1:0] queryLocalHistoryIndex;
    logic [LOCAL_HISTORY_INDEX_WIDTH-1:0] queryLocalHistoryIndex1;
    logic [LOCAL_HISTORY_INDEX_WIDTH-1:0] updateLocalHistoryIndex;
    logic [THRESHOLD_INDEX_WIDTH-1:0] queryThresholdIndex;
    logic [THRESHOLD_INDEX_WIDTH-1:0] queryThresholdIndex1;
    logic [THRESHOLD_INDEX_WIDTH-1:0] updateThresholdIndex;
    logic [GLOBAL_GEHL_TABLE_NUM-1:0][GLOBAL_INDEX_WIDTH-1:0]
        queryGlobalIndex;
    logic [GLOBAL_GEHL_TABLE_NUM-1:0][GLOBAL_INDEX_WIDTH-1:0]
        queryGlobalIndex1;
    logic [GLOBAL_GEHL_TABLE_NUM-1:0][GLOBAL_INDEX_WIDTH-1:0]
        updateGlobalIndex;
    logic [LOCAL_GEHL_TABLE_NUM-1:0][LOCAL_INDEX_WIDTH-1:0]
        queryLocalIndex;
    logic [LOCAL_GEHL_TABLE_NUM-1:0][LOCAL_INDEX_WIDTH-1:0]
        queryLocalIndex1;
    logic [LOCAL_GEHL_TABLE_NUM-1:0][LOCAL_INDEX_WIDTH-1:0]
        updateLocalIndex;
    logic [IMLI_GEHL_TABLE_NUM-1:0][IMLI_INDEX_WIDTH-1:0]
        queryImliIndex;
    logic [IMLI_GEHL_TABLE_NUM-1:0][IMLI_INDEX_WIDTH-1:0]
        queryImliIndex1;
    logic [IMLI_GEHL_TABLE_NUM-1:0][IMLI_INDEX_WIDTH-1:0]
        updateImliIndex;
    logic [PATH_GEHL_TABLE_NUM-1:0][PATH_INDEX_WIDTH-1:0]
        queryPathIndex;
    logic [PATH_GEHL_TABLE_NUM-1:0][PATH_INDEX_WIDTH-1:0]
        queryPathIndex1;
    logic [PATH_GEHL_TABLE_NUM-1:0][PATH_INDEX_WIDTH-1:0]
        updatePathIndex;
    logic [GLOBAL_GEHL_TABLE_NUM-1:0][GLOBAL_FOLD_WIDTH-1:0]
        updateGlobalFold;

    sc_local_history_t queryLocalHistory;
    sc_local_history_t queryLocalHistory1;
    sc_local_history_t advancedUpdateLocalHistory;

    logic signed [COUNTER_WIDTH-1:0]
        responseBias0, responseBias1;
    logic signed [COUNTER_WIDTH-1:0]
        responseBiasLane1_0, responseBiasLane1_1;
    logic signed [COUNTER_WIDTH-1:0]
        responseGlobal0, responseGlobal1, responseGlobal2, responseGlobal3,
        responseGlobal4, responseGlobal5;
    logic signed [COUNTER_WIDTH-1:0]
        responseGlobalLane1_0, responseGlobalLane1_1,
        responseGlobalLane1_2, responseGlobalLane1_3,
        responseGlobalLane1_4, responseGlobalLane1_5;
    logic signed [COUNTER_WIDTH-1:0]
        responseLocal0, responseLocal1, responseLocal2, responseLocal3;
    logic signed [COUNTER_WIDTH-1:0]
        responseLocalLane1_0, responseLocalLane1_1,
        responseLocalLane1_2, responseLocalLane1_3;
    logic signed [COUNTER_WIDTH-1:0]
        responseImli0, responseImli1, responseImli2;
    logic signed [COUNTER_WIDTH-1:0]
        responseImliLane1_0, responseImliLane1_1,
        responseImliLane1_2;
    logic signed [COUNTER_WIDTH-1:0]
        responsePath0, responsePath1, responsePath2;
    logic signed [COUNTER_WIDTH-1:0]
        responsePathLane1_0, responsePathLane1_1,
        responsePathLane1_2;
    logic signed [THRESHOLD_COUNTER_WIDTH-1:0]
        responseThresholdCounter;
    logic signed [THRESHOLD_COUNTER_WIDTH-1:0]
        responseThresholdCounter1;

    logic signed [THRESHOLD_COUNTER_WIDTH-1:0]
        updatedThresholdCounter;
    logic trainUpdate;

    initial begin
        localHistoryTable = '{default:'0};
        thresholdTable = '{default:'0};
        if ((BIAS_TABLE_NUM != 2) ||
            (GLOBAL_GEHL_TABLE_NUM != 6) ||
            (LOCAL_GEHL_TABLE_NUM != 4) ||
            (IMLI_GEHL_TABLE_NUM != 3) ||
            (PATH_GEHL_TABLE_NUM != 3))
            $fatal(1,
                "SC bank wiring requires 2 Bias/6 Global/4 Local/3 IMLI/3 Path tables");
        if (GLOBAL_FOLD_WIDTH != GLOBAL_INDEX_WIDTH)
            $fatal(1, "SC global fold width must match its GEHL index");
        if (LOGICAL_COUNTER_STORAGE_BITS !=
            BPU_SC_COUNTER_STORAGE_BITS)
            $fatal(1, "SC counter state disagrees with BPU budget");
        if (BPU_ENFORCE_CBP_STORAGE_LIMIT &&
            (BPU_TOTAL_STORAGE_BITS > BPU_CBP_STORAGE_LIMIT_BITS))
            $fatal(1, "BPU logical state exceeds the CBP 16 KiB budget");
    end

    function automatic logic [GLOBAL_INDEX_WIDTH-1:0] rotateGlobal(
        input logic [GLOBAL_INDEX_WIDTH-1:0] value,
        input integer amount
    );
        integer rotation;
        begin
            rotation = amount % GLOBAL_INDEX_WIDTH;
            if (rotation == 0)
                rotateGlobal = value;
            else
                rotateGlobal = (value << rotation) |
                    (value >> (GLOBAL_INDEX_WIDTH-rotation));
        end
    endfunction

    function automatic logic [LOCAL_INDEX_WIDTH-1:0] rotateLocal(
        input logic [LOCAL_INDEX_WIDTH-1:0] value,
        input integer amount
    );
        integer rotation;
        begin
            rotation = amount % LOCAL_INDEX_WIDTH;
            if (rotation == 0)
                rotateLocal = value;
            else
                rotateLocal = (value << rotation) |
                    (value >> (LOCAL_INDEX_WIDTH-rotation));
        end
    endfunction

    function automatic logic [IMLI_INDEX_WIDTH-1:0] rotateImli(
        input logic [IMLI_INDEX_WIDTH-1:0] value,
        input integer amount
    );
        integer rotation;
        begin
            rotation = amount % IMLI_INDEX_WIDTH;
            if (rotation == 0)
                rotateImli = value;
            else
                rotateImli = (value << rotation) |
                    (value >> (IMLI_INDEX_WIDTH-rotation));
        end
    endfunction

    function automatic logic [PATH_INDEX_WIDTH-1:0] rotatePath(
        input logic [PATH_INDEX_WIDTH-1:0] value,
        input integer amount
    );
        integer rotation;
        begin
            rotation = amount % PATH_INDEX_WIDTH;
            if (rotation == 0)
                rotatePath = value;
            else
                rotatePath = (value << rotation) |
                    (value >> (PATH_INDEX_WIDTH-rotation));
        end
    endfunction

    function automatic logic [BIAS_INDEX_WIDTH-1:0] hashBias(
        input instruction_addr_t pc,
        input logic [GLOBAL_FOLD_WIDTH-1:0] shortHistory,
        input logic basePrediction,
        input logic baseStrong,
        input integer tableId
    );
        logic [BIAS_INDEX_WIDTH-1:0] pcHash;
        begin
            pcHash =
                BIAS_INDEX_WIDTH'(pc >> 2) ^
                BIAS_INDEX_WIDTH'(pc >> (2 + BIAS_INDEX_WIDTH)) ^
                BIAS_INDEX_WIDTH'(pc >> (2 + 2*BIAS_INDEX_WIDTH));
            if (tableId == 0)
                hashBias = pcHash;
            else
                hashBias =
                    rotateGlobal(BIAS_INDEX_WIDTH'(pcHash), 3) ^
                    BIAS_INDEX_WIDTH'(shortHistory) ^
                    (BIAS_INDEX_WIDTH'(basePrediction) <<
                     (BIAS_INDEX_WIDTH-1)) ^
                    (BIAS_INDEX_WIDTH'(baseStrong) <<
                     (BIAS_INDEX_WIDTH-2)) ^
                    BIAS_INDEX_WIDTH'(8'h5d);
        end
    endfunction

    function automatic logic [LOCAL_HISTORY_INDEX_WIDTH-1:0] hashLocalPc(
        input instruction_addr_t pc
    );
        begin
            hashLocalPc =
                LOCAL_HISTORY_INDEX_WIDTH'(pc >> 2) ^
                LOCAL_HISTORY_INDEX_WIDTH'(
                    pc >> (2 + LOCAL_HISTORY_INDEX_WIDTH)) ^
                LOCAL_HISTORY_INDEX_WIDTH'(
                    pc >> (2 + 2*LOCAL_HISTORY_INDEX_WIDTH));
        end
    endfunction

    function automatic logic [THRESHOLD_INDEX_WIDTH-1:0] hashThreshold(
        input instruction_addr_t pc,
        input logic basePrediction,
        input logic baseStrong
    );
        begin
            hashThreshold =
                THRESHOLD_INDEX_WIDTH'(pc >> 2) ^
                THRESHOLD_INDEX_WIDTH'(
                    pc >> (2 + THRESHOLD_INDEX_WIDTH)) ^
                THRESHOLD_INDEX_WIDTH'(
                    pc >> (2 + 2*THRESHOLD_INDEX_WIDTH)) ^
                THRESHOLD_INDEX_WIDTH'(
                    pc >> (2 + 3*THRESHOLD_INDEX_WIDTH)) ^
                (THRESHOLD_INDEX_WIDTH'(basePrediction) <<
                 (THRESHOLD_INDEX_WIDTH-1)) ^
                (THRESHOLD_INDEX_WIDTH'(baseStrong) <<
                 (THRESHOLD_INDEX_WIDTH-2));
        end
    endfunction

    function automatic logic [GLOBAL_INDEX_WIDTH-1:0] hashGlobal(
        input instruction_addr_t pc,
        input logic [GLOBAL_FOLD_WIDTH-1:0] historyFold,
        input tage_path_history_t path,
        input integer tableId
    );
        logic [GLOBAL_INDEX_WIDTH-1:0] pcFold;
        logic [GLOBAL_INDEX_WIDTH-1:0] pathFold;
        begin
            pcFold =
                GLOBAL_INDEX_WIDTH'(pc >> 2) ^
                GLOBAL_INDEX_WIDTH'(pc >> (2 + GLOBAL_INDEX_WIDTH)) ^
                GLOBAL_INDEX_WIDTH'(pc >> (2 + 2*GLOBAL_INDEX_WIDTH));
            pathFold =
                GLOBAL_INDEX_WIDTH'(path) ^
                GLOBAL_INDEX_WIDTH'(path >> GLOBAL_INDEX_WIDTH);
            hashGlobal =
                rotateGlobal(pcFold, 2*tableId+1) ^
                rotateGlobal(historyFold, 3*tableId+2) ^
                ((tableId >= 3) ? rotateGlobal(pathFold, tableId+1) : '0) ^
                GLOBAL_INDEX_WIDTH'((tableId*53) + 23);
        end
    endfunction

    function automatic logic [LOCAL_INDEX_WIDTH-1:0] hashLocal(
        input instruction_addr_t pc,
        input sc_local_history_t history,
        input tage_path_history_t path,
        input integer tableId
    );
        logic [LOCAL_INDEX_WIDTH-1:0] pcFold;
        logic [LOCAL_INDEX_WIDTH-1:0] historyFold;
        logic [LOCAL_INDEX_WIDTH-1:0] pathFold;
        sc_local_history_t selectedHistory;
        begin
            pcFold =
                LOCAL_INDEX_WIDTH'(pc >> 2) ^
                LOCAL_INDEX_WIDTH'(pc >> (2 + LOCAL_INDEX_WIDTH)) ^
                LOCAL_INDEX_WIDTH'(pc >> (2 + 2*LOCAL_INDEX_WIDTH));
            case (tableId)
                0: selectedHistory =
                    history & sc_local_history_t'(12'h007);
                1: selectedHistory =
                    history & sc_local_history_t'(12'h03f);
                2: selectedHistory =
                    history & sc_local_history_t'(12'h1ff);
                default: selectedHistory = history;
            endcase
            historyFold =
                LOCAL_INDEX_WIDTH'(selectedHistory) ^
                LOCAL_INDEX_WIDTH'(selectedHistory >> LOCAL_INDEX_WIDTH);
            pathFold =
                LOCAL_INDEX_WIDTH'(path) ^
                LOCAL_INDEX_WIDTH'(path >> LOCAL_INDEX_WIDTH);
            hashLocal =
                rotateLocal(pcFold, tableId+1) ^
                rotateLocal(historyFold, 2*tableId+3) ^
                ((tableId >= 2) ? rotateLocal(pathFold, tableId+2) : '0) ^
                LOCAL_INDEX_WIDTH'((tableId*113) + 41);
        end
    endfunction

    function automatic logic [IMLI_INDEX_WIDTH-1:0] hashImli(
        input instruction_addr_t pc,
        input sc_imli_t imli,
        input logic [GLOBAL_FOLD_WIDTH-1:0] globalFold,
        input tage_path_history_t path,
        input integer tableId
    );
        logic [IMLI_INDEX_WIDTH-1:0] pcFold;
        logic [IMLI_INDEX_WIDTH-1:0] imliFold;
        logic [IMLI_INDEX_WIDTH-1:0] pathFold;
        begin
            pcFold =
                IMLI_INDEX_WIDTH'(pc >> 2) ^
                IMLI_INDEX_WIDTH'(pc >> (2 + IMLI_INDEX_WIDTH)) ^
                IMLI_INDEX_WIDTH'(pc >> (2 + 2*IMLI_INDEX_WIDTH));
            imliFold =
                IMLI_INDEX_WIDTH'(imli) ^
                IMLI_INDEX_WIDTH'(imli >> IMLI_INDEX_WIDTH);
            pathFold =
                IMLI_INDEX_WIDTH'(path) ^
                IMLI_INDEX_WIDTH'(path >> IMLI_INDEX_WIDTH);
            hashImli =
                rotateImli(pcFold, 2*tableId+1) ^
                rotateImli(imliFold, tableId+2) ^
                ((tableId >= 1) ?
                 rotateImli(IMLI_INDEX_WIDTH'(globalFold), tableId+3) :
                 '0) ^
                ((tableId >= 2) ? rotateImli(pathFold, tableId+1) : '0) ^
                IMLI_INDEX_WIDTH'((tableId*91) + 51);
        end
    endfunction

    function automatic logic [PATH_INDEX_WIDTH-1:0] hashPath(
        input instruction_addr_t pc,
        input tage_path_history_t path,
        input integer tableId
    );
        logic [PATH_INDEX_WIDTH-1:0] pcFold;
        logic [PATH_INDEX_WIDTH-1:0] selectedPath;
        begin
            pcFold =
                PATH_INDEX_WIDTH'(pc >> 2) ^
                PATH_INDEX_WIDTH'(pc >> (2 + PATH_INDEX_WIDTH)) ^
                PATH_INDEX_WIDTH'(pc >> (2 + 2*PATH_INDEX_WIDTH));
            case (tableId)
                0: selectedPath =
                    PATH_INDEX_WIDTH'(path & tage_path_history_t'(16'h000f));
                1: selectedPath =
                    PATH_INDEX_WIDTH'(path & tage_path_history_t'(16'h00ff));
                default: selectedPath =
                    PATH_INDEX_WIDTH'(path) ^
                    PATH_INDEX_WIDTH'(path >> PATH_INDEX_WIDTH);
            endcase
            hashPath =
                rotatePath(pcFold, 2*tableId+1) ^
                rotatePath(selectedPath, 3*tableId+2) ^
                PATH_INDEX_WIDTH'((tableId*73) + 29);
        end
    endfunction

    function automatic logic [GLOBAL_FOLD_WIDTH-1:0] fold64(
        input logic [63:0] history
    );
        fold64 =
            GLOBAL_FOLD_WIDTH'(history) ^
            GLOBAL_FOLD_WIDTH'(history >> 8) ^
            GLOBAL_FOLD_WIDTH'(history >> 16) ^
            GLOBAL_FOLD_WIDTH'(history >> 24) ^
            GLOBAL_FOLD_WIDTH'(history >> 32) ^
            GLOBAL_FOLD_WIDTH'(history >> 40) ^
            GLOBAL_FOLD_WIDTH'(history >> 48) ^
            GLOBAL_FOLD_WIDTH'(history >> 56);
    endfunction

    function automatic logic [GLOBAL_FOLD_WIDTH-1:0] rebuildGlobalFold(
        input tage_history_t history,
        input integer tableId
    );
        begin
            case (tableId)
                0: rebuildGlobalFold =
                    GLOBAL_FOLD_WIDTH'(history & tage_history_t'(3));
                1: rebuildGlobalFold =
                    GLOBAL_FOLD_WIDTH'(history & tage_history_t'(63));
                2: rebuildGlobalFold =
                    GLOBAL_FOLD_WIDTH'(history) ^
                    GLOBAL_FOLD_WIDTH'(history >> 8);
                3: rebuildGlobalFold =
                    GLOBAL_FOLD_WIDTH'(history) ^
                    GLOBAL_FOLD_WIDTH'(history >> 8) ^
                    GLOBAL_FOLD_WIDTH'(history >> 16);
                4: rebuildGlobalFold =
                    GLOBAL_FOLD_WIDTH'(history) ^
                    GLOBAL_FOLD_WIDTH'(history >> 8) ^
                    GLOBAL_FOLD_WIDTH'(history >> 16) ^
                    GLOBAL_FOLD_WIDTH'(history >> 24) ^
                    GLOBAL_FOLD_WIDTH'(history >> 32) ^
                    GLOBAL_FOLD_WIDTH'(history >> 40);
                default: rebuildGlobalFold =
                    fold64(history[63:0]) ^
                    fold64(history[127:64]) ^
                    fold64(history[191:128]);
            endcase
        end
    endfunction

    function automatic integer signed counterAsInteger(
        input logic signed [COUNTER_WIDTH-1:0] value
    );
        counterAsInteger =
            {{(32-COUNTER_WIDTH){value[COUNTER_WIDTH-1]}}, value};
    endfunction

    function automatic integer signed thresholdAsInteger(
        input logic signed [THRESHOLD_COUNTER_WIDTH-1:0] value
    );
        thresholdAsInteger =
            {{(32-THRESHOLD_COUNTER_WIDTH){
                value[THRESHOLD_COUNTER_WIDTH-1]}}, value};
    endfunction

    function automatic integer absoluteScore(input sc_score_t value);
        integer signed extendedValue;
        begin
            extendedValue =
                {{(32-SC_SCORE_WIDTH){value[SC_SCORE_WIDTH-1]}}, value};
            absoluteScore = (extendedValue < 0) ?
                -extendedValue : extendedValue;
        end
    endfunction

    always_comb begin : buildIndices
        trainUpdate = updateValid_i &&
            ((updateFinalPrediction_i != updateTaken_i) ||
             updateLowConfidence_i);

        queryBiasIndex[0] = hashBias(
            queryPc_i, queryGlobalFold_i[0],
            basePrediction_i, baseStrong_i, 0);
        queryBiasIndex[1] = hashBias(
            queryPc_i, queryGlobalFold_i[0],
            basePrediction_i, baseStrong_i, 1);
        queryBiasIndex1[0] = hashBias(
            queryPc1_i, queryGlobalFold1_i[0],
            basePrediction1_i, baseStrong1_i, 0);
        queryBiasIndex1[1] = hashBias(
            queryPc1_i, queryGlobalFold1_i[0],
            basePrediction1_i, baseStrong1_i, 1);
        updateBiasIndex[0] = hashBias(
            updatePc_i, rebuildGlobalFold(updateHistory_i, 0),
            updateBasePrediction_i, updateBaseStrong_i, 0);
        updateBiasIndex[1] = hashBias(
            updatePc_i, rebuildGlobalFold(updateHistory_i, 0),
            updateBasePrediction_i, updateBaseStrong_i, 1);
        queryLocalHistoryIndex = hashLocalPc(queryPc_i);
        queryLocalHistoryIndex1 = hashLocalPc(queryPc1_i);
        updateLocalHistoryIndex = hashLocalPc(updatePc_i);
        queryThresholdIndex = hashThreshold(
            queryPc_i, basePrediction_i, baseStrong_i);
        queryThresholdIndex1 = hashThreshold(
            queryPc1_i, basePrediction1_i, baseStrong1_i);
        updateThresholdIndex = hashThreshold(
            updatePc_i, updateBasePrediction_i, updateBaseStrong_i);

        advancedUpdateLocalHistory = {
            localHistoryTable[updateLocalHistoryIndex]
                [SC_LOCAL_HISTORY_WIDTH-2:0],
            updateTaken_i};
        queryLocalHistory =
            localHistoryTable[queryLocalHistoryIndex];
        queryLocalHistory1 =
            localHistoryTable[queryLocalHistoryIndex1];
        if (updateValid_i &&
            (updateLocalHistoryIndex == queryLocalHistoryIndex))
            queryLocalHistory = advancedUpdateLocalHistory;
        if (updateValid_i &&
            (updateLocalHistoryIndex == queryLocalHistoryIndex1))
            queryLocalHistory1 = advancedUpdateLocalHistory;

        updatedThresholdCounter = thresholdTable[updateThresholdIndex];
        if ((updateFinalPrediction_i != updateBasePrediction_i) &&
            (updateFinalPrediction_i != updateTaken_i) &&
            updateBaseStrong_i &&
            !updateLowConfidence_i &&
            (absoluteScore(updateScore_i) >
             LOW_CONFIDENCE_THRESHOLD) &&
            (updatedThresholdCounter != THRESHOLD_MAX))
            updatedThresholdCounter =
                updatedThresholdCounter + THRESHOLD_COUNTER_WIDTH'(1);
        else if ((updateFinalPrediction_i != updateBasePrediction_i) &&
                 (updateFinalPrediction_i == updateTaken_i) &&
                 updateLowConfidence_i &&
                 (updatedThresholdCounter != THRESHOLD_MIN))
            updatedThresholdCounter =
                updatedThresholdCounter - THRESHOLD_COUNTER_WIDTH'(1);

`define SC_BUILD_GLOBAL_INDEX(TABLE_ID) \
        updateGlobalFold[TABLE_ID] = \
            rebuildGlobalFold(updateHistory_i, TABLE_ID); \
        queryGlobalIndex[TABLE_ID] = hashGlobal( \
            queryPc_i, queryGlobalFold_i[TABLE_ID], \
            queryPath_i, TABLE_ID); \
        queryGlobalIndex1[TABLE_ID] = hashGlobal( \
            queryPc1_i, queryGlobalFold1_i[TABLE_ID], \
            queryPath1_i, TABLE_ID); \
        updateGlobalIndex[TABLE_ID] = hashGlobal( \
            updatePc_i, updateGlobalFold[TABLE_ID], \
            updatePath_i, TABLE_ID);

        `SC_BUILD_GLOBAL_INDEX(0)
        `SC_BUILD_GLOBAL_INDEX(1)
        `SC_BUILD_GLOBAL_INDEX(2)
        `SC_BUILD_GLOBAL_INDEX(3)
        `SC_BUILD_GLOBAL_INDEX(4)
        `SC_BUILD_GLOBAL_INDEX(5)

`define SC_BUILD_LOCAL_INDEX(TABLE_ID) \
        queryLocalIndex[TABLE_ID] = hashLocal( \
            queryPc_i, queryLocalHistory, queryPath_i, TABLE_ID); \
        queryLocalIndex1[TABLE_ID] = hashLocal( \
            queryPc1_i, queryLocalHistory1, queryPath1_i, TABLE_ID); \
        updateLocalIndex[TABLE_ID] = hashLocal( \
            updatePc_i, updateLocalHistory_i, updatePath_i, TABLE_ID);

        `SC_BUILD_LOCAL_INDEX(0)
        `SC_BUILD_LOCAL_INDEX(1)
        `SC_BUILD_LOCAL_INDEX(2)
        `SC_BUILD_LOCAL_INDEX(3)

`define SC_BUILD_IMLI_INDEX(TABLE_ID, FOLD_ID) \
        queryImliIndex[TABLE_ID] = hashImli( \
            queryPc_i, queryImli_i, queryGlobalFold_i[FOLD_ID], \
            queryPath_i, TABLE_ID); \
        queryImliIndex1[TABLE_ID] = hashImli( \
            queryPc1_i, queryImli1_i, queryGlobalFold1_i[FOLD_ID], \
            queryPath1_i, TABLE_ID); \
        updateImliIndex[TABLE_ID] = hashImli( \
            updatePc_i, updateImli_i, updateGlobalFold[FOLD_ID], \
            updatePath_i, TABLE_ID);

        `SC_BUILD_IMLI_INDEX(0, 0)
        `SC_BUILD_IMLI_INDEX(1, 1)
        `SC_BUILD_IMLI_INDEX(2, 4)

`define SC_BUILD_PATH_INDEX(TABLE_ID) \
        queryPathIndex[TABLE_ID] = hashPath( \
            queryPc_i, queryPath_i, TABLE_ID); \
        queryPathIndex1[TABLE_ID] = hashPath( \
            queryPc1_i, queryPath1_i, TABLE_ID); \
        updatePathIndex[TABLE_ID] = hashPath( \
            updatePc_i, updatePath_i, TABLE_ID);

        `SC_BUILD_PATH_INDEX(0)
        `SC_BUILD_PATH_INDEX(1)
        `SC_BUILD_PATH_INDEX(2)
    end

`undef SC_BUILD_GLOBAL_INDEX
`undef SC_BUILD_LOCAL_INDEX
`undef SC_BUILD_IMLI_INDEX
`undef SC_BUILD_PATH_INDEX

    always_ff @(posedge clk or negedge rst) begin : auxiliaryState
        if (!rst) begin
            responseValid_o <= 1'b0;
            responseThresholdCounter <= '0;
            responseThresholdCounter1 <= '0;
            localHistory_o <= '0;
            localHistory1_o <= '0;
        end else begin
            responseValid_o <= queryValid_i;
            localHistory_o <= queryLocalHistory;
            localHistory1_o <= queryLocalHistory1;

            responseThresholdCounter <=
                (updateValid_i &&
                 updateThresholdIndex == queryThresholdIndex) ?
                updatedThresholdCounter :
                thresholdTable[queryThresholdIndex];
            responseThresholdCounter1 <=
                (updateValid_i &&
                 updateThresholdIndex == queryThresholdIndex1) ?
                updatedThresholdCounter :
                thresholdTable[queryThresholdIndex1];
            if (updateValid_i)
                thresholdTable[updateThresholdIndex] <=
                    updatedThresholdCounter;
            if (updateValid_i)
                localHistoryTable[updateLocalHistoryIndex] <=
                    advancedUpdateLocalHistory;
        end
    end

`define SC_COUNTER_BANK(INSTANCE, ENTRIES_VALUE, QUERY_ARRAY, QUERY1_ARRAY, RESPONSE0, RESPONSE1, UPDATE_ARRAY, TABLE_ID) \
    ScSignedCounterTable #( \
        .ENTRIES(ENTRIES_VALUE), .COUNTER_WIDTH(COUNTER_WIDTH) \
    ) INSTANCE ( \
        .clk(clk), .rst(rst), .queryIndex_i(QUERY_ARRAY[TABLE_ID]), \
        .queryIndex1_i(QUERY1_ARRAY[TABLE_ID]), \
        .responseCounter_o(RESPONSE0), \
        .responseCounter1_o(RESPONSE1), \
        .updateValid_i(trainUpdate), \
        .updateIndex_i(UPDATE_ARRAY[TABLE_ID]), \
        .updateTaken_i(updateTaken_i) \
    );

    `SC_COUNTER_BANK(biasCounter0, BIAS_TABLE_ENTRIES, queryBiasIndex, queryBiasIndex1, responseBias0, responseBiasLane1_0, updateBiasIndex, 0)
    `SC_COUNTER_BANK(biasCounter1, BIAS_TABLE_ENTRIES, queryBiasIndex, queryBiasIndex1, responseBias1, responseBiasLane1_1, updateBiasIndex, 1)

    `SC_COUNTER_BANK(globalCounter0, GLOBAL_GEHL_TABLE_ENTRIES, queryGlobalIndex, queryGlobalIndex1, responseGlobal0, responseGlobalLane1_0, updateGlobalIndex, 0)
    `SC_COUNTER_BANK(globalCounter1, GLOBAL_GEHL_TABLE_ENTRIES, queryGlobalIndex, queryGlobalIndex1, responseGlobal1, responseGlobalLane1_1, updateGlobalIndex, 1)
    `SC_COUNTER_BANK(globalCounter2, GLOBAL_GEHL_TABLE_ENTRIES, queryGlobalIndex, queryGlobalIndex1, responseGlobal2, responseGlobalLane1_2, updateGlobalIndex, 2)
    `SC_COUNTER_BANK(globalCounter3, GLOBAL_GEHL_TABLE_ENTRIES, queryGlobalIndex, queryGlobalIndex1, responseGlobal3, responseGlobalLane1_3, updateGlobalIndex, 3)
    `SC_COUNTER_BANK(globalCounter4, GLOBAL_GEHL_TABLE_ENTRIES, queryGlobalIndex, queryGlobalIndex1, responseGlobal4, responseGlobalLane1_4, updateGlobalIndex, 4)
    `SC_COUNTER_BANK(globalCounter5, GLOBAL_GEHL_TABLE_ENTRIES, queryGlobalIndex, queryGlobalIndex1, responseGlobal5, responseGlobalLane1_5, updateGlobalIndex, 5)
    `SC_COUNTER_BANK(localCounter0, LOCAL_GEHL_TABLE_ENTRIES, queryLocalIndex, queryLocalIndex1, responseLocal0, responseLocalLane1_0, updateLocalIndex, 0)
    `SC_COUNTER_BANK(localCounter1, LOCAL_GEHL_TABLE_ENTRIES, queryLocalIndex, queryLocalIndex1, responseLocal1, responseLocalLane1_1, updateLocalIndex, 1)
    `SC_COUNTER_BANK(localCounter2, LOCAL_GEHL_TABLE_ENTRIES, queryLocalIndex, queryLocalIndex1, responseLocal2, responseLocalLane1_2, updateLocalIndex, 2)
    `SC_COUNTER_BANK(localCounter3, LOCAL_GEHL_TABLE_ENTRIES, queryLocalIndex, queryLocalIndex1, responseLocal3, responseLocalLane1_3, updateLocalIndex, 3)

    `SC_COUNTER_BANK(imliCounter0, IMLI_GEHL_TABLE_ENTRIES, queryImliIndex, queryImliIndex1, responseImli0, responseImliLane1_0, updateImliIndex, 0)
    `SC_COUNTER_BANK(imliCounter1, IMLI_GEHL_TABLE_ENTRIES, queryImliIndex, queryImliIndex1, responseImli1, responseImliLane1_1, updateImliIndex, 1)
    `SC_COUNTER_BANK(imliCounter2, IMLI_GEHL_TABLE_ENTRIES, queryImliIndex, queryImliIndex1, responseImli2, responseImliLane1_2, updateImliIndex, 2)
    `SC_COUNTER_BANK(pathCounter0, PATH_GEHL_TABLE_ENTRIES, queryPathIndex, queryPathIndex1, responsePath0, responsePathLane1_0, updatePathIndex, 0)
    `SC_COUNTER_BANK(pathCounter1, PATH_GEHL_TABLE_ENTRIES, queryPathIndex, queryPathIndex1, responsePath1, responsePathLane1_1, updatePathIndex, 1)
    `SC_COUNTER_BANK(pathCounter2, PATH_GEHL_TABLE_ENTRIES, queryPathIndex, queryPathIndex1, responsePath2, responsePathLane1_2, updatePathIndex, 2)

`undef SC_COUNTER_BANK

    always_comb begin : buildScore0
        integer signed accumulatedScore;
        integer signed dynamicThreshold;
        integer signed biasScore;
        integer signed globalScore;
        integer signed localScore;
        integer signed imliScore;
        integer signed pathScore;
        integer agreementCount;
        logic candidatePrediction;

        // Bias is deliberately half-weighted.  Unlike the history families,
        // its two tables describe closely related PC tendencies and therefore
        // should not receive two full independent votes in the final sum.
        biasScore =
            (counterAsInteger(responseBias0) +
             counterAsInteger(responseBias1)) / 2;
        // Six correlated global-history tables must not dominate the smaller
        // orthogonal Local/IMLI/Path families merely because there are more of
        // them.  Normalize their aggregate to half weight.
        globalScore =
            (counterAsInteger(responseGlobal0) +
             counterAsInteger(responseGlobal1) +
             counterAsInteger(responseGlobal2) +
             counterAsInteger(responseGlobal3) +
             counterAsInteger(responseGlobal4) +
             counterAsInteger(responseGlobal5)) / 2;
        localScore =
            counterAsInteger(responseLocal0) +
            counterAsInteger(responseLocal1) +
            counterAsInteger(responseLocal2) +
            counterAsInteger(responseLocal3);
        imliScore =
            counterAsInteger(responseImli0) +
            counterAsInteger(responseImli1) +
            counterAsInteger(responseImli2);
        pathScore =
            counterAsInteger(responsePath0) +
            counterAsInteger(responsePath1) +
            counterAsInteger(responsePath2);

        familyTaken_o[0] = biasScore > 0;
        familyTaken_o[1] = globalScore > 0;
        familyTaken_o[2] = localScore > 0;
        familyTaken_o[3] = imliScore > 0;
        familyTaken_o[4] = pathScore > 0;
        familyValid_o[0] = biasScore != 0;
        familyValid_o[1] = globalScore != 0;
        familyValid_o[2] = localScore != 0;
        familyValid_o[3] = imliScore != 0;
        familyValid_o[4] = pathScore != 0;

        accumulatedScore =
            biasScore + globalScore + localScore + imliScore + pathScore;
        accumulatedScore += basePrediction_i ?
            (baseStrong_i ? STRONG_BASE_WEIGHT : WEAK_BASE_WEIGHT) :
            -(baseStrong_i ? STRONG_BASE_WEIGHT : WEAK_BASE_WEIGHT);
        score_o = sc_score_t'(accumulatedScore);
        candidatePrediction = (accumulatedScore == 0) ?
            basePrediction_i : (accumulatedScore > 0);

        dynamicThreshold = LOW_CONFIDENCE_THRESHOLD +
            thresholdAsInteger(responseThresholdCounter);
        if (dynamicThreshold < 8)
            dynamicThreshold = 8;
        else if (dynamicThreshold > 63)
            dynamicThreshold = 63;
        lowConfidence_o =
            (accumulatedScore <= dynamicThreshold) &&
            (accumulatedScore >= -dynamicThreshold);

        agreementCount = 0;
        if (familyValid_o[0] &&
            familyTaken_o[0] == candidatePrediction) agreementCount++;
        if (familyValid_o[1] &&
            familyTaken_o[1] == candidatePrediction) agreementCount++;
        if (familyValid_o[2] &&
            familyTaken_o[2] == candidatePrediction) agreementCount++;
        if (familyValid_o[3] &&
            familyTaken_o[3] == candidatePrediction) agreementCount++;
        if (familyValid_o[4] &&
            familyTaken_o[4] == candidatePrediction) agreementCount++;

        predictTaken_o = candidatePrediction;
        if (candidatePrediction != basePrediction_i) begin
            if (baseStrong_i &&
                (((accumulatedScore <= dynamicThreshold) &&
                  (accumulatedScore >= -dynamicThreshold)) ||
                 (agreementCount < 3)))
                predictTaken_o = basePrediction_i;
            else if (!baseStrong_i && (agreementCount < 2))
                predictTaken_o = basePrediction_i;
        end
    end

    always_comb begin : buildScore1
        integer signed accumulatedScore;
        integer signed dynamicThreshold;
        integer signed biasScore;
        integer signed globalScore;
        integer signed localScore;
        integer signed imliScore;
        integer signed pathScore;
        integer agreementCount;
        logic candidatePrediction;

        biasScore =
            (counterAsInteger(responseBiasLane1_0) +
             counterAsInteger(responseBiasLane1_1)) / 2;
        globalScore =
            (counterAsInteger(responseGlobalLane1_0) +
             counterAsInteger(responseGlobalLane1_1) +
             counterAsInteger(responseGlobalLane1_2) +
             counterAsInteger(responseGlobalLane1_3) +
             counterAsInteger(responseGlobalLane1_4) +
             counterAsInteger(responseGlobalLane1_5)) / 2;
        localScore =
            counterAsInteger(responseLocalLane1_0) +
            counterAsInteger(responseLocalLane1_1) +
            counterAsInteger(responseLocalLane1_2) +
            counterAsInteger(responseLocalLane1_3);
        imliScore =
            counterAsInteger(responseImliLane1_0) +
            counterAsInteger(responseImliLane1_1) +
            counterAsInteger(responseImliLane1_2);
        pathScore =
            counterAsInteger(responsePathLane1_0) +
            counterAsInteger(responsePathLane1_1) +
            counterAsInteger(responsePathLane1_2);

        familyTaken1_o[0] = biasScore > 0;
        familyTaken1_o[1] = globalScore > 0;
        familyTaken1_o[2] = localScore > 0;
        familyTaken1_o[3] = imliScore > 0;
        familyTaken1_o[4] = pathScore > 0;
        familyValid1_o[0] = biasScore != 0;
        familyValid1_o[1] = globalScore != 0;
        familyValid1_o[2] = localScore != 0;
        familyValid1_o[3] = imliScore != 0;
        familyValid1_o[4] = pathScore != 0;

        accumulatedScore =
            biasScore + globalScore + localScore + imliScore + pathScore;
        accumulatedScore += basePrediction1_i ?
            (baseStrong1_i ? STRONG_BASE_WEIGHT : WEAK_BASE_WEIGHT) :
            -(baseStrong1_i ? STRONG_BASE_WEIGHT : WEAK_BASE_WEIGHT);
        score1_o = sc_score_t'(accumulatedScore);
        candidatePrediction = (accumulatedScore == 0) ?
            basePrediction1_i : (accumulatedScore > 0);

        dynamicThreshold = LOW_CONFIDENCE_THRESHOLD +
            thresholdAsInteger(responseThresholdCounter1);
        if (dynamicThreshold < 8)
            dynamicThreshold = 8;
        else if (dynamicThreshold > 63)
            dynamicThreshold = 63;
        lowConfidence1_o =
            (accumulatedScore <= dynamicThreshold) &&
            (accumulatedScore >= -dynamicThreshold);

        agreementCount = 0;
        if (familyValid1_o[0] &&
            familyTaken1_o[0] == candidatePrediction) agreementCount++;
        if (familyValid1_o[1] &&
            familyTaken1_o[1] == candidatePrediction) agreementCount++;
        if (familyValid1_o[2] &&
            familyTaken1_o[2] == candidatePrediction) agreementCount++;
        if (familyValid1_o[3] &&
            familyTaken1_o[3] == candidatePrediction) agreementCount++;
        if (familyValid1_o[4] &&
            familyTaken1_o[4] == candidatePrediction) agreementCount++;

        predictTaken1_o = candidatePrediction;
        if (candidatePrediction != basePrediction1_i) begin
            if (baseStrong1_i &&
                (((accumulatedScore <= dynamicThreshold) &&
                  (accumulatedScore >= -dynamicThreshold)) ||
                 (agreementCount < 3)))
                predictTaken1_o = basePrediction1_i;
            else if (!baseStrong1_i && (agreementCount < 2))
                predictTaken1_o = basePrediction1_i;
        end
    end

endmodule
