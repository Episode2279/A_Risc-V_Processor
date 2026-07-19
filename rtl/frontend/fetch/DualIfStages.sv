module DualIfStages
    import TypesPkg::*;
#(
    parameter int ADDR_W = WORD_SIZE,
    parameter int INSN_W = INS_SIZE,
    parameter int MEM_ADDR_W = INS_ADDR,
    parameter int MEM_BYTES = INS_ADDR_SIZE,
    parameter int ICACHE_BYTES = 4096,
    parameter int ICACHE_LINE_BYTES = 16,
    parameter logic [ADDR_W-1:0] RESET_PC = RESET_VECTOR,
    parameter logic [ADDR_W-1:0] PC_INCREMENT = 32'd4,
    parameter string MEM_FILE = "build/images/insn.mem"
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
    input  logic btbHit_i,btbHit1_i,rasUsed_i,rasUsed1_i,
    // pc_step_i is 0/4/8 for stall, single issue, or dual issue.
    input  logic [ADDR_W-1:0] pc_step_i,

    // F0 request handshake. requestValid_o is an accepted-request pulse: the
    // instruction cache and BPU sample requestPc_o/requestPc1_o together on an
    // edge where it is high. requestReady_i is the BPU-side readiness input.
    input  logic              requestReady_i,
    output logic              requestValid_o,
    output logic [ADDR_W-1:0] requestPc_o,
    output logic [INSN_W-1:0] requestInsn_o,
    output logic [ADDR_W-1:0] requestPc1_o,
    output logic [INSN_W-1:0] requestInsn1_o,
    // F1 instruction-data validity, aligned with requestInsn_o/requestInsn1_o.
    output logic              cacheResponseValid_o,
    output logic [63:0]       perfRequestCount_o,
    output logic [63:0]       perfHitCount_o,
    output logic [63:0]       perfMissCount_o,
    output logic [63:0]       perfLineMissCount_o,
    output logic [63:0]       perfMissStallCycles_o,
    output logic [63:0]       perfRefillLineCount_o,
    output logic [63:0]       perfRefillCycles_o,
    output logic [63:0]       perfCrosslineMissCount_o,
    output logic [63:0]       perfResponseBackpressureCycles_o,

    InstructionPacketIf.source fetch_packet0,
    InstructionPacketIf.source fetch_packet1
);

    logic [ADDR_W-1:0] pc;
    logic [ADDR_W-1:0] nextRequestPc;
    logic predictionResponseUsable;
    logic predictionResponseConsumed;

    logic cacheRequestReady;
    logic cacheResponseValid;
    logic cacheResponseReady;
    logic [INSN_W-1:0] cacheResponseInsn;
    logic [INSN_W-1:0] cacheResponseInsn1;

    logic backingRequestValid;
    logic backingRequestReady;
    logic [ADDR_W-1:0] backingRequestAddr;
    logic backingResponseValid;
    logic [INSN_W-1:0] backingResponseWord;

    // A fetch response is useful only when both the synchronous I-cache lookup
    // and predictor lookup describe the same accepted F0 request.  A redirect
    // suppresses the old response combinationally; IF/ID is flushed on the same
    // edge and the redirect request may launch immediately.
    assign predictionResponseUsable = cacheResponseValid &&
        predictionValid_i && !jump_enable;
    assign predictionResponseConsumed = predictionResponseUsable &&
        (pc_step_i != '0);
    assign cacheResponseReady = jump_enable || predictionResponseConsumed;
    assign cacheResponseValid_o = cacheResponseValid;

    // The retained PC is the oldest fetch address that has not produced a
    // consumed response.  Consumption can update it even when the BPU is not
    // ready for a same-edge replacement request; the new address then remains
    // pending until both request endpoints become ready.
    always_comb begin
        nextRequestPc = pc;
        if (jump_enable)
            nextRequestPc = jump_address;
        else if (predictionResponseConsumed) begin
            if (predictTaken_i)
                nextRequestPc = predictTarget_i;
            else if (predictTaken1_i &&
                     (pc_step_i == (PC_INCREMENT + PC_INCREMENT)))
                nextRequestPc = predictTarget1_i;
            else
                nextRequestPc = responsePc_i + pc_step_i;
        end
    end

    // When the current response is consumed, nextRequestPc is visible early
    // enough to replace it in the I-cache lookup register on that same edge.
    // During miss/refill or downstream stall cacheRequestReady is low, so no
    // duplicate request is presented to the BPU.
    assign requestPc_o = nextRequestPc;
    assign requestPc1_o = nextRequestPc + PC_INCREMENT;
    assign requestValid_o = rst && cacheRequestReady && requestReady_i;

    always_ff @(posedge clk or negedge rst) begin
        if (!rst)
            pc <= RESET_PC;
        else
            pc <= nextRequestPc;
    end

    // The packet instruction comes directly from the I-cache F1 response.  The
    // legacy responseInsn inputs remain on the interface while the BPU is being
    // converted to parallel PC-only F0 lookup; predictor PC/meta outputs still
    // provide the response context used below.
    assign fetch_packet0.pc = predictionResponseUsable ? responsePc_i : RESET_PC;
    assign fetch_packet1.pc = predictionResponseUsable ? responsePc1_i : RESET_PC;
    assign fetch_packet0.insn = predictionResponseUsable ? cacheResponseInsn : '0;
    assign fetch_packet1.insn = predictionResponseUsable &&
        !(predictTaken_i && (pc_step_i != '0)) ? cacheResponseInsn1 : '0;
    assign fetch_packet0.predictedTaken = predictionResponseUsable &&
        predictTaken_i && (pc_step_i != '0);
    assign fetch_packet0.predictedTarget = predictionResponseUsable ?
        predictTarget_i : '0;
    assign fetch_packet0.predictorIndex = predictionResponseUsable ?
        predictorIndex_i : '0;
    assign fetch_packet0.historySnapshot = predictionResponseUsable ?
        historySnapshot_i : '0;
    assign fetch_packet0.tageMeta = predictionResponseUsable ? tageMeta_i : '0;
    assign fetch_packet0.predictedBtbHit = predictionResponseUsable && btbHit_i;
    assign fetch_packet0.predictedRasUsed = predictionResponseUsable && rasUsed_i;

    assign fetch_packet1.predictedTaken = predictionResponseUsable &&
        predictTaken1_i && !predictTaken_i &&
        (pc_step_i == (PC_INCREMENT + PC_INCREMENT));
    assign fetch_packet1.predictedTarget = predictionResponseUsable ?
        predictTarget1_i : '0;
    assign fetch_packet1.predictorIndex = predictionResponseUsable ?
        predictorIndex1_i : '0;
    assign fetch_packet1.historySnapshot = predictionResponseUsable ?
        historySnapshot1_i : '0;
    assign fetch_packet1.tageMeta = predictionResponseUsable ? tageMeta1_i : '0;
    assign fetch_packet1.predictedBtbHit = predictionResponseUsable && btbHit1_i;
    assign fetch_packet1.predictedRasUsed = predictionResponseUsable && rasUsed1_i;

    assign requestInsn_o = cacheResponseInsn;
    assign requestInsn1_o = cacheResponseInsn1;

    InstructionCache #(
        .ADDR_W(ADDR_W),
        .INSN_W(INSN_W),
        .CACHE_BYTES(ICACHE_BYTES),
        .LINE_BYTES(ICACHE_LINE_BYTES)
    ) instructionCache (
        .clk(clk),
        .rst(rst),
        .flush_i(jump_enable),
        .requestValid_i(requestValid_o),
        .requestReady_o(cacheRequestReady),
        .requestPc_i(requestPc_o),
        .requestPc1_i(requestPc1_o),
        .responseValid_o(cacheResponseValid),
        .responseReady_i(cacheResponseReady),
        .responseInsn_o(cacheResponseInsn),
        .responseInsn1_o(cacheResponseInsn1),
        .backingRequestValid_o(backingRequestValid),
        .backingRequestReady_i(backingRequestReady),
        .backingRequestAddr_o(backingRequestAddr),
        .backingResponseValid_i(backingResponseValid),
        .backingResponseWord_i(backingResponseWord),
        .perfRequestCount_o(perfRequestCount_o),
        .perfHitCount_o(perfHitCount_o),
        .perfMissCount_o(perfMissCount_o),
        .perfLineMissCount_o(perfLineMissCount_o),
        .perfMissStallCycles_o(perfMissStallCycles_o),
        .perfRefillLineCount_o(perfRefillLineCount_o),
        .perfRefillCycles_o(perfRefillCycles_o),
        .perfCrosslineMissCount_o(perfCrosslineMissCount_o),
        .perfResponseBackpressureCycles_o(
            perfResponseBackpressureCycles_o)
    );

    // Preserve the instance name insnMem0 so existing runtime image-loading
    // code needs only to drop the former second replicated memory instance.
    insnMem #(
        .ADDR_W(ADDR_W),
        .INSN_W(INSN_W),
        .MEM_ADDR_W(MEM_ADDR_W),
        .MEM_BYTES(MEM_BYTES),
        .MEM_FILE(MEM_FILE)
    ) insnMem0 (
        .clk(clk),
        .rst(rst),
        .requestValid_i(backingRequestValid),
        .requestReady_o(backingRequestReady),
        .requestAddr_i(backingRequestAddr),
        .responseValid_o(backingResponseValid),
        .responseWord_o(backingResponseWord)
    );

endmodule
