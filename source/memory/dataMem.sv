module dataMem
    import TypesPkg::*;
#(
    parameter int DATA_W = WORD_SIZE,
    parameter int LOGIC_ADDR_W = DATA_ADDR,
    parameter int MEM_BYTES = DATA_ADDR_SIZE,
    parameter logic [DATA_W-1:0] UART_TX_MMIO_ADDR = UART_TX_ADDR,
    parameter logic [DATA_W-1:0] FROMHOST_MMIO_ADDR = FROMHOST_ADDR,
    parameter logic [DATA_W-1:0] TOHOST_MMIO_ADDR = TOHOST_ADDR,
    parameter string MEM_FILE = "utils/data.mem"
)
(
    input  logic        clk,
    input  logic        rst,
    input  logic [DATA_W-1:0] logicAddr,
    input  mem_access_t accessCtr,
    input  logic        writeEnable,
    input  logic [DATA_W-1:0] data_i,
    input  logic [DATA_W-1:0] fromHost_i,
    output logic [DATA_W-1:0] data_o,
    output logic [DATA_W-1:0] toHost_o,
    output logic        uartValid_o,
    output logic [7:0]  uartData_o
);

    localparam int DATA_WORD_COUNT = MEM_BYTES / (DATA_W / 8);

    logic [DATA_W-1:0] mem [0:DATA_WORD_COUNT-1];
    logic [$clog2(DATA_WORD_COUNT)-1:0] wordAddr;
    logic [1:0]           byteOffset;
    logic [DATA_W-1:0]    readWord;
    logic [DATA_W-1:0]    toHostReg;
    logic                 uartHit;
    logic                 fromHostHit;
    logic                 toHostHit;

    function automatic logic [DATA_W-1:0] format_load(
        input logic [DATA_W-1:0] rawWord,
        input mem_access_t accessMode,
        input logic [1:0]  offset
    );
        logic [DATA_W-1:0] shiftedWord;
        begin
            // RV32 uses little-endian byte lanes, so offset 0 maps to the low byte.
            shiftedWord = rawWord >> (offset * 8);
            unique case (accessMode)
                MEM_BYTE:   format_load = {{24{shiftedWord[7]}}, shiftedWord[7:0]};
                MEM_HALF:   format_load = {{16{shiftedWord[15]}}, shiftedWord[15:0]};
                MEM_WORD:   format_load = rawWord;
                MEM_BYTE_U: format_load = {24'd0, shiftedWord[7:0]};
                MEM_HALF_U: format_load = {16'd0, shiftedWord[15:0]};
                default:    format_load = '0;
            endcase
        end
    endfunction

    function automatic logic [DATA_W-1:0] merge_store(
        input logic [DATA_W-1:0] currentWord,
        input logic [DATA_W-1:0] writeData,
        input mem_access_t accessMode,
        input logic [1:0]  offset
    );
        logic [DATA_W-1:0] mergedWord;
        begin
            mergedWord = currentWord;
            unique case (accessMode)
                MEM_BYTE: begin
                    unique case (offset)
                        2'd0: mergedWord[7:0]   = writeData[7:0];
                        2'd1: mergedWord[15:8]  = writeData[7:0];
                        2'd2: mergedWord[23:16] = writeData[7:0];
                        2'd3: mergedWord[31:24] = writeData[7:0];
                    endcase
                end
                MEM_HALF: begin
                    unique case (offset)
                        2'd0: mergedWord[15:0]  = writeData[15:0];
                        2'd1: mergedWord[23:8]  = writeData[15:0];
                        2'd2: mergedWord[31:16] = writeData[15:0];
                        default: mergedWord = currentWord;
                    endcase
                end
                default: begin
                    mergedWord = writeData;
                end
            endcase

            merge_store = mergedWord;
        end
    endfunction

    assign wordAddr = logicAddr[LOGIC_ADDR_W-1:2];
    assign byteOffset = logicAddr[1:0];
    // UART is byte-oriented: only the base byte address emits a character.
    // GCC may split volatile word stores into byte stores at +1/+2/+3.
    assign uartHit = (logicAddr == UART_TX_MMIO_ADDR);
    // Host registers are word-oriented locations exported by coremark/link.ld.
    assign fromHostHit = (logicAddr[DATA_W-1:2] == FROMHOST_MMIO_ADDR[DATA_W-1:2]);
    assign toHostHit = (logicAddr[DATA_W-1:2] == TOHOST_MMIO_ADDR[DATA_W-1:2]);
    assign toHost_o = toHostReg;

    initial begin
        $readmemh(MEM_FILE, mem);
    end

    always_comb begin
        if (fromHostHit) begin
            readWord = fromHost_i;
        end else if (toHostHit) begin
            readWord = toHostReg;
        end else if (uartHit) begin
            readWord = '0;
        end else begin
            readWord = mem[wordAddr];
        end

        data_o = format_load(readWord, accessCtr, byteOffset);
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            toHostReg <= '0;
            uartValid_o <= 1'b0;
            uartData_o <= '0;
        end else begin
            uartValid_o <= 1'b0;

            if (writeEnable) begin
                if (toHostHit) begin
                    toHostReg <= merge_store(toHostReg, data_i, accessCtr, byteOffset);
                end else if (uartHit) begin
                    uartValid_o <= 1'b1;
                    uartData_o <= data_i[7:0];
                end else if (!fromHostHit) begin
                    mem[wordAddr] <= merge_store(mem[wordAddr], data_i, accessCtr, byteOffset);
                end
            end
        end
    end

endmodule
