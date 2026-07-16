module DualIF_IDRegister
    import TypesPkg::*;
#(
    parameter logic [WORD_SIZE-1:0] RESET_PC = RESET_VECTOR
)
(
    input logic                clk,
    input logic                rst,
    InstructionPacketIf.sink   fetch0_i,
    InstructionPacketIf.sink   fetch1_i,
    input logic                stall,
    input logic                flush,
    input logic                issue0,
    input logic                issue1,
    InstructionPacketIf.source packet0_o,
    InstructionPacketIf.source packet1_o
);

    always_ff @(posedge clk or negedge rst) begin
        if (~rst || flush) begin
            packet0_o.insn <= '0;
            packet0_o.pc <= RESET_PC;
            packet0_o.predictedTaken <= 1'b0;
            packet0_o.predictedTarget <= '0;
            packet0_o.predictorIndex <= '0;
            packet0_o.historySnapshot <= '0;
            packet0_o.predictedBtbHit <= 1'b0; packet0_o.predictedRasUsed <= 1'b0;
            packet1_o.insn <= '0;
            packet1_o.pc <= RESET_PC;
            packet1_o.predictedTaken <= 1'b0;
            packet1_o.predictedTarget <= '0;
            packet1_o.predictorIndex <= '0;
            packet1_o.historySnapshot <= '0;
            packet1_o.predictedBtbHit <= 1'b0; packet1_o.predictedRasUsed <= 1'b0;
        end else if (stall) begin
            packet0_o.insn <= packet0_o.insn;
            packet0_o.pc <= packet0_o.pc;
            packet0_o.predictedTaken <= packet0_o.predictedTaken;
            packet0_o.predictedTarget <= packet0_o.predictedTarget;
            packet0_o.predictorIndex <= packet0_o.predictorIndex;
            packet0_o.historySnapshot <= packet0_o.historySnapshot;
            packet0_o.predictedBtbHit <= packet0_o.predictedBtbHit; packet0_o.predictedRasUsed <= packet0_o.predictedRasUsed;
            packet1_o.insn <= packet1_o.insn;
            packet1_o.pc <= packet1_o.pc;
            packet1_o.predictedTaken <= packet1_o.predictedTaken;
            packet1_o.predictedTarget <= packet1_o.predictedTarget;
            packet1_o.predictorIndex <= packet1_o.predictorIndex;
            packet1_o.historySnapshot <= packet1_o.historySnapshot;
            packet1_o.predictedBtbHit <= packet1_o.predictedBtbHit; packet1_o.predictedRasUsed <= packet1_o.predictedRasUsed;
        end else if ((packet0_o.insn == '0) && (packet1_o.insn == '0)) begin
            // Fill an empty window after reset/flush.
            packet0_o.insn <= fetch0_i.insn;
            packet0_o.pc <= fetch0_i.pc;
            packet0_o.predictedTaken <= fetch0_i.predictedTaken;
            packet0_o.predictedTarget <= fetch0_i.predictedTarget;
            packet0_o.predictorIndex <= fetch0_i.predictorIndex;
            packet0_o.historySnapshot <= fetch0_i.historySnapshot;
            packet0_o.predictedBtbHit <= fetch0_i.predictedBtbHit; packet0_o.predictedRasUsed <= fetch0_i.predictedRasUsed;
            packet1_o.insn <= fetch1_i.insn;
            packet1_o.pc <= fetch1_i.pc;
            packet1_o.predictedTaken <= fetch1_i.predictedTaken;
            packet1_o.predictedTarget <= fetch1_i.predictedTarget;
            packet1_o.predictorIndex <= fetch1_i.predictorIndex;
            packet1_o.historySnapshot <= fetch1_i.historySnapshot;
            packet1_o.predictedBtbHit <= fetch1_i.predictedBtbHit; packet1_o.predictedRasUsed <= fetch1_i.predictedRasUsed;
        end else if (issue0 && issue1) begin
            // Both decoded slots issued, so replace the window with the next
            // two fetched instructions.
            packet0_o.insn <= fetch0_i.insn;
            packet0_o.pc <= fetch0_i.pc;
            packet0_o.predictedTaken <= fetch0_i.predictedTaken;
            packet0_o.predictedTarget <= fetch0_i.predictedTarget;
            packet0_o.predictorIndex <= fetch0_i.predictorIndex;
            packet0_o.historySnapshot <= fetch0_i.historySnapshot;
            packet0_o.predictedBtbHit <= fetch0_i.predictedBtbHit; packet0_o.predictedRasUsed <= fetch0_i.predictedRasUsed;
            packet1_o.insn <= fetch1_i.insn;
            packet1_o.pc <= fetch1_i.pc;
            packet1_o.predictedTaken <= fetch1_i.predictedTaken;
            packet1_o.predictedTarget <= fetch1_i.predictedTarget;
            packet1_o.predictorIndex <= fetch1_i.predictorIndex;
            packet1_o.historySnapshot <= fetch1_i.historySnapshot;
            packet1_o.predictedBtbHit <= fetch1_i.predictedBtbHit; packet1_o.predictedRasUsed <= fetch1_i.predictedRasUsed;
        end else if (issue0) begin
            if (packet1_o.insn == '0) begin
                // A taken prediction suppresses the sequential slot. Once the
                // branch issues, refill both slots from its predicted target.
                packet0_o.insn <= fetch0_i.insn;
                packet0_o.pc <= fetch0_i.pc;
                packet0_o.predictedTaken <= fetch0_i.predictedTaken;
                packet0_o.predictedTarget <= fetch0_i.predictedTarget;
                packet0_o.predictorIndex <= fetch0_i.predictorIndex;
                packet0_o.historySnapshot <= fetch0_i.historySnapshot;
                packet0_o.predictedBtbHit <= fetch0_i.predictedBtbHit; packet0_o.predictedRasUsed <= fetch0_i.predictedRasUsed;
                packet1_o.insn <= fetch1_i.insn;
                packet1_o.pc <= fetch1_i.pc;
                packet1_o.predictedTaken <= fetch1_i.predictedTaken;
                packet1_o.predictedTarget <= fetch1_i.predictedTarget;
                packet1_o.predictorIndex <= fetch1_i.predictorIndex;
                packet1_o.historySnapshot <= fetch1_i.historySnapshot;
                packet1_o.predictedBtbHit <= fetch1_i.predictedBtbHit; packet1_o.predictedRasUsed <= fetch1_i.predictedRasUsed;
            end else begin
                // Only the older decoded slot issued. Preserve the younger
                // instruction by sliding it into slot0, then append fetch0.
                packet0_o.insn <= packet1_o.insn;
                packet0_o.pc <= packet1_o.pc;
                packet0_o.predictedTaken <= packet1_o.predictedTaken;
                packet0_o.predictedTarget <= packet1_o.predictedTarget;
                packet0_o.predictorIndex <= packet1_o.predictorIndex;
                packet0_o.historySnapshot <= packet1_o.historySnapshot;
                packet0_o.predictedBtbHit <= packet1_o.predictedBtbHit; packet0_o.predictedRasUsed <= packet1_o.predictedRasUsed;
                packet1_o.insn <= fetch0_i.insn;
                packet1_o.pc <= fetch0_i.pc;
                packet1_o.predictedTaken <= fetch0_i.predictedTaken;
                packet1_o.predictedTarget <= fetch0_i.predictedTarget;
                packet1_o.predictorIndex <= fetch0_i.predictorIndex;
                packet1_o.historySnapshot <= fetch0_i.historySnapshot;
                packet1_o.predictedBtbHit <= fetch0_i.predictedBtbHit; packet1_o.predictedRasUsed <= fetch0_i.predictedRasUsed;
            end
        end
    end

endmodule
