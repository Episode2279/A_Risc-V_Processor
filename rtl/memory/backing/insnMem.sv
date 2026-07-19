// Single-port, one-cycle instruction backing memory.
//
// This module models the memory below the instruction cache.  A request is
// accepted whenever requestReady_o is asserted; its word is returned with
// responseValid_o one cycle later.  The array remains visible as `mem` so the
// existing simulation testbench can continue to override the initialized
// image hierarchically.
module insnMem
    import TypesPkg::*;
#(
    parameter int ADDR_W = WORD_SIZE,
    parameter int INSN_W = INS_SIZE,
    parameter int MEM_ADDR_W = INS_ADDR,
    parameter int MEM_BYTES = INS_ADDR_SIZE,
    parameter string MEM_FILE = "build/images/insn.mem"
)
(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  requestValid_i,
    output logic                  requestReady_o,
    input  logic [ADDR_W-1:0]     requestAddr_i,
    output logic                  responseValid_o,
    output logic [INSN_W-1:0]     responseWord_o
);

    localparam int INS_WORD_COUNT = MEM_BYTES / (INSN_W / 8);

    (* rom_style = "block", ram_style = "block" *)
    logic [INSN_W-1:0] mem [0:INS_WORD_COUNT-1];
    logic [$clog2(INS_WORD_COUNT)-1:0] requestWordAddr;
    string runtimeMemFile;

    initial begin
        if ($value$plusargs("insn-mem=%s", runtimeMemFile))
            $readmemh(runtimeMemFile, mem);
        else
            $readmemh(MEM_FILE, mem);
    end

    // The backing store is never back-pressured.  Keeping the response in an
    // always_ff block gives the cache a deterministic one-cycle lower-memory
    // latency and maps naturally to a single-port synchronous ROM/BRAM.
    assign requestReady_o = 1'b1;
    assign requestWordAddr = requestAddr_i[MEM_ADDR_W-1:2];

    // Keep the ROM read itself reset-free so synthesis can map `mem` to a
    // physical synchronous ROM/BRAM.  responseValid_o makes stale/uninitialised
    // output-register contents unobservable after reset.
    always_ff @(posedge clk) begin
        if (requestValid_i && requestReady_o)
            responseWord_o <= mem[requestWordAddr];
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst)
            responseValid_o <= 1'b0;
        else
            responseValid_o <= requestValid_i && requestReady_o;
    end

endmodule
