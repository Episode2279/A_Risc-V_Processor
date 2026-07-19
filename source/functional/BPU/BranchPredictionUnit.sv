module BranchPredictionUnit
    import TypesPkg::*;
#(
    parameter int BTB_ENTRIES = 128,
    parameter bit TAGE_ENABLE = 1'b1,
    parameter bit SC_ENABLE = 1'b1,
    parameter int SC_LOW_CONFIDENCE_THRESHOLD = 23,
    parameter int SC_WEAK_BASE_WEIGHT = 20,
    parameter int SC_STRONG_BASE_WEIGHT = 62
)
(
    input  logic clk,
    input  logic rst,
    input  logic flush_i,

    input  instruction_addr_t queryPc_i,
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
    input  logic resolveMispredicted_i,
    input  logic resolveIsCall_i, resolveIsReturn_i,
    input  rob_tag_t resolveRobTag_i,
    input logic [1:0] checkpointAllocValid_i,
    input rob_tag_t checkpointAllocTag_i [2],
    input logic [BPU_HISTORY_WIDTH-1:0] checkpointAllocHistory_i [2],
    input tage_history_t checkpointAllocTageHistory_i [2],
    input tage_path_history_t checkpointAllocTagePathHistory_i [2]
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
    logic gshareTaken;
    logic selectedDirection;
    tage_meta_t tageRawMeta;
    logic queryIsCall,queryIsReturn,rasValid;
    instruction_addr_t rasTarget;
    instruction_addr_t directJalTarget;
    logic query1Conditional,query1Unconditional,query1Call,query1Return,rasValid1;
    logic btbHit1,gshareTaken1;
    logic selectedDirection1;
    tage_meta_t tageRawMeta1;
    instruction_addr_t btbTarget1,directJalTarget1,rasTarget1;
    logic tageUpdateReady;

    // Raw request predecode feeds the synchronous TAGE lookup launched at this
    // edge.  All fallback, target, and speculative-update signals below still
    // describe the currently registered prediction response.
    assign requestIsConditional = queryInsn_i[6:0] == OPCODE_BRANCH;
    assign requestIsUnconditional = (queryInsn_i[6:0] == OPCODE_JAL) ||
                                    (queryInsn_i[6:0] == OPCODE_JALR);
    assign queryIsConditional = responseInsn_o[6:0] == OPCODE_BRANCH;
    assign queryIsUnconditional = (responseInsn_o[6:0] == OPCODE_JAL) ||
                                  (responseInsn_o[6:0] == OPCODE_JALR);
    assign queryIsCall = queryIsUnconditional && ((responseInsn_o[11:7]==5'd1)||(responseInsn_o[11:7]==5'd5));
    assign queryIsReturn = (responseInsn_o[6:0]==OPCODE_JALR)&&(responseInsn_o[11:7]==0)&&
                           ((responseInsn_o[19:15]==5'd1)||(responseInsn_o[19:15]==5'd5));
    assign directJalTarget = responsePc_o + {{11{responseInsn_o[31]}}, responseInsn_o[31],
        responseInsn_o[19:12], responseInsn_o[20], responseInsn_o[30:21], 1'b0};
    assign selectedDirection = TAGE_ENABLE ?
        tageRawMeta.finalPrediction : gshareTaken;
    assign selectedDirection1 = TAGE_ENABLE ?
        tageRawMeta1.finalPrediction : gshareTaken1;
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
            tageMeta_o.tagePrediction = gshareTaken;
            tageMeta_o.finalPrediction = gshareTaken;
            tageMeta_o.scLowConfidence = 1'b0;
            tageMeta1_o.tagePrediction = gshareTaken1;
            tageMeta1_o.finalPrediction = gshareTaken1;
            tageMeta1_o.scLowConfidence = 1'b0;
        end
    end

    // The incoming query is the next fetch request.  Registering its complete
    // context creates an explicit request/response boundary while the current
    // predictor tables remain combinational behind that boundary.
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            predictionValid_o <= 1'b0;
            responsePc_o <= RESET_VECTOR;
            responseInsn_o <= '0;
            responsePc1_o <= RESET_VECTOR + 32'd4;
            responseInsn1_o <= '0;
        end else begin
            predictionValid_o <= 1'b1;
            responsePc_o <= queryPc_i;
            responseInsn_o <= queryInsn_i;
            responsePc1_o <= queryPc1_i;
            responseInsn1_o <= queryInsn1_i;
        end
    end

    BranchTargetBuffer #(.ENTRIES(BTB_ENTRIES)) btb (
        .clk(clk),
        .rst(rst),
        .queryPc_i(responsePc_o),
        .hit_o(btbHit),
        .target_o(btbTarget),
        .queryPc1_i(responsePc1_o), .hit1_o(btbHit1), .target1_o(btbTarget1),
        .updateValid_i(updateValid_i),
        .updatePc_i(updatePc_i),
        .updateTaken_i(updateTaken_i),
        .updateTarget_i(updateTarget_i)
    );

    GSharePredictor gshare (
        .clk(clk),
        .rst(rst),
        .flush_i(flush_i),
        .queryPc_i(responsePc_o),
        .predictTaken_o(gshareTaken),
        .queryIndex_o(predictorIndex_o),
        .queryPc1_i(responsePc1_o), .query0Conditional_i(queryIsConditional),
        .query0PredictedTaken_i(predictTaken_o), .predictTaken1_o(gshareTaken1),
        .queryIndex1_o(predictorIndex1_o),
        .queryHistory_o(historySnapshot_o), .queryHistory1_o(historySnapshot1_o),
        .speculateValid_i(queryAdvance_i && queryIsConditional),
        .speculateTaken_i(predictTaken_o),
        .speculateValid1_i(queryAdvance1_i && query1Conditional),
        .speculateTaken1_i(predictTaken1_o),
        .updateValid_i(updateValid_i), .updateIsConditional_i(updateIsConditional_i),
        .updateIndex_i(updatePredictorIndex_i),
        .updateTaken_i(updateTaken_i),
        .recoverValid_i(resolveValid_i && resolveMispredicted_i),
        .recoverIsConditional_i(resolveIsConditional_i),
        .recoverTaken_i(resolveTaken_i), .recoverRobTag_i(resolveRobTag_i),
        .checkpointAllocValid_i(checkpointAllocValid_i),
        .checkpointAllocTag_i(checkpointAllocTag_i), .checkpointAllocHistory_i(checkpointAllocHistory_i)
    );

    TagePredictor #(
        .SC_ENABLE(SC_ENABLE),
        .SC_LOW_CONFIDENCE_THRESHOLD(SC_LOW_CONFIDENCE_THRESHOLD),
        .SC_WEAK_BASE_WEIGHT(SC_WEAK_BASE_WEIGHT),
        .SC_STRONG_BASE_WEIGHT(SC_STRONG_BASE_WEIGHT)
    ) tage (
        .clk(clk), .rst(rst), .flush_i(flush_i),
        .queryPc_i(queryPc_i), .fallbackPrediction_i(gshareTaken),
        .queryMeta_o(tageRawMeta),
        .queryPc1_i(queryPc1_i),
        .fallbackPrediction1_i(gshareTaken1),
        .query0Conditional_i(requestIsConditional),
        .query0Control_i(requestIsConditional || requestIsUnconditional),
        // Slot 1 can be consumed only when slot 0 follows the fall-through
        // path, so its synchronous request always assumes slot-0 NT.
        .query0PathTaken_i(1'b0), .queryMeta1_o(tageRawMeta1),
        .speculateValid_i(queryAdvance_i && queryIsConditional),
        .speculateTaken_i(predictTaken_o),
        .speculateValid1_i(queryAdvance1_i && query1Conditional),
        .speculateTaken1_i(predictTaken1_o),
        .speculateControlValid_i(queryAdvance_i &&
            (queryIsConditional || queryIsUnconditional)),
        .speculateControlValid1_i(queryAdvance1_i &&
            (query1Conditional || query1Unconditional)),
        .updateValid_i(updateValid_i && TAGE_ENABLE),
        .updateIsConditional_i(updateIsConditional_i),
        .updatePc_i(updatePc_i), .updateTaken_i(updateTaken_i),
        .updateMeta_i(updateTageMeta_i),
        .updateReady_o(tageUpdateReady),
        .recoverValid_i(resolveValid_i && resolveMispredicted_i),
        .recoverPc_i(resolvePc_i),
        .recoverIsConditional_i(resolveIsConditional_i),
        .recoverTaken_i(resolveTaken_i), .recoverRobTag_i(resolveRobTag_i),
        .checkpointAllocValid_i(checkpointAllocValid_i),
        .checkpointAllocTag_i(checkpointAllocTag_i),
        .checkpointAllocHistory_i(checkpointAllocTageHistory_i),
        .checkpointAllocPathHistory_i(
            checkpointAllocTagePathHistory_i)
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
