`timescale 1ns/1ps

module sc_tb;
    import TypesPkg::*;

    logic clk = 1'b0;
    logic rst = 1'b0;

    logic queryValid;
    instruction_addr_t queryPc, queryPc1;
    localparam int GLOBAL_FOLD_WIDTH =
        $clog2(SC_GLOBAL_GEHL_TABLE_ENTRIES);
    logic [GLOBAL_FOLD_WIDTH-1:0]
        queryGlobalFold [SC_GLOBAL_GEHL_TABLE_NUM];
    logic [GLOBAL_FOLD_WIDTH-1:0]
        queryGlobalFold1 [SC_GLOBAL_GEHL_TABLE_NUM];
    tage_path_history_t queryPath, queryPath1;
    sc_imli_t queryImli, queryImli1;
    logic basePrediction, baseStrong;
    logic basePrediction1, baseStrong1;

    logic responseValid;
    logic predictTaken, predictTaken1;
    logic lowConfidence, lowConfidence1;
    sc_score_t score, score1;
    logic [SC_FEATURE_FAMILY_NUM-1:0] familyTaken, familyTaken1;
    logic [SC_FEATURE_FAMILY_NUM-1:0] familyValid, familyValid1;
    sc_local_history_t localHistory, localHistory1;

    logic updateValid;
    instruction_addr_t updatePc;
    tage_history_t updateHistory;
    tage_path_history_t updatePath;
    sc_local_history_t updateLocalHistory;
    sc_imli_t updateImli;
    logic updateTaken;
    logic updateBasePrediction;
    logic updateFinalPrediction;
    sc_score_t updateScore;
    logic updateLowConfidence;

    localparam instruction_addr_t KEY_A_PC = 32'h0000_1240;
    localparam instruction_addr_t KEY_B_PC = 32'h0000_9b74;
    localparam tage_history_t KEY_A_HISTORY =
        192'h0123_4567_89ab_cdef_fedc_ba98_7654_3210_0f1e_2d3c_4b5a_6978;

    always #5 clk = ~clk;

    StatisticalCorrector dut (
        .clk(clk), .rst(rst),
        .queryValid_i(queryValid),
        .queryPc_i(queryPc), .queryPc1_i(queryPc1),
        .queryGlobalFold_i(queryGlobalFold),
        .queryGlobalFold1_i(queryGlobalFold1),
        .queryPath_i(queryPath), .queryPath1_i(queryPath1),
        .queryImli_i(queryImli), .queryImli1_i(queryImli1),
        .basePrediction_i(basePrediction),
        .baseStrong_i(baseStrong),
        .basePrediction1_i(basePrediction1),
        .baseStrong1_i(baseStrong1),
        .responseValid_o(responseValid),
        .predictTaken_o(predictTaken),
        .predictTaken1_o(predictTaken1),
        .lowConfidence_o(lowConfidence),
        .lowConfidence1_o(lowConfidence1),
        .score_o(score), .score1_o(score1),
        .familyTaken_o(familyTaken),
        .familyTaken1_o(familyTaken1),
        .familyValid_o(familyValid),
        .familyValid1_o(familyValid1),
        .localHistory_o(localHistory),
        .localHistory1_o(localHistory1),
        .updateValid_i(updateValid),
        .updatePc_i(updatePc),
        .updateHistory_i(updateHistory),
        .updatePath_i(updatePath),
        .updateLocalHistory_i(updateLocalHistory),
        .updateImli_i(updateImli),
        .updateTaken_i(updateTaken),
        .updateBasePrediction_i(updateBasePrediction),
        .updateBaseStrong_i(1'b0),
        .updateFinalPrediction_i(updateFinalPrediction),
        .updateScore_i(updateScore),
        .updateLowConfidence_i(updateLowConfidence)
    );

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    task automatic clear_update;
        begin
            updateValid = 1'b0;
            updatePc = '0;
            updateHistory = '0;
            updatePath = '0;
            updateLocalHistory = '0;
            updateImli = '0;
            updateTaken = 1'b0;
            updateBasePrediction = 1'b0;
            updateFinalPrediction = 1'b0;
            updateScore = '0;
            updateLowConfidence = 1'b0;
        end
    endtask

    initial begin
        queryValid = 1'b0;
        queryPc = KEY_A_PC;
        queryPc1 = KEY_B_PC;
        queryGlobalFold = '{default:'0};
        queryGlobalFold1 = '{default:'0};
        queryPath = 16'h39a5;
        queryPath1 = 16'hc63a;
        queryImli = sc_imli_t'(3);
        queryImli1 = sc_imli_t'(7);
        basePrediction = 1'b0;
        baseStrong = 1'b0;
        basePrediction1 = 1'b1;
        baseStrong1 = 1'b0;
        clear_update();

        repeat (2) tick();
        if (responseValid)
            $fatal(1, "SC response must remain invalid during reset");
        rst = 1'b1;

        // All component counters start neutral, so the two lanes must follow
        // their independent weak base predictions.
        queryValid = 1'b1;
        tick();
        if (!responseValid || predictTaken || !predictTaken1)
            $fatal(1, "neutral SC did not preserve lane base predictions");
        if (($signed(score) != -20) || ($signed(score1) != 20))
            $fatal(1, "neutral scores were %0d/%0d, expected -20/+20",
                   $signed(score), $signed(score1));
        if (!lowConfidence || !lowConfidence1)
            $fatal(1, "weak neutral base must be low confidence");
        if ((localHistory != '0) || (localHistory1 != '0))
            $fatal(1, "local histories did not initialize to zero");

        // A strong base is outside the initial correction window.
        baseStrong = 1'b1;
        baseStrong1 = 1'b1;
        #1;
        if (($signed(score) != -62) || ($signed(score1) != 62) ||
            lowConfidence || lowConfidence1)
            $fatal(1, "strong-base confidence/score is incorrect");
        baseStrong = 1'b0;
        baseStrong1 = 1'b0;

        // Repeated residual misses for key A train Bias, Global GEHL and
        // IMLI GEHL toward taken.  The unrelated lane must remain isolated.
        updateValid = 1'b1;
        updatePc = KEY_A_PC;
        updateHistory = KEY_A_HISTORY;
        updatePath = queryPath;
        updateLocalHistory = '0;
        updateImli = queryImli;
        updateTaken = 1'b1;
        updateBasePrediction = 1'b0;
        updateFinalPrediction = 1'b0;
        updateScore = sc_score_t'(-20);
        updateLowConfidence = 1'b1;

        repeat (8) tick();
        if (!predictTaken)
            $fatal(1, "trained SC failed to override weak N base, score=%0d",
                   $signed(score));
        if (!predictTaken1)
            $fatal(1, "training key A polluted unrelated key B");
        if (localHistory == '0)
            $fatal(1, "retired outcomes did not advance local history");

        // A correct, high-confidence result must not update residual
        // counters, but the committed local history must still advance.
        clear_update();
        tick();
        updateValid = 1'b1;
        updatePc = KEY_A_PC;
        updateHistory = KEY_A_HISTORY;
        updatePath = queryPath;
        updateLocalHistory = localHistory;
        updateImli = queryImli;
        updateTaken = predictTaken;
        updateBasePrediction = basePrediction;
        updateFinalPrediction = predictTaken;
        updateScore = score;
        updateLowConfidence = 1'b0;
        tick();
        clear_update();
        tick();
        if (!predictTaken)
            $fatal(1, "non-training local-history update lost SC state");

        queryValid = 1'b0;
        tick();
        if (responseValid)
            $fatal(1, "responseValid did not clear");

        $display("16 KiB TAGE-SC-L statistical-corrector smoke tests passed");
        $finish;
    end
endmodule
