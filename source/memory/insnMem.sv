module insnMem
    import TypesPkg::*;
#(
    parameter int ADDR_W = WORD_SIZE,
    parameter int INSN_W = INS_SIZE,
    parameter int MEM_ADDR_W = INS_ADDR,
    parameter int MEM_BYTES = INS_ADDR_SIZE,
    parameter string MEM_FILE = "utils/insn.mem"
)
(
    input  logic [ADDR_W-1:0] addr,
    output logic [INSN_W-1:0] instruction_o
);

    localparam int INS_WORD_COUNT = MEM_BYTES / (INSN_W / 8);

    logic [INSN_W-1:0] mem [0:INS_WORD_COUNT-1];
    logic [$clog2(INS_WORD_COUNT)-1:0] wordAddr;

    initial begin
        $readmemh(MEM_FILE, mem);
    end

    assign wordAddr = addr[MEM_ADDR_W-1:2];
    assign instruction_o = mem[wordAddr];
endmodule
