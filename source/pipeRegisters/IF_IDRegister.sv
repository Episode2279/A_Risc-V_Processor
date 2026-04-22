module IF_IDRegister
    import TypesPkg::*;
#(
    parameter logic [WORD_SIZE-1:0] RESET_PC = RESET_VECTOR
)
(
    input logic                clk,
    input logic                rst,
    InstructionPacketIf.sink   packet_i,
    input logic                stall,
    input logic                flush,
    InstructionPacketIf.source packet_o
);

    always_ff @(posedge clk or negedge rst) begin
        if (~rst) begin
            packet_o.insn <= '0;
            packet_o.pc <= RESET_PC;
        end else if (flush) begin
            packet_o.insn <= '0;
            packet_o.pc <= RESET_PC;
        end else if (!stall) begin
            packet_o.insn <= packet_i.insn;
            packet_o.pc <= packet_i.pc;
        end
    end

endmodule
