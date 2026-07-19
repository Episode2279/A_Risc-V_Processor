`timescale 1ns/1ps

module bpu_tb;
    import TypesPkg::*;

    localparam instruction_t BEQ_INSN = 32'h0000_0063;
    localparam instruction_t JAL_INSN = 32'h0000_006f;

    logic clk = 1'b0;
    logic rst = 1'b0;
    instruction_addr_t queryPc;
    instruction_t queryInsn;
    logic queryValid;
    logic queryReady;
    logic cancel;
    logic predictionValid;
    instruction_addr_t responsePc;
    instruction_t responseInsn;
    logic predictTaken;
    instruction_addr_t predictTarget;
    bpu_index_t predictorIndex;
    logic updateValid;
    instruction_addr_t updatePc;
    logic updateIsConditional;
    logic updateTaken;
    instruction_addr_t updateTarget;
    bpu_index_t updatePredictorIndex;

    always #5 clk = ~clk;

    BranchPredictionUnit #(
        .BTB_ENTRIES(8), .TAGE_ENABLE(1'b0), .SC_ENABLE(1'b0)
    ) dut (
        .clk(clk),
        .rst(rst),
        .flush_i(1'b0),
        .cancel_i(cancel),
        .queryValid_i(queryValid), .queryReady_o(queryReady),
        .queryPc_i(queryPc),
        .instructionValid_i(1'b1),
        .queryInsn_i(queryInsn),
        .predictionValid_o(predictionValid),
        .responsePc_o(responsePc),
        .responseInsn_o(responseInsn),
        .predictTaken_o(predictTaken),
        .predictTarget_o(predictTarget),
        .predictorIndex_o(predictorIndex),
        .tageMeta_o(),
        .queryAdvance_i(1'b0),
        .queryPc1_i('0), .queryInsn1_i('0), .queryAdvance1_i(1'b0),
        .responsePc1_o(), .responseInsn1_o(),
        .predictTaken1_o(), .predictTarget1_o(), .predictorIndex1_o(),
        .tageMeta1_o(),
        .historySnapshot_o(), .historySnapshot1_o(),
        .btbHit_o(),.btbHit1_o(),.rasUsed_o(),.rasUsed1_o(),
        .updateValid_i(updateValid),
        .updatePc_i(updatePc),
        .updateIsConditional_i(updateIsConditional),
        .updateTaken_i(updateTaken),
        .updateTarget_i(updateTarget),
        .updatePredictorIndex_i(updatePredictorIndex),
        .updateTageMeta_i('0),
        .updateReady_o(),
        .resolveValid_i(1'b0), .resolvePc_i('0),
        .resolveIsConditional_i(1'b0), .resolveTaken_i(1'b0),
        .resolveMispredicted_i(1'b0), .resolveIsCall_i(1'b0),
        .resolveIsReturn_i(1'b0), .resolveRobTag_i('0),
        .checkpointAllocValid_i('0),
        .checkpointAllocTag_i('{default:'0}),
        .checkpointAllocHistory_i('{default:'0}),
        .checkpointAllocTageHistory_i('{default:'0}),
        .checkpointAllocTagePathHistory_i('{default:'0})
    );

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    task automatic update(input word_t pc, input logic conditional,
                          input logic taken, input word_t target,
                          input bpu_index_t savedIndex);
        begin
            updateValid = 1'b1;
            updatePc = pc;
            updateIsConditional = conditional;
            updateTaken = taken;
            updateTarget = target;
            updatePredictorIndex = savedIndex;
            tick();
            updateValid = 1'b0;
        end
    endtask

    task automatic query(input word_t pc, input instruction_t insn);
        begin
            if (predictionValid) begin
                cancel = 1'b1;
                tick();
                cancel = 1'b0;
            end
            queryPc = pc;
            queryInsn = insn;
            queryValid = 1'b1;
            if (!queryReady) $fatal(1, "BPU request channel was not ready");
            tick();
            queryValid = 1'b0;
            if (!predictionValid || responsePc != pc || responseInsn != insn)
                $fatal(1, "registered BPU request/response alignment failed");
        end
    endtask

    initial begin
        queryPc = 32'h100;
        queryInsn = BEQ_INSN;
        queryValid = 1'b0;
        cancel = 1'b0;
        updateValid = 1'b0;
        updatePc = '0;
        updateIsConditional = 1'b0;
        updateTaken = 1'b0;
        updateTarget = '0;
        updatePredictorIndex = '0;

        tick();
        rst = 1'b1;
        #1;
        if (predictTaken) $fatal(1, "BPU predicted after reset");
        query(32'h100, BEQ_INSN);

        // A non-speculative unit-test update trains PHT[0x40] without
        // fabricating a GHR advance; real fetches use queryAdvance.
        update(32'h100, 1'b1, 1'b1, 32'h180, predictorIndex);

        // PC 0x104 therefore selects its own initially weak-not-taken entry.
        query(32'h104, JAL_INSN);
        update(32'h104, 1'b0, 1'b1, 32'h1a0, predictorIndex);
        query(32'h104, BEQ_INSN);
        if (predictTaken || predictTarget != 32'h1a0 ||
            predictorIndex != bpu_index_t'(10'h041))
            $fatal(1, "GShare lookup or BTB target lookup failed");

        // Train that entry not-taken; GHR remains owned by speculation.
        update(32'h104, 1'b1, 1'b0, 32'h108, predictorIndex);
        query(32'h108, JAL_INSN);
        update(32'h108, 1'b0, 1'b1, 32'h1c0, predictorIndex);
        query(32'h108, BEQ_INSN);
        if (predictTaken || predictorIndex != bpu_index_t'(10'h042))
            $fatal(1, "GShare not-taken counter update failed");

        // Direct JAL targets are decoded without waiting for a BTB fill.
        query(32'h200, JAL_INSN);
        if (!predictTaken || predictTarget != 32'h200)
            $fatal(1, "direct JAL prediction failed");
        update(32'h200, 1'b0, 1'b1, 32'h280, predictorIndex);
        query(32'h200, JAL_INSN);
        if (!predictTaken || predictTarget != 32'h200)
            $fatal(1, "direct JAL target changed after BTB update");
        update(32'h200, 1'b0, 1'b0, 32'h204, predictorIndex);
        query(32'h200, JAL_INSN);
        if (!predictTaken || predictTarget != 32'h200)
            $fatal(1, "not-taken update incorrectly invalidated BTB");

        $display("GShare base BPU + BTB smoke test: PASS");
        $finish;
    end

endmodule
