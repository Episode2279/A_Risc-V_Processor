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
    // pc_step_i is 0/4/8 for stall, single issue, or dual issue.
    input  logic [ADDR_W-1:0] pc_step_i,
    InstructionPacketIf.source fetch_packet0,
    InstructionPacketIf.source fetch_packet1
);

    logic [ADDR_W-1:0] pc;
    logic [ADDR_W-1:0] pc_plus4;

    assign pc_plus4 = pc + PC_INCREMENT;
    assign fetch_packet0.pc = pc;
    assign fetch_packet1.pc = pc_plus4;

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            pc <= RESET_PC;
        end else if (jump_enable) begin
            // Execute-stage redirects take priority over sequential issue width.
            pc <= jump_address;
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
        .instruction_o(fetch_packet0.insn)
    );

    insnMem #(
        .ADDR_W(ADDR_W),
        .INSN_W(INSN_W),
        .MEM_ADDR_W(MEM_ADDR_W),
        .MEM_BYTES(MEM_BYTES),
        .MEM_FILE(MEM_FILE)
    ) insnMem1(
        .addr(fetch_packet1.pc),
        .instruction_o(fetch_packet1.insn)
    );

endmodule
