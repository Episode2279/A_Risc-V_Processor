module IfStages
    import TypesPkg::*;
#(
    // Fetch-stage sizing and memory-image parameters.
    parameter int ADDR_W = WORD_SIZE,
    parameter int INSN_W = INS_SIZE,
    parameter int MEM_ADDR_W = INS_ADDR,
    parameter int MEM_BYTES = INS_ADDR_SIZE,
    parameter logic [ADDR_W-1:0] RESET_PC = RESET_VECTOR,
    parameter logic [ADDR_W-1:0] PC_INCREMENT = 32'd4,
    parameter string MEM_FILE = "utils/insn.mem"
)
(
    // Fetch stage owns the PC register and combinational instruction memory.
    input logic                clk,
    input logic                rst,
    // Redirect target and enable from execute-stage branch resolution.
    input logic [ADDR_W-1:0]   jump_address,
    input logic                jump_enable,
    input logic                wrEnable,
    InstructionPacketIf.source fetch_packet
);

    // PC updates only when wrEnable is asserted. A load-use stall therefore
    // freezes both PC and IF/ID so decode can retry the same instruction.
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

    // Instruction memory is combinational, so a new PC produces a same-cycle
    // instruction word for the IF packet.
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
