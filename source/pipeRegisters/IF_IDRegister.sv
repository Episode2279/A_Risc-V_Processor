module IF_IDRegister
    import TypesPkg::*;
#(
    // PC value used when the register is reset or flushed into a bubble.
    parameter logic [WORD_SIZE-1:0] RESET_PC = RESET_VECTOR
)
(
    // IF/ID holds the fetched instruction packet for the decode stage.
    input logic                clk,
    input logic                rst,
    InstructionPacketIf.sink   packet_i,
    input logic                stall,
    input logic                flush,
    InstructionPacketIf.source packet_o
);

    always_ff @(posedge clk or negedge rst) begin
        if (~rst) begin
            // Active-low reset injects a zero instruction bubble.
            packet_o.insn <= '0;
            packet_o.pc <= RESET_PC;
        end else if (flush) begin
            // Branch/jump redirects squash the younger instruction in decode.
            packet_o.insn <= '0;
            packet_o.pc <= RESET_PC;
        end else if (!stall) begin
            // During a load-use stall this register holds its current packet
            // while ID/EX is cleared into a bubble.
            packet_o.insn <= packet_i.insn;
            packet_o.pc <= packet_i.pc;
        end
    end

endmodule
