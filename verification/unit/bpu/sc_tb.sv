`timescale 1ns/1ps

module sc_tb;
    import TypesPkg::*;

    logic clk = 1'b0;
    logic rst = 1'b0;

    logic queryValid;
    instruction_addr_t queryPc;
    instruction_addr_t queryPc1;
    localparam int SC_GEHL_TABLE_NUM = 4;
    logic [6:0] queryHistoryFold [SC_GEHL_TABLE_NUM];
    logic [6:0] queryHistoryFold1 [SC_GEHL_TABLE_NUM];
    tage_path_history_t queryPath;
    tage_path_history_t queryPath1;
    logic basePrediction;
    logic baseStrong;
    logic basePrediction1;
    logic baseStrong1;

    logic responseValid;
    logic predictTaken;
    logic predictTaken1;
    logic lowConfidence;
    logic lowConfidence1;
    logic signed [9:0] score;
    logic signed [9:0] score1;

    logic updateValid;
    instruction_addr_t updatePc;
    tage_history_t updateHistory;
    tage_path_history_t updatePath;
    logic updateTaken;
    logic updateFinalPrediction;
    logic updateLowConfidence;

    localparam instruction_addr_t KEY_A_PC = 32'h0000_1240;
    localparam tage_history_t KEY_A_HISTORY =
        64'h0123_4567_89ab_cdef;
    localparam tage_path_history_t KEY_A_PATH = 16'h39a5;

    localparam instruction_addr_t KEY_B_PC = 32'h0000_9b74;
    localparam tage_history_t KEY_B_HISTORY =
        64'hd4c3_b2a1_7869_5a4b;
    localparam tage_path_history_t KEY_B_PATH = 16'hc63a;

    always #5 clk = ~clk;

    // Deliberately use the production defaults: a 256-entry PC-bias table and
    // four 128-entry GEHL tables, all with signed six-bit counters
    // (256*6 + 4*128*6 = 4608 logical counter-state bits).
    StatisticalCorrector dut (
        .clk(clk),
        .rst(rst),
        .queryValid_i(queryValid),
        .queryPc_i(queryPc),
        .queryPc1_i(queryPc1),
        .queryHistoryFold_i(queryHistoryFold),
        .queryHistoryFold1_i(queryHistoryFold1),
        .queryPath_i(queryPath),
        .queryPath1_i(queryPath1),
        .basePrediction_i(basePrediction),
        .baseStrong_i(baseStrong),
        .basePrediction1_i(basePrediction1),
        .baseStrong1_i(baseStrong1),
        .responseValid_o(responseValid),
        .predictTaken_o(predictTaken),
        .predictTaken1_o(predictTaken1),
        .lowConfidence_o(lowConfidence),
        .lowConfidence1_o(lowConfidence1),
        .score_o(score),
        .score1_o(score1),
        .updateValid_i(updateValid),
        .updatePc_i(updatePc),
        .updateHistory_i(updateHistory),
        .updatePath_i(updatePath),
        .updateTaken_i(updateTaken),
        .updateFinalPrediction_i(updateFinalPrediction),
        .updateLowConfidence_i(updateLowConfidence)
    );

    function automatic logic [6:0] foldHistory(
        input tage_history_t history,
        input integer historyLength
    );
        logic [6:0] result;
        integer bitIndex;
        begin
            result = '0;
            for (bitIndex = 0; bitIndex < historyLength;
                 bitIndex = bitIndex + 1)
                result[bitIndex % 7] = result[bitIndex % 7] ^
                    history[bitIndex];
            foldHistory = result;
        end
    endfunction

    function automatic integer historyLength(input integer foldIndex);
        begin
            case (foldIndex)
                0: historyLength = 3;
                1: historyLength = 7;
                2: historyLength = 15;
                default: historyLength = 31;
            endcase
        end
    endfunction

    task automatic set_query_keys;
        integer foldIndex;
        begin
            queryPc = KEY_A_PC;
            queryPath = KEY_A_PATH;
            queryPc1 = KEY_B_PC;
            queryPath1 = KEY_B_PATH;
            for (foldIndex = 0; foldIndex < SC_GEHL_TABLE_NUM;
                 foldIndex = foldIndex + 1) begin
                queryHistoryFold[foldIndex] = foldHistory(
                    KEY_A_HISTORY, historyLength(foldIndex));
                queryHistoryFold1[foldIndex] = foldHistory(
                    KEY_B_HISTORY, historyLength(foldIndex));
            end
        end
    endtask

    task automatic set_update_a(
        input logic taken,
        input logic finalPrediction,
        input logic lowConfidenceValue
    );
        begin
            updateValid = 1'b1;
            updatePc = KEY_A_PC;
            updateHistory = KEY_A_HISTORY;
            updatePath = KEY_A_PATH;
            updateTaken = taken;
            updateFinalPrediction = finalPrediction;
            updateLowConfidence = lowConfidenceValue;
        end
    endtask

    task automatic clear_update;
        begin
            updateValid = 1'b0;
            updatePc = '0;
            updateHistory = '0;
            updatePath = '0;
            updateTaken = 1'b0;
            updateFinalPrediction = 1'b0;
            updateLowConfidence = 1'b0;
        end
    endtask

    task automatic expect_lane_predictions(
        input logic expected0,
        input logic expected1,
        input string phase
    );
        begin
            if (!responseValid)
                $fatal(1, "%s: responseValid was not asserted", phase);
            if (predictTaken !== expected0)
                $fatal(1,
                       "%s: lane0 prediction=%0b expected=%0b score=%0d",
                       phase, predictTaken, expected0, $signed(score));
            if (predictTaken1 !== expected1)
                $fatal(1,
                       "%s: lane1 prediction=%0b expected=%0b score=%0d",
                       phase, predictTaken1, expected1, $signed(score1));
        end
    endtask

    initial begin
        queryValid = 1'b0;
        queryPc = '0;
        queryPc1 = '0;
        queryHistoryFold = '{default:'0};
        queryHistoryFold1 = '{default:'0};
        queryPath = '0;
        queryPath1 = '0;
        basePrediction = 1'b0;
        baseStrong = 1'b0;
        basePrediction1 = 1'b0;
        baseStrong1 = 1'b0;
        clear_update();

        // Active-low reset clears every component counter and suppresses a
        // response even if no request has ever been launched.
        repeat (2) @(posedge clk);
        #1;
        if (responseValid !== 1'b0)
            $fatal(1, "reset: responseValid must be zero");
        @(negedge clk);
        rst = 1'b1;

        // A request must not become visible combinationally.  With all
        // counters at zero each lane follows its own base predictor, proving
        // both the reset state and that the lane1 base cannot leak into lane0.
        set_query_keys();
        queryValid = 1'b1;
        basePrediction = 1'b0;
        baseStrong = 1'b0;
        basePrediction1 = 1'b1;
        baseStrong1 = 1'b0;
        #1;
        if (responseValid !== 1'b0)
            $fatal(1, "request became valid before its sampling edge");
        @(posedge clk);
        #1;
        expect_lane_predictions(1'b0, 1'b1, "zero-state/base isolation");
        if (($signed(score) != -20) || ($signed(score1) != 20))
            $fatal(1,
                   "zero-state scores were not weak-base scores: %0d/%0d",
                   $signed(score), $signed(score1));
        if (!lowConfidence || !lowConfidence1)
            $fatal(1, "zero component sum must request SC training");

        // The confidence threshold is applied to the complete score.  With
        // neutral components, a strong TAGE vote must therefore remain
        // outside the SC training window.
        baseStrong = 1'b1;
        baseStrong1 = 1'b1;
        #1;
        expect_lane_predictions(1'b0, 1'b1,
                                "strong-base confidence");
        if (($signed(score) != -62) || ($signed(score1) != 62))
            $fatal(1, "strong-base scores were wrong: %0d/%0d",
                   $signed(score), $signed(score1));
        if (lowConfidence || lowConfidence1)
            $fatal(1, "strong combined score must not request training");
        baseStrong = 1'b0;
        baseStrong1 = 1'b0;

        // responseValid remains asserted for the response cycle and drops on
        // the first edge after queryValid is removed.
        queryValid = 1'b0;
        #1;
        if (responseValid !== 1'b1)
            $fatal(1, "responseValid did not span the full response cycle");
        @(posedge clk);
        #1;
        if (responseValid !== 1'b0)
            $fatal(1, "responseValid did not deassert after one response");

        // Train key A toward taken while launching a lookup of the exact same
        // key on the same edge. The first forwarded update changes the score
        // from -20 to -14 without immediately overriding TAGE; this checks the
        // conservative residual-learning policy as well as write forwarding.
        @(negedge clk);
        set_query_keys();
        queryValid = 1'b1;
        basePrediction = 1'b0;
        baseStrong = 1'b0;
        basePrediction1 = 1'b0;
        baseStrong1 = 1'b0;
        set_update_a(1'b1, 1'b0, 1'b1);
        @(posedge clk);
        #1;
        expect_lane_predictions(1'b0, 1'b0,
                                "first taken training/forwarding");
        if ($signed(score) != -14)
            $fatal(1, "forwarded taken score=%0d expected=-14",
                   $signed(score));
        if (!lowConfidence)
            $fatal(1, "combined score -14 must be low confidence");

        // Three more agreeing residual misses are needed before the six
        // effective component votes outweigh the weak-base vote
        // (4*6-20 = +4).
        repeat (3) begin
            @(posedge clk);
            #1;
        end
        expect_lane_predictions(1'b1, 1'b0,
                                "conservative taken correction");
        if ($signed(score) != 4)
            $fatal(1, "trained taken score=%0d expected=4",
                   $signed(score));

        // Remove the update and read again: the taken correction must have
        // persisted, while unrelated key B must still follow its N base.
        clear_update();
        @(posedge clk);
        #1;
        expect_lane_predictions(1'b1, 1'b0,
                                "persisted taken/key isolation");

        // Reverse the training direction.  The same-edge lookup must observe
        // the decremented values through forwarding and return to N.
        set_update_a(1'b0, 1'b1, 1'b1);
        @(posedge clk);
        #1;
        expect_lane_predictions(1'b0, 1'b0,
                                "not-taken training/forwarding");
        if ($signed(score) != -2)
            $fatal(1, "forwarded not-taken score=%0d expected=-2",
                   $signed(score));

        // Confirm the reverse update is persistent as well.
        clear_update();
        @(posedge clk);
        #1;
        expect_lane_predictions(1'b0, 1'b0, "persisted not-taken");

        queryValid = 1'b0;
        @(posedge clk);
        #1;
        if (responseValid !== 1'b0)
            $fatal(1, "final responseValid did not clear");

        $display("StatisticalCorrector Bias256+4xGEHL128 smoke tests passed");
        $finish;
    end

endmodule
