`timescale 1ns/1ps

module loop_predictor_tb;
    import TypesPkg::*;

    localparam instruction_addr_t LOOP_PC = 32'h0000_0140;

    logic clk = 1'b0;
    logic rst = 1'b0;
    instruction_addr_t queryPc;
    instruction_addr_t queryPc1;
    logic response0Conditional;
    loop_meta_t queryMeta;
    loop_meta_t queryMeta1;
    logic speculateValid;
    logic speculateTaken;
    logic speculateValid1;
    logic speculateTaken1;
    logic updateValid;
    instruction_addr_t updatePc;
    instruction_addr_t updateTarget;
    logic updateTaken;
    loop_meta_t updateMeta;
    logic recoverValid;
    logic recoverIsConditional;
    logic recoverTaken;
    rob_tag_t recoverRobTag;
    logic [1:0] checkpointAllocValid;
    rob_tag_t checkpointAllocTag [2];
    loop_meta_t checkpointAllocMeta [2];
    loop_meta_t savedExitMeta;

    always #5 clk = ~clk;

    LoopPredictor dut (
        .clk(clk), .rst(rst), .flush_i(1'b0),
        .queryPc_i(queryPc), .queryPc1_i(queryPc1),
        .response0Conditional_i(response0Conditional),
        .queryMeta_o(queryMeta), .queryMeta1_o(queryMeta1),
        .speculateValid_i(speculateValid),
        .speculateTaken_i(speculateTaken),
        .speculateValid1_i(speculateValid1),
        .speculateTaken1_i(speculateTaken1),
        .updateValid_i(updateValid), .updatePc_i(updatePc),
        .updateTarget_i(updateTarget),
        .updateTaken_i(updateTaken), .updateMeta_i(updateMeta),
        .recoverValid_i(recoverValid),
        .recoverIsConditional_i(recoverIsConditional),
        .recoverTaken_i(recoverTaken),
        .recoverRobTag_i(recoverRobTag),
        .checkpointAllocValid_i(checkpointAllocValid),
        .checkpointAllocTag_i(checkpointAllocTag),
        .checkpointAllocMeta_i(checkpointAllocMeta)
    );

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    task automatic retireOutcome(input logic taken);
        begin
            updateValid = 1'b1;
            updatePc = LOOP_PC;
            updateTaken = taken;
            updateMeta = '0;
            tick();
            updateValid = 1'b0;
        end
    endtask

    task automatic trainTripThree;
        begin
            retireOutcome(1'b1);
            retireOutcome(1'b1);
            retireOutcome(1'b1);
            retireOutcome(1'b0);
        end
    endtask

    task automatic acceptPrediction(input logic taken);
        begin
            speculateValid = 1'b1;
            speculateTaken = taken;
            tick();
            speculateValid = 1'b0;
        end
    endtask

    initial begin
        queryPc = LOOP_PC;
        queryPc1 = LOOP_PC + 32'd4;
        response0Conditional = 1'b1;
        speculateValid = 1'b0;
        speculateTaken = 1'b0;
        speculateValid1 = 1'b0;
        speculateTaken1 = 1'b0;
        updateValid = 1'b0;
        updatePc = LOOP_PC;
        updateTarget = LOOP_PC - 32'd16;
        updateTaken = 1'b0;
        updateMeta = '0;
        recoverValid = 1'b0;
        recoverIsConditional = 1'b0;
        recoverTaken = 1'b0;
        recoverRobTag = '0;
        checkpointAllocValid = '0;
        checkpointAllocTag[0] = '0;
        checkpointAllocTag[1] = '0;
        checkpointAllocMeta[0] = '0;
        checkpointAllocMeta[1] = '0;

        tick();
        rst = 1'b1;

        // First sequence discovers trip count 3. Three more matching exits
        // saturate the two-bit confidence counter.
        for (integer trainingLoop = 0; trainingLoop < 8;
             trainingLoop = trainingLoop + 1)
            trainTripThree();

        tick();
        if (!queryMeta.hit || !queryMeta.confident ||
            !queryMeta.prediction || (queryMeta.iterationBefore != 0))
            $fatal(1, "loop entry did not learn trip=3");

        acceptPrediction(1'b1);
        if (!queryMeta.prediction || (queryMeta.iterationBefore != 1))
            $fatal(1, "first loop iteration did not advance");
        acceptPrediction(1'b1);
        if (!queryMeta.prediction || (queryMeta.iterationBefore != 2))
            $fatal(1, "second loop iteration did not advance");
        acceptPrediction(1'b1);
        if (queryMeta.prediction || (queryMeta.iterationBefore != 3))
            $fatal(1, "loop predictor did not predict the learned exit");

        // Save the exit action in a ROB checkpoint, consume predicted N, and
        // then resolve it as T. Recovery must append corrected iteration 4.
        savedExitMeta = queryMeta;
        checkpointAllocValid[0] = 1'b1;
        checkpointAllocTag[0] = rob_tag_t'(2);
        checkpointAllocMeta[0] = savedExitMeta;
        speculateValid = 1'b1;
        speculateTaken = 1'b0;
        tick();
        checkpointAllocValid[0] = 1'b0;
        speculateValid = 1'b0;

        recoverValid = 1'b1;
        recoverIsConditional = 1'b1;
        recoverTaken = 1'b1;
        recoverRobTag = rob_tag_t'(2);
        tick();
        recoverValid = 1'b0;
        recoverIsConditional = 1'b0;
        tick();

        if (!queryMeta.hit || (queryMeta.iterationBefore != 4) ||
            queryMeta.prediction)
            $fatal(1, "loop action-log recovery failed");

        $display("Loop predictor trip-count/recovery smoke test: PASS");
        $finish;
    end

endmodule
