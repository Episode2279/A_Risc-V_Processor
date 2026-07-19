module DualIfStages
    import TypesPkg::*;
#(
    // Dual fetch keeps the same byte-addressed PC model as the single-issue IF
    // stage, but reads PC and PC+4 each cycle.
    parameter int ADDR_W = WORD_SIZE,
    parameter int INSN_W = INS_SIZE,
    parameter int MEM_ADDR_W = INS_ADDR,
    parameter int MEM_BYTES = INS_ADDR_SIZE,
    parameter logic [ADDR_W-1:0] RESET_PC = RESET_VECTOR,
    parameter logic [ADDR_W-1:0] PC_INCREMENT = 32'd4,
    parameter string MEM_FILE = "utils/insn.mem"
)
(
    input  logic              clk,
    input  logic              rst,
    input  logic [ADDR_W-1:0] jump_address,
    input  logic              jump_enable,
    input  logic              predictionValid_i,
    input  logic [ADDR_W-1:0] responsePc_i,
    input  logic [INSN_W-1:0] responseInsn_i,
    input  logic [ADDR_W-1:0] responsePc1_i,
    input  logic [INSN_W-1:0] responseInsn1_i,
    input  logic              predictTaken_i,
    input  logic [ADDR_W-1:0] predictTarget_i,
    input  bpu_index_t        predictorIndex_i,
    input  logic              predictTaken1_i,
    input  logic [ADDR_W-1:0] predictTarget1_i,
    input  bpu_index_t        predictorIndex1_i,
    input  logic [BPU_HISTORY_WIDTH-1:0] historySnapshot_i,
    input  logic [BPU_HISTORY_WIDTH-1:0] historySnapshot1_i,
    input  tage_meta_t        tageMeta_i,
    input  tage_meta_t        tageMeta1_i,
    input logic btbHit_i,btbHit1_i,rasUsed_i,rasUsed1_i,
    // pc_step_i is 0/4/8 for stall, single issue, or dual issue.
    input  logic [ADDR_W-1:0] pc_step_i,
    output logic [ADDR_W-1:0] requestPc_o,
    output logic [INSN_W-1:0] requestInsn_o,
    output logic [ADDR_W-1:0] requestPc1_o,
    output logic [INSN_W-1:0] requestInsn1_o,
    InstructionPacketIf.source fetch_packet0,
    InstructionPacketIf.source fetch_packet1
);

    logic [ADDR_W-1:0] pc;
    logic [ADDR_W-1:0] nextRequestPc;

    // The registered BPU response is the only context exposed to IF/ID.  The
    // combinational instruction-memory outputs below belong to the next
    // request and must never be mixed with these response predictions.
    assign fetch_packet0.pc = predictionValid_i ? responsePc_i : RESET_PC;
    assign fetch_packet1.pc = predictionValid_i ? responsePc1_i : RESET_PC;
    assign fetch_packet0.insn = predictionValid_i ? responseInsn_i : '0;
    assign fetch_packet1.insn = predictionValid_i &&
        !(predictTaken_i && (pc_step_i != '0)) ? responseInsn1_i : '0;
    assign fetch_packet0.predictedTaken = predictionValid_i && predictTaken_i &&
                                          (pc_step_i != '0);
    assign fetch_packet0.predictedTarget = predictionValid_i ? predictTarget_i : '0;
    assign fetch_packet0.predictorIndex = predictionValid_i ? predictorIndex_i : '0;
    assign fetch_packet0.historySnapshot = predictionValid_i ? historySnapshot_i : '0;
    assign fetch_packet0.tageMeta = predictionValid_i ? tageMeta_i : '0;
    assign fetch_packet0.predictedBtbHit = predictionValid_i && btbHit_i;
    assign fetch_packet0.predictedRasUsed = predictionValid_i && rasUsed_i;
    assign fetch_packet1.predictedTaken = predictionValid_i && predictTaken1_i &&
        !predictTaken_i && (pc_step_i == (PC_INCREMENT + PC_INCREMENT));
    assign fetch_packet1.predictedTarget = predictionValid_i ? predictTarget1_i : '0;
    assign fetch_packet1.predictorIndex = predictionValid_i ? predictorIndex1_i : '0;
    assign fetch_packet1.historySnapshot = predictionValid_i ? historySnapshot1_i : '0;
    assign fetch_packet1.tageMeta = predictionValid_i ? tageMeta1_i : '0;
    assign fetch_packet1.predictedBtbHit = predictionValid_i && btbHit1_i;
    assign fetch_packet1.predictedRasUsed = predictionValid_i && rasUsed1_i;

    // A response can retire zero, one, or two instruction slots.  Redirects
    // override that flow immediately; an invalid or stalled response repeats
    // the last request so the registered predictor context stays aligned.
    always_comb begin
        nextRequestPc = pc;
        if (jump_enable)
            nextRequestPc = jump_address;
        else if (predictionValid_i && (pc_step_i != '0)) begin
            if (predictTaken_i)
                nextRequestPc = predictTarget_i;
            else if (predictTaken1_i &&
                     (pc_step_i == (PC_INCREMENT + PC_INCREMENT)))
                nextRequestPc = predictTarget1_i;
            else
                nextRequestPc = responsePc_i + pc_step_i;
        end
    end

    assign requestPc_o = nextRequestPc;
    assign requestPc1_o = nextRequestPc + PC_INCREMENT;

    always_ff @(posedge clk or negedge rst) begin
        if (!rst)
            pc <= RESET_PC;
        else
            pc <= nextRequestPc;
    end

    // Two read ports are modeled by two instruction-memory instances. This is
    // simple and simulator-friendly for the current one-word-per-line hex image.
    insnMem #(
        .ADDR_W(ADDR_W),
        .INSN_W(INSN_W),
        .MEM_ADDR_W(MEM_ADDR_W),
        .MEM_BYTES(MEM_BYTES),
        .MEM_FILE(MEM_FILE)
    ) insnMem0(
        .addr(requestPc_o),
        .instruction_o(requestInsn_o)
    );

    insnMem #(
        .ADDR_W(ADDR_W),
        .INSN_W(INSN_W),
        .MEM_ADDR_W(MEM_ADDR_W),
        .MEM_BYTES(MEM_BYTES),
        .MEM_FILE(MEM_FILE)
    ) insnMem1(
        .addr(requestPc1_o),
        .instruction_o(requestInsn1_o)
    );

endmodule
