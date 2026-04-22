module IfStages
    import TypesPkg::*;
#(
    parameter int ADDR_W = WORD_SIZE,
    parameter int INSN_W = INS_SIZE,
    parameter int MEM_ADDR_W = INS_ADDR,
    parameter int MEM_BYTES = INS_ADDR_SIZE,
    parameter logic [ADDR_W-1:0] RESET_PC = RESET_VECTOR,
    parameter logic [ADDR_W-1:0] PC_INCREMENT = 32'd4,
    parameter string MEM_FILE = "utils/insn.mem"
)
(
    input logic                clk,
    input logic                rst,
    input logic [ADDR_W-1:0]   jump_address,
    input logic                jump_enable,
    input logic                wrEnable,
    InstructionPacketIf.source fetch_packet
);

    PC #(
        .ADDR_W(ADDR_W),
        .RESET_PC(RESET_PC),
        .PC_INCREMENT(PC_INCREMENT)
    ) pcReg(
        .clk(clk),
        .rst(rst),
        .jump_enable(jump_enable),
        .wrEnable(wrEnable),
        .jump_address(jump_address),
        .pc_address_out(fetch_packet.pc)
    );

    insnMem #(
        .ADDR_W(ADDR_W),
        .INSN_W(INSN_W),
        .MEM_ADDR_W(MEM_ADDR_W),
        .MEM_BYTES(MEM_BYTES),
        .MEM_FILE(MEM_FILE)
    ) insnMem(
        .addr(fetch_packet.pc),
        .instruction_o(fetch_packet.insn)
    );

endmodule
