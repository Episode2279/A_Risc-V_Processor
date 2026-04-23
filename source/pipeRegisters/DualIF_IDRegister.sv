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
            packet1_o.insn <= '0;
            packet1_o.pc <= RESET_PC;
        end else if (stall) begin
            packet0_o.insn <= packet0_o.insn;
            packet0_o.pc <= packet0_o.pc;
            packet1_o.insn <= packet1_o.insn;
            packet1_o.pc <= packet1_o.pc;
        end else if ((packet0_o.insn == '0) && (packet1_o.insn == '0)) begin
            // Fill an empty window after reset/flush.
            packet0_o.insn <= fetch0_i.insn;
            packet0_o.pc <= fetch0_i.pc;
            packet1_o.insn <= fetch1_i.insn;
            packet1_o.pc <= fetch1_i.pc;
        end else if (issue0 && issue1) begin
            // Both decoded slots issued, so replace the window with the next
            // two fetched instructions.
            packet0_o.insn <= fetch0_i.insn;
            packet0_o.pc <= fetch0_i.pc;
            packet1_o.insn <= fetch1_i.insn;
            packet1_o.pc <= fetch1_i.pc;
        end else if (issue0) begin
            // Only the older decoded slot issued. Preserve the younger decoded
            // instruction by sliding it into slot0, then append the next fetched
            // instruction after it.
            packet0_o.insn <= packet1_o.insn;
            packet0_o.pc <= packet1_o.pc;
            packet1_o.insn <= fetch0_i.insn;
            packet1_o.pc <= fetch0_i.pc;
        end
    end

endmodule
