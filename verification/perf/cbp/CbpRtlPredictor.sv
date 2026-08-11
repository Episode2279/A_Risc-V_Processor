// CBP2025 direction-only wrapper around the production Bimodal+TAGE+Loop+SC
// RTL.  This wrapper is verification infrastructure, not additional predictor
// hardware.  The metadata slots model prediction-time information retained by
// the pipeline until a branch commits; CBP explicitly excludes such transient
// checkpoint state from its predictor-capacity budget.
module CbpRtlPredictor
    import TypesPkg::*;
#(
    parameter int META_SLOT_NUM = 4096,
    parameter int META_SLOT_WIDTH = $clog2(META_SLOT_NUM)
)
(
    input  logic clk,
    input  logic rst,

    input  instruction_addr_t queryPc_i,
    output logic prediction_o,
    output logic rawTagePrediction_o,
    output logic preScPrediction_o,
    output logic providerValid_o,
    output logic loopUsed_o,
    output logic scLowConfidence_o,

    input  logic saveMetaValid_i,
    input  logic [META_SLOT_WIDTH-1:0] saveMetaSlot_i,

    // CBP supplies the resolved direction immediately after prediction for
    // correct-path speculative-history maintenance.  Direction history moves
    // only for conditionals; Path History moves for every control event.
    input  logic historyUpdateValid_i,
    input  logic historyConditional_i,
    input  logic historyTaken_i,
    input  logic historyBackward_i,

    // Production tables still train at architectural commit.
    input  logic commitValid_i,
    input  logic commitConditional_i,
    input  logic [META_SLOT_WIDTH-1:0] commitMetaSlot_i,
    input  instruction_addr_t commitPc_i,
    input  instruction_addr_t commitTarget_i,
    input  logic commitTaken_i,
    output logic commitReady_o
);

    tage_meta_t queryMeta;
    tage_meta_t unusedMeta1;
    tage_meta_t savedMeta [META_SLOT_NUM];
    bpu_index_t queryIndex;
    bpu_index_t unusedIndex1;
    bpu_index_t commitIndex;
    logic fallbackPrediction;
    logic unusedFallback1;

    logic [1:0] checkpointAllocValid;
    rob_tag_t checkpointAllocTag [2];
    tage_history_t checkpointAllocHistory [2];
    tage_path_history_t checkpointAllocPathHistory [2];
    sc_imli_t checkpointAllocScImli [2];
    loop_meta_t checkpointAllocLoopMeta [2];

    assign prediction_o = queryMeta.finalPrediction;
    assign rawTagePrediction_o = queryMeta.tagePrediction;
    assign preScPrediction_o = queryMeta.preScPrediction;
    assign providerValid_o = queryMeta.providerValid;
    assign loopUsed_o = queryMeta.loop.used;
    assign scLowConfidence_o = queryMeta.scLowConfidence;
    assign commitIndex =
        bpu_index_t'(commitPc_i[BPU_BASE_INDEX_WIDTH+1:2]);

    always_comb begin
        checkpointAllocValid = '0;
        for (int lane = 0; lane < 2; lane = lane + 1) begin
            checkpointAllocTag[lane] = '0;
            checkpointAllocHistory[lane] = '0;
            checkpointAllocPathHistory[lane] = '0;
            checkpointAllocScImli[lane] = '0;
            checkpointAllocLoopMeta[lane] = '0;
        end
    end

    // Saving queryMeta one edge after the synchronous lookup captures the
    // exact history, Provider generation, Loop state, and SC score used for
    // the returned prediction.
    always_ff @(posedge clk) begin
        if (rst && saveMetaValid_i)
            savedMeta[saveMetaSlot_i] <= queryMeta;
    end

    BimodalPredictor bimodal (
        .clk(clk),
        .rst(rst),
        .queryPc_i(queryPc_i),
        .predictTaken_o(fallbackPrediction),
        .queryIndex_o(queryIndex),
        .queryPc1_i(queryPc_i + instruction_addr_t'(4)),
        .predictTaken1_o(unusedFallback1),
        .queryIndex1_o(unusedIndex1),
        .updateValid_i(commitValid_i),
        .updateIsConditional_i(commitConditional_i),
        .updateIndex_i(commitIndex),
        .updateTaken_i(commitTaken_i)
    );

    TagePredictor tage (
        .clk(clk),
        .rst(rst),
        .flush_i(1'b0),
        .queryPc_i(queryPc_i),
        .fallbackPrediction_i(fallbackPrediction),
        .queryMeta_o(queryMeta),
        .queryPc1_i(queryPc_i + instruction_addr_t'(4)),
        .fallbackPrediction1_i(unusedFallback1),
        .response0Conditional_i(1'b0),
        .query0Conditional_i(1'b0),
        .query0Control_i(1'b0),
        .query0Backward_i(1'b0),
        .query0PathTaken_i(1'b0),
        .queryMeta1_o(unusedMeta1),
        .speculateValid_i(historyUpdateValid_i &&
                          historyConditional_i),
        .speculateTaken_i(historyTaken_i),
        .speculateBackward_i(historyBackward_i),
        .speculateValid1_i(1'b0),
        .speculateTaken1_i(1'b0),
        .speculateBackward1_i(1'b0),
        .speculateControlValid_i(historyUpdateValid_i),
        .speculateControlValid1_i(1'b0),
        .updateValid_i(commitValid_i),
        .updateIsConditional_i(commitConditional_i),
        .updatePc_i(commitPc_i),
        .updateTarget_i(commitTarget_i),
        .updateTaken_i(commitTaken_i),
        .updateMeta_i(savedMeta[commitMetaSlot_i]),
        .updateReady_o(commitReady_o),
        .recoverValid_i(1'b0),
        .recoverPc_i('0),
        .recoverIsConditional_i(1'b0),
        .recoverTaken_i(1'b0),
        .recoverTarget_i('0),
        .recoverRobTag_i('0),
        .checkpointAllocValid_i(checkpointAllocValid),
        .checkpointAllocTag_i(checkpointAllocTag),
        .checkpointAllocHistory_i(checkpointAllocHistory),
        .checkpointAllocPathHistory_i(checkpointAllocPathHistory),
        .checkpointAllocScImli_i(checkpointAllocScImli),
        .checkpointAllocLoopMeta_i(checkpointAllocLoopMeta)
    );

endmodule
