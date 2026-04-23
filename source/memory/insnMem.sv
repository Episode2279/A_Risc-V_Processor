module insnMem
    import TypesPkg::*;
#(
    // addr is byte addressed, but the memory array stores one 32-bit word per
    // line. MEM_ADDR_W defines how many byte-address bits are valid.
    parameter int ADDR_W = WORD_SIZE,
    parameter int INSN_W = INS_SIZE,
    parameter int MEM_ADDR_W = INS_ADDR,
    parameter int MEM_BYTES = INS_ADDR_SIZE,
    parameter string MEM_FILE = "utils/insn.mem"
)
(
    // Byte address from the PC.
    input  logic [ADDR_W-1:0] addr,
    // Combinational instruction word read from the initialized memory image.
    output logic [INSN_W-1:0] instruction_o
);

    // The hex file contains one instruction word per line, so byte capacity is
    // converted to a word count for the array bounds.
    localparam int INS_WORD_COUNT = MEM_BYTES / (INSN_W / 8);

    logic [INSN_W-1:0] mem [0:INS_WORD_COUNT-1];
    logic [$clog2(INS_WORD_COUNT)-1:0] wordAddr;

    initial begin
        // Simulation memory image. Vivado/Verilator tests may override this
        // with explicit $readmemh calls after elaboration.
        $readmemh(MEM_FILE, mem);
    end

    // Drop the low two byte-offset bits because each array entry is one word.
    assign wordAddr = addr[MEM_ADDR_W-1:2];
    // Instruction memory is intentionally combinational in this teaching core.
    assign instruction_o = mem[wordAddr];
endmodule
