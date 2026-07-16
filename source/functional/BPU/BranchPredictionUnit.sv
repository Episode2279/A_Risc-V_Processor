module BranchPredictionUnit
    import TypesPkg::*;
#(
    parameter int BTB_ENTRIES = 128
)
(
    input  logic clk,
    input  logic rst,

    input  instruction_addr_t queryPc_i,
    input  instruction_t queryInsn_i,
    output logic predictTaken_o,
    output instruction_addr_t predictTarget_o,
    output bpu_index_t predictorIndex_o,
    input logic queryAdvance_i,
    input instruction_addr_t queryPc1_i,
    input instruction_t queryInsn1_i,
    input logic queryAdvance1_i,
    output logic predictTaken1_o,
    output instruction_addr_t predictTarget1_o,
    output bpu_index_t predictorIndex1_o,
    output logic [BPU_HISTORY_WIDTH-1:0] historySnapshot_o,
    output logic [BPU_HISTORY_WIDTH-1:0] historySnapshot1_o,
    output logic btbHit_o,btbHit1_o,rasUsed_o,rasUsed1_o,

    input  logic updateValid_i,
    input  instruction_addr_t updatePc_i,
    input  logic updateIsConditional_i,
    input  logic updateTaken_i,
    input  instruction_addr_t updateTarget_i,
    input  bpu_index_t updatePredictorIndex_i,
    input logic updateMispredicted_i, updateIsCall_i, updateIsReturn_i,
    input rob_tag_t updateRobTag_i,
    input logic [1:0] checkpointAllocValid_i,
    input rob_tag_t checkpointAllocTag_i [2],
    input logic [BPU_HISTORY_WIDTH-1:0] checkpointAllocHistory_i [2]
);

    localparam logic [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam logic [6:0] OPCODE_JAL    = 7'b1101111;
    localparam logic [6:0] OPCODE_JALR   = 7'b1100111;

    logic queryIsConditional;
    logic queryIsUnconditional;
    logic btbHit;
    instruction_addr_t btbTarget;
    logic gshareTaken;
    logic queryIsCall,queryIsReturn,rasValid;
    instruction_addr_t rasTarget;
    instruction_addr_t directJalTarget;
    logic query1Conditional,query1Unconditional,query1Call,query1Return,rasValid1;
    logic btbHit1,gshareTaken1;
    instruction_addr_t btbTarget1,directJalTarget1,rasTarget1;

    assign queryIsConditional = queryInsn_i[6:0] == OPCODE_BRANCH;
    assign queryIsUnconditional = (queryInsn_i[6:0] == OPCODE_JAL) ||
                                  (queryInsn_i[6:0] == OPCODE_JALR);
    assign queryIsCall = queryIsUnconditional && ((queryInsn_i[11:7]==5'd1)||(queryInsn_i[11:7]==5'd5));
    assign queryIsReturn = (queryInsn_i[6:0]==OPCODE_JALR)&&(queryInsn_i[11:7]==0)&&
                           ((queryInsn_i[19:15]==5'd1)||(queryInsn_i[19:15]==5'd5));
    assign directJalTarget = queryPc_i + {{11{queryInsn_i[31]}}, queryInsn_i[31],
        queryInsn_i[19:12], queryInsn_i[20], queryInsn_i[30:21], 1'b0};
    assign predictTaken_o = (queryInsn_i[6:0] == OPCODE_JAL) ||
        (queryIsReturn && rasValid) || (btbHit &&
        (queryIsUnconditional || (queryIsConditional && gshareTaken)));
    assign predictTarget_o = (queryInsn_i[6:0] == OPCODE_JAL) ? directJalTarget :
        ((queryIsReturn && rasValid) ? rasTarget : btbTarget);
    assign query1Conditional = queryInsn1_i[6:0] == OPCODE_BRANCH;
    assign query1Unconditional = (queryInsn1_i[6:0] == OPCODE_JAL) || (queryInsn1_i[6:0] == OPCODE_JALR);
    assign query1Call = query1Unconditional && ((queryInsn1_i[11:7]==5'd1)||(queryInsn1_i[11:7]==5'd5));
    assign query1Return = (queryInsn1_i[6:0]==OPCODE_JALR)&&(queryInsn1_i[11:7]==0)&&
                          ((queryInsn1_i[19:15]==5'd1)||(queryInsn1_i[19:15]==5'd5));
    assign directJalTarget1 = queryPc1_i + {{11{queryInsn1_i[31]}},queryInsn1_i[31],
        queryInsn1_i[19:12],queryInsn1_i[20],queryInsn1_i[30:21],1'b0};
    assign predictTaken1_o = (queryInsn1_i[6:0]==OPCODE_JAL) || (query1Return&&rasValid1) ||
        (btbHit1&&(query1Unconditional||(query1Conditional&&gshareTaken1)));
    assign predictTarget1_o = (queryInsn1_i[6:0]==OPCODE_JAL) ? directJalTarget1 :
        ((query1Return&&rasValid1)?rasTarget1:btbTarget1);
    assign btbHit_o=btbHit;
    assign btbHit1_o=btbHit1;
    assign rasUsed_o=queryIsReturn&&rasValid;
    assign rasUsed1_o=query1Return&&rasValid1;

    BranchTargetBuffer #(.ENTRIES(BTB_ENTRIES)) btb (
        .clk(clk),
        .rst(rst),
        .queryPc_i(queryPc_i),
        .hit_o(btbHit),
        .target_o(btbTarget),
        .queryPc1_i(queryPc1_i), .hit1_o(btbHit1), .target1_o(btbTarget1),
        .updateValid_i(updateValid_i),
        .updatePc_i(updatePc_i),
        .updateTaken_i(updateTaken_i),
        .updateTarget_i(updateTarget_i)
    );

    GSharePredictor gshare (
        .clk(clk),
        .rst(rst),
        .queryPc_i(queryPc_i),
        .predictTaken_o(gshareTaken),
        .queryIndex_o(predictorIndex_o),
        .queryPc1_i(queryPc1_i), .query0Conditional_i(queryIsConditional),
        .query0PredictedTaken_i(predictTaken_o), .predictTaken1_o(gshareTaken1),
        .queryIndex1_o(predictorIndex1_o),
        .queryHistory_o(historySnapshot_o), .queryHistory1_o(historySnapshot1_o),
        .speculateValid_i(queryAdvance_i && queryIsConditional),
        .speculateTaken_i(predictTaken_o),
        .speculateValid1_i(queryAdvance1_i && query1Conditional),
        .speculateTaken1_i(predictTaken1_o),
        .updateValid_i(updateValid_i), .updateIsConditional_i(updateIsConditional_i),
        .updateIndex_i(updatePredictorIndex_i),
        .updateTaken_i(updateTaken_i), .updateMispredicted_i(updateMispredicted_i),
        .updateRobTag_i(updateRobTag_i), .checkpointAllocValid_i(checkpointAllocValid_i),
        .checkpointAllocTag_i(checkpointAllocTag_i), .checkpointAllocHistory_i(checkpointAllocHistory_i)
    );

    ReturnAddressStack ras(
        .clk(clk),.rst(rst),.speculateValid_i(queryAdvance_i),
        .speculateCall_i(queryIsCall),.speculateReturn_i(queryIsReturn),
        .speculateReturnAddress_i(queryPc_i+32'd4),.resolveValid_i(updateValid_i),
        .speculateValid1_i(queryAdvance1_i),.speculateCall1_i(query1Call),
        .speculateReturn1_i(query1Return),.speculateReturnAddress1_i(queryPc1_i+32'd4),
        .resolveCall_i(updateIsCall_i),.resolveReturn_i(updateIsReturn_i),
        .mispredict_i(updateValid_i&&updateMispredicted_i),
        .resolveReturnAddress_i(updatePc_i+32'd4),.valid_o(rasValid),.target_o(rasTarget),
        .valid1_o(rasValid1),.target1_o(rasTarget1));

endmodule
