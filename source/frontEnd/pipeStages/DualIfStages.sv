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
    input  logic              predictTaken_i,
    input  logic [ADDR_W-1:0] predictTarget_i,
    input  bpu_index_t        predictorIndex_i,
    input  logic              predictTaken1_i,
    input  logic [ADDR_W-1:0] predictTarget1_i,
    input  bpu_index_t        predictorIndex1_i,
    input  logic [BPU_HISTORY_WIDTH-1:0] historySnapshot_i,
    input  logic [BPU_HISTORY_WIDTH-1:0] historySnapshot1_i,
    input logic btbHit_i,btbHit1_i,rasUsed_i,rasUsed1_i,
    // pc_step_i is 0/4/8 for stall, single issue, or dual issue.
    input  logic [ADDR_W-1:0] pc_step_i,
    InstructionPacketIf.source fetch_packet0,
    InstructionPacketIf.source fetch_packet1
);

    logic [ADDR_W-1:0] pc;
    logic [ADDR_W-1:0] pc_plus4;
    logic [INSN_W-1:0] fetchInsn0;
    logic [INSN_W-1:0] fetchInsn1;

    assign pc_plus4 = pc + PC_INCREMENT;
    assign fetch_packet0.pc = pc;
    assign fetch_packet1.pc = pc_plus4;
    assign fetch_packet0.insn = fetchInsn0;
    // Only slot 0 is currently queried in the BTB. Suppress the sequential
    // slot when it predicts taken so a wrong-path instruction is not decoded.
    assign fetch_packet1.insn = (predictTaken_i && (pc_step_i != '0)) ?
                                '0 : fetchInsn1;
    assign fetch_packet0.predictedTaken = predictTaken_i &&
                                           (pc_step_i != '0);
    assign fetch_packet0.predictedTarget = predictTarget_i;
    assign fetch_packet0.predictorIndex = predictorIndex_i;
    assign fetch_packet0.historySnapshot = historySnapshot_i;
    assign fetch_packet0.predictedBtbHit = btbHit_i;
    assign fetch_packet0.predictedRasUsed = rasUsed_i;
    assign fetch_packet1.predictedTaken = predictTaken1_i &&
                                           !predictTaken_i && (pc_step_i == 32'd8);
    assign fetch_packet1.predictedTarget = predictTarget1_i;
    assign fetch_packet1.predictorIndex = predictorIndex1_i;
    assign fetch_packet1.historySnapshot = historySnapshot1_i;
    assign fetch_packet1.predictedBtbHit = btbHit1_i;
    assign fetch_packet1.predictedRasUsed = rasUsed1_i;

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            pc <= RESET_PC;
        end else if (jump_enable) begin
            // Execute-stage redirects take priority over sequential issue width.
            pc <= jump_address;
        end else if (predictTaken_i && (pc_step_i != '0)) begin
            pc <= predictTarget_i;
        end else if (predictTaken1_i && (pc_step_i == 32'd8)) begin
            pc <= predictTarget1_i;
        end else begin
            pc <= pc + pc_step_i;
        end
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
        .addr(fetch_packet0.pc),
        .instruction_o(fetchInsn0)
    );

    insnMem #(
        .ADDR_W(ADDR_W),
        .INSN_W(INSN_W),
        .MEM_ADDR_W(MEM_ADDR_W),
        .MEM_BYTES(MEM_BYTES),
        .MEM_FILE(MEM_FILE)
    ) insnMem1(
        .addr(fetch_packet1.pc),
        .instruction_o(fetchInsn1)
    );

endmodule
