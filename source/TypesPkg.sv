package TypesPkg;

    // Central package for project-wide data widths, memory sizes, and control types.
    // Modules may override these defaults locally, but these values define the
    // baseline RV32-style configuration used by the current core.

    // Width of the main integer datapath, register file entries, and ALU results.
    parameter int WORD_SIZE = 32;
    // Width of one fetched instruction word.
    parameter int INS_SIZE = 32;
    // Generic small block width used by utility logic that handles byte-like data.
    parameter int BLOCK_SIZE = 8;
    // Total instruction memory capacity in bytes.
    parameter int INS_ADDR_SIZE = 65536;
    // Total data memory capacity in bytes.
    parameter int DATA_ADDR_SIZE = 65536;
    // Number of architectural integer registers in the register file.
    parameter int REG_NUM = 32;
    // Encoded width needed to address one register entry.
    parameter int REG_ADDR = 5;

    // Derived address widths used by memory index signals inside the design.
    localparam int INS_ADDR = $clog2(INS_ADDR_SIZE);
    localparam int DATA_ADDR = $clog2(DATA_ADDR_SIZE);

    // Common scalar types shared across modules and interfaces.
    typedef logic [WORD_SIZE-1:0] word_t;
    typedef logic [INS_SIZE-1:0] instruction_t;
    typedef logic [BLOCK_SIZE-1:0] block_t;
    typedef logic [DATA_ADDR-1:0] data_addr_t;
    typedef logic [REG_ADDR-1:0] reg_addr_t;
    // Program counter and instruction addresses use full datapath width.
    typedef word_t instruction_addr_t;

    // Reset and MMIO map used by the testbench and software images.
    localparam word_t RESET_VECTOR = '0;
    localparam word_t UART_TX_ADDR = 32'h0000_FFE0;
    localparam word_t FROMHOST_ADDR = 32'h0000_FFF0;
    localparam word_t TOHOST_ADDR = 32'h0000_FFF8;

    // ALU control encoding selected by the decoder/controller path.
    typedef enum logic [3:0] {
        ALU_ADD  = 4'd0,
        ALU_SUB  = 4'd1,
        ALU_AND  = 4'd2,
        ALU_OR   = 4'd3,
        ALU_XOR  = 4'd4,
        ALU_SLL  = 4'd5,
        ALU_SRL  = 4'd6,
        ALU_SRA  = 4'd7,
        ALU_SLT  = 4'd8,
        ALU_SLTU = 4'd9,
        ALU_PASS = 4'd10
    } alu_ctr_t;

    // Write-back source selection for the final result sent to the register file.
    typedef enum logic [1:0] {
        WB_ALU = 2'b00,
        WB_MEM = 2'b01,
        WB_PC4 = 2'b10,
        WB_IMM = 2'b11
    } wb_select_t;

    // Branch/jump operation selected in decode and resolved in execute.
    typedef enum logic [3:0] {
        BR_NONE = 4'd0,
        BR_BEQ  = 4'd1,
        BR_BNE  = 4'd2,
        BR_BLT  = 4'd3,
        BR_BGE  = 4'd4,
        BR_BLTU = 4'd5,
        BR_BGEU = 4'd6,
        BR_JAL  = 4'd7,
        BR_JALR = 4'd8
    } branch_ctr_t;

    // Load/store access type used by the data memory for sign/zero extension
    // and write masking behavior.
    typedef enum logic [2:0] {
        MEM_BYTE   = 3'b000,
        MEM_HALF   = 3'b001,
        MEM_WORD   = 3'b010,
        MEM_BYTE_U = 3'b100,
        MEM_HALF_U = 3'b101
    } mem_access_t;

endpackage
