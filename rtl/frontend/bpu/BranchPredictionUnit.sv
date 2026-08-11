module BranchPredictionUnit
    import TypesPkg::*;
#(
    parameter int BTB_ENTRIES = 128,
    parameter bit TAGE_ENABLE = 1'b1,
    parameter bit LOOP_ENABLE = 1'b1,
    parameter bit SC_ENABLE = 1'b1,
    parameter int SC_LOW_CONFIDENCE_THRESHOLD = 23,
    parameter int SC_WEAK_BASE_WEIGHT = 20,
    parameter int SC_STRONG_BASE_WEIGHT = 62
)
(
    input  logic clk,
    input  logic rst,
    input  logic flush_i,
    input  logic cancel_i,

    input  logic queryValid_i,
    output logic queryReady_o,
    input  instruction_addr_t queryPc_i,
    // The synchronous I-cache returns these instruction words one stage after
    // queryPc_i was accepted.  instructionValid_i holds until the prediction
    // response is consumed.
    input  logic instructionValid_i,
    input  instruction_t queryInsn_i,
    output logic predictionValid_o,
    output instruction_addr_t responsePc_o,
    output instruction_t responseInsn_o,
    output logic predictTaken_o,
    output instruction_addr_t predictTarget_o,
    output bpu_index_t predictorIndex_o,
    output tage_meta_t tageMeta_o,
    input logic queryAdvance_i,
    input instruction_addr_t queryPc1_i,
    input instruction_t queryInsn1_i,
    output instruction_addr_t responsePc1_o,
    output instruction_t responseInsn1_o,
    input logic queryAdvance1_i,
    output logic predictTaken1_o,
    output instruction_addr_t predictTarget1_o,
    output bpu_index_t predictorIndex1_o,
    output tage_meta_t tageMeta1_o,
    output logic [BPU_HISTORY_WIDTH-1:0] historySnapshot_o,
    output logic [BPU_HISTORY_WIDTH-1:0] historySnapshot1_o,
    output logic btbHit_o,btbHit1_o,rasUsed_o,rasUsed1_o,

    input  logic updateValid_i,
    input  instruction_addr_t updatePc_i,
    input  logic updateIsConditional_i,
    input  logic updateTaken_i,
    input  instruction_addr_t updateTarget_i,
    input  bpu_index_t updatePredictorIndex_i,
    input  tage_meta_t updateTageMeta_i,
    output logic updateReady_o,
    input  logic resolveValid_i,
    input  instruction_addr_t resolvePc_i,
    input  logic resolveIsConditional_i,
    input  logic resolveTaken_i,
    input  instruction_addr_t resolveTarget_i,
    input  logic resolveMispredicted_i,
    input  logic resolveIsCall_i, resolveIsReturn_i,
    input  rob_tag_t resolveRobTag_i,
    input logic [1:0] checkpointAllocValid_i,
    input rob_tag_t checkpointAllocTag_i [2],
    input logic [BPU_HISTORY_WIDTH-1:0] checkpointAllocHistory_i [2],
    input tage_history_t checkpointAllocTageHistory_i [2],
    input tage_path_history_t checkpointAllocTagePathHistory_i [2],
    input sc_imli_t checkpointAllocScImli_i [2],
    input loop_meta_t checkpointAllocLoopMeta_i [2]
);

    localparam logic [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam logic [6:0] OPCODE_JAL    = 7'b1101111;
    localparam logic [6:0] OPCODE_JALR   = 7'b1100111;

    logic queryIsConditional;
    logic queryIsUnconditional;
    logic requestIsConditional;
    logic requestIsUnconditional;
    logic btbHit;
    instruction_addr_t btbTarget;
    logic baseTaken;
    logic selectedDirection;
    tage_meta_t tageRawMeta;
    logic queryIsCall,queryIsReturn,rasValid;
    instruction_addr_t rasTarget;
    instruction_addr_t directJalTarget;
    logic query1Conditional,query1Unconditional,query1Call,query1Return,rasValid1;
    logic btbHit1,baseTaken1;
    logic selectedDirection1;
    tage_meta_t tageRawMeta1;
    instruction_addr_t btbTarget1,directJalTarget1,rasTarget1;
    logic tageUpdateReady;
    logic requestContextValid;
    logic btbHintConditional,btbHintControl;
    logic btbHintConditional1,btbHintControl1;
    instruction_addr_t btbHintTarget,btbHintTarget1;
    instruction_addr_t tageQueryPc,tageQueryPc1;

    // I-cache Tag/Data and TAGE SRAMs are read in parallel.  The instruction
    // bits are therefore unavailable in F0; a BTB-resident CFI type hint gives
    // slot 1 the best known slot-0 history.  A BTB miss conservatively treats
    // the request as non-control until the real instruction arrives in F1.
    assign requestIsConditional = btbHintConditional;
    assign requestIsUnconditional = btbHintControl && !btbHintConditional;
    assign tageQueryPc = queryValid_i ? queryPc_i : responsePc_o;
    assign tageQueryPc1 = queryValid_i ? queryPc1_i : responsePc1_o;
    assign queryReady_o = !requestContextValid || queryAdvance_i || cancel_i;
    assign predictionValid_o = requestContextValid && instructionValid_i;
    assign responseInsn_o = predictionValid_o ? queryInsn_i : '0;
    assign responseInsn1_o = predictionValid_o ? queryInsn1_i : '0;
    assign queryIsConditional = responseInsn_o[6:0] == OPCODE_BRANCH;
    assign queryIsUnconditional = (responseInsn_o[6:0] == OPCODE_JAL) ||
                                  (responseInsn_o[6:0] == OPCODE_JALR);
    assign queryIsCall = queryIsUnconditional && ((responseInsn_o[11:7]==5'd1)||(responseInsn_o[11:7]==5'd5));
    assign queryIsReturn = (responseInsn_o[6:0]==OPCODE_JALR)&&(responseInsn_o[11:7]==0)&&
                           ((responseInsn_o[19:15]==5'd1)||(responseInsn_o[19:15]==5'd5));
    assign directJalTarget = responsePc_o + {{11{responseInsn_o[31]}}, responseInsn_o[31],
        responseInsn_o[19:12], responseInsn_o[20], responseInsn_o[30:21], 1'b0};
    assign selectedDirection = TAGE_ENABLE ?
        tageRawMeta.finalPrediction : baseTaken;
    assign selectedDirection1 = TAGE_ENABLE ?
        tageRawMeta1.finalPrediction : baseTaken1;
    assign updateReady_o = !TAGE_ENABLE || tageUpdateReady;
    assign predictTaken_o = predictionValid_o &&
        ((responseInsn_o[6:0] == OPCODE_JAL) ||
        (queryIsReturn && rasValid) || (btbHit &&
        (queryIsUnconditional || (queryIsConditional && selectedDirection))));
    assign predictTarget_o = (responseInsn_o[6:0] == OPCODE_JAL) ? directJalTarget :
        ((queryIsReturn && rasValid) ? rasTarget : btbTarget);
    assign query1Conditional = responseInsn1_o[6:0] == OPCODE_BRANCH;
    assign query1Unconditional = (responseInsn1_o[6:0] == OPCODE_JAL) || (responseInsn1_o[6:0] == OPCODE_JALR);
    assign query1Call = query1Unconditional && ((responseInsn1_o[11:7]==5'd1)||(responseInsn1_o[11:7]==5'd5));
    assign query1Return = (responseInsn1_o[6:0]==OPCODE_JALR)&&(responseInsn1_o[11:7]==0)&&
                          ((responseInsn1_o[19:15]==5'd1)||(responseInsn1_o[19:15]==5'd5));
    assign directJalTarget1 = responsePc1_o + {{11{responseInsn1_o[31]}},responseInsn1_o[31],
        responseInsn1_o[19:12],responseInsn1_o[20],responseInsn1_o[30:21],1'b0};
    assign predictTaken1_o = predictionValid_o &&
        ((responseInsn1_o[6:0]==OPCODE_JAL) || (query1Return&&rasValid1) ||
        (btbHit1&&(query1Unconditional||(query1Conditional&&selectedDirection1))));
    assign predictTarget1_o = (responseInsn1_o[6:0]==OPCODE_JAL) ? directJalTarget1 :
        ((query1Return&&rasValid1)?rasTarget1:btbTarget1);
    assign btbHit_o=btbHit;
    assign btbHit1_o=btbHit1;
    assign rasUsed_o=queryIsReturn&&rasValid;
    assign rasUsed1_o=query1Return&&rasValid1;

    always_comb begin
        tageMeta_o = tageRawMeta;
        tageMeta1_o = tageRawMeta1;
        if (!TAGE_ENABLE) begin
            tageMeta_o.tagePrediction = baseTaken;
            tageMeta_o.preScPrediction = baseTaken;
            tageMeta_o.finalPrediction = baseTaken;
            tageMeta_o.scLowConfidence = 1'b0;
            tageMeta1_o.tagePrediction = baseTaken1;
            tageMeta1_o.preScPrediction = baseTaken1;
            tageMeta1_o.finalPrediction = baseTaken1;
            tageMeta1_o.scLowConfidence = 1'b0;
        end
    end

    // The accepted F0 PC is retained while a cache miss or a full fetch window
    // holds F1.  A consumed response may be replaced by the next request at the
    // same edge, preserving one dual-instruction bundle per hit cycle.
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            requestContextValid <= 1'b0;
            responsePc_o <= RESET_VECTOR;
            responsePc1_o <= RESET_VECTOR + 32'd4;
        end else if (cancel_i) begin
            // A redirect cancels the old F1 context, but the I-cache may accept
            // the redirect PC on this same edge.  Retain that replacement so
            // its synchronous I-cache/TAGE results remain aligned.
            requestContextValid <= queryValid_i;
            if (queryValid_i) begin
                responsePc_o <= queryPc_i;
                responsePc1_o <= queryPc1_i;
            end
        end else begin
            if (queryValid_i && queryReady_o) begin
                requestContextValid <= 1'b1;
                responsePc_o <= queryPc_i;
                responsePc1_o <= queryPc1_i;
            end else if (queryAdvance_i) begin
                requestContextValid <= 1'b0;
            end
        end
    end

    BranchTargetBuffer #(.ENTRIES(BTB_ENTRIES)) btb (
        .clk(clk),
        .rst(rst),
        .queryPc_i(responsePc_o),
        .hit_o(btbHit),
        .target_o(btbTarget),
        .queryPc1_i(responsePc1_o), .hit1_o(btbHit1), .target1_o(btbTarget1),
        .hintPc_i(tageQueryPc), .hintPc1_i(tageQueryPc1),
        .hintConditional_o(btbHintConditional),
        .hintControl_o(btbHintControl),
        .hintConditional1_o(btbHintConditional1),
        .hintControl1_o(btbHintControl1),
        .hintTarget_o(btbHintTarget),
        .hintTarget1_o(btbHintTarget1),
        .updateValid_i(updateValid_i),
        .updatePc_i(updatePc_i),
        .updateIsConditional_i(updateIsConditional_i),
        .updateTaken_i(updateTaken_i),
        .updateTarget_i(updateTarget_i)
    );

    // TAGE falls back to a PC-indexed Bimodal predictor.  The compatibility
    // history outputs are zero because the base predictor has no speculative
    // history or recovery state.
    assign historySnapshot_o = '0;
    assign historySnapshot1_o = '0;

    BimodalPredictor bimodal (
        .clk(clk),
        .rst(rst),
        .queryPc_i(responsePc_o),
        .predictTaken_o(baseTaken),
        .queryIndex_o(predictorIndex_o),
        .queryPc1_i(responsePc1_o),
        .predictTaken1_o(baseTaken1),
        .queryIndex1_o(predictorIndex1_o),
        .updateValid_i(updateValid_i), .updateIsConditional_i(updateIsConditional_i),
        .updateIndex_i(updatePredictorIndex_i),
        .updateTaken_i(updateTaken_i)
    );

    TagePredictor #(
        .LOOP_ENABLE(LOOP_ENABLE),
        .SC_ENABLE(SC_ENABLE),
        .SC_LOW_CONFIDENCE_THRESHOLD(SC_LOW_CONFIDENCE_THRESHOLD),
        .SC_WEAK_BASE_WEIGHT(SC_WEAK_BASE_WEIGHT),
        .SC_STRONG_BASE_WEIGHT(SC_STRONG_BASE_WEIGHT)
    ) tage (
        .clk(clk), .rst(rst), .flush_i(flush_i),
        .queryPc_i(tageQueryPc), .fallbackPrediction_i(baseTaken),
        .queryMeta_o(tageRawMeta),
        .queryPc1_i(tageQueryPc1),
        .fallbackPrediction1_i(baseTaken1),
        .response0Conditional_i(queryIsConditional),
        .query0Conditional_i(requestIsConditional),
        .query0Control_i(requestIsConditional || requestIsUnconditional),
        .query0Backward_i(requestIsConditional &&
            (btbHintTarget < tageQueryPc)),
        // Slot 1 can be consumed only when slot 0 follows the fall-through
        // path, so its synchronous request always assumes slot-0 NT.
        .query0PathTaken_i(1'b0), .queryMeta1_o(tageRawMeta1),
        .speculateValid_i(queryAdvance_i && queryIsConditional),
        .speculateTaken_i(predictTaken_o),
        .speculateBackward_i(queryIsConditional && btbHit &&
            (btbTarget < responsePc_o)),
        .speculateValid1_i(queryAdvance1_i && query1Conditional),
        .speculateTaken1_i(predictTaken1_o),
        .speculateBackward1_i(query1Conditional && btbHit1 &&
            (btbTarget1 < responsePc1_o)),
        .speculateControlValid_i(queryAdvance_i &&
            (queryIsConditional || queryIsUnconditional)),
        .speculateControlValid1_i(queryAdvance1_i &&
            (query1Conditional || query1Unconditional)),
        .updateValid_i(updateValid_i && TAGE_ENABLE),
        .updateIsConditional_i(updateIsConditional_i),
        .updatePc_i(updatePc_i), .updateTarget_i(updateTarget_i),
        .updateTaken_i(updateTaken_i),
        .updateMeta_i(updateTageMeta_i),
        .updateReady_o(tageUpdateReady),
        .recoverValid_i(resolveValid_i && resolveMispredicted_i),
        .recoverPc_i(resolvePc_i),
        .recoverIsConditional_i(resolveIsConditional_i),
        .recoverTaken_i(resolveTaken_i),
        .recoverTarget_i(resolveTarget_i),
        .recoverRobTag_i(resolveRobTag_i),
        .checkpointAllocValid_i(checkpointAllocValid_i),
        .checkpointAllocTag_i(checkpointAllocTag_i),
        .checkpointAllocHistory_i(checkpointAllocTageHistory_i),
        .checkpointAllocPathHistory_i(
            checkpointAllocTagePathHistory_i),
        .checkpointAllocScImli_i(checkpointAllocScImli_i),
        .checkpointAllocLoopMeta_i(checkpointAllocLoopMeta_i)
    );

    ReturnAddressStack ras(
        .clk(clk),.rst(rst),.speculateValid_i(queryAdvance_i),
        .speculateCall_i(queryIsCall),.speculateReturn_i(queryIsReturn),
        .speculateReturnAddress_i(responsePc_o+32'd4),.resolveValid_i(resolveValid_i),
        .speculateValid1_i(queryAdvance1_i),.speculateCall1_i(query1Call),
        .speculateReturn1_i(query1Return),.speculateReturnAddress1_i(responsePc1_o+32'd4),
        .resolveCall_i(resolveIsCall_i),.resolveReturn_i(resolveIsReturn_i),
        .mispredict_i(resolveValid_i&&resolveMispredicted_i),
        .resolveReturnAddress_i(resolvePc_i+32'd4),.valid_o(rasValid),.target_o(rasTarget),
        .valid1_o(rasValid1),.target1_o(rasTarget1));

endmodule
