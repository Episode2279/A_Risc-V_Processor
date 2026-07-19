module dataMem
    import TypesPkg::*;
#(
    parameter int DATA_W = WORD_SIZE,
    parameter int LOGIC_ADDR_W = DATA_ADDR,
    parameter int MEM_BYTES = DATA_ADDR_SIZE,
    parameter logic [DATA_W-1:0] UART_TX_MMIO_ADDR = UART_TX_ADDR,
    parameter logic [DATA_W-1:0] FROMHOST_MMIO_ADDR = FROMHOST_ADDR,
    parameter logic [DATA_W-1:0] TOHOST_MMIO_ADDR = TOHOST_ADDR,
    parameter string MEM_FILE = "build/images/data.mem"
)
(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  requestValid_i,
    output logic                  requestReady_o,
    input  logic                  requestWrite_i,
    input  logic [DATA_W-1:0]     requestAddress_i,
    input  logic [DATA_W-1:0]     requestWriteData_i,
    input  mem_access_t           requestAccess_i,
    output logic                  responseValid_o,
    input  logic                  responseReady_i,
    output logic [DATA_W-1:0]     responseData_o,
    input  logic [DATA_W-1:0]     fromHost_i,
    output logic [DATA_W-1:0]     toHost_o,
    output logic                  uartValid_o,
    output logic [7:0]            uartData_o,
    output logic                  toHostHit_o,
    output logic                  uartHit_o,
    output logic                  fromHostHit_o
);

    localparam int DATA_WORD_COUNT = MEM_BYTES / (DATA_W / 8);

    // This array remains directly below dut.memStage.dataMem so the existing
    // testbench can continue loading and inspecting the backing-memory image.
    (* ram_style = "block" *)
    logic [DATA_W-1:0] mem [0:DATA_WORD_COUNT-1];

    logic [$clog2(DATA_WORD_COUNT)-1:0] wordAddr;
    logic [1:0]           byteOffset;
    logic [DATA_W-1:0]    readWordReg;
    mem_access_t          readAccessReg;
    logic [1:0]           readByteOffsetReg;
    logic                 responseValidReg;
    logic [DATA_W-1:0]    toHostReg;
    logic                 uartHit;
    logic                 fromHostHit;
    logic                 toHostHit;
    logic                 requestFire;
    logic                 responseSlotAvailable;
    logic [3:0]           writeByteEnable;
    logic [DATA_W-1:0]    shiftedWriteData;
    string                runtimeMemFile;
    integer               storeLane;

    function automatic logic [DATA_W-1:0] formatLoad(
        input logic [DATA_W-1:0] rawWord,
        input mem_access_t       accessMode,
        input logic [1:0]        offset
    );
        logic [DATA_W-1:0] shiftedWord;
        begin
            shiftedWord = rawWord >> (offset * 8);
            unique case (accessMode)
                MEM_BYTE:   formatLoad = {{24{shiftedWord[7]}}, shiftedWord[7:0]};
                MEM_HALF:   formatLoad = {{16{shiftedWord[15]}}, shiftedWord[15:0]};
                MEM_WORD:   formatLoad = rawWord;
                MEM_BYTE_U: formatLoad = {24'd0, shiftedWord[7:0]};
                MEM_HALF_U: formatLoad = {16'd0, shiftedWord[15:0]};
                default:    formatLoad = '0;
            endcase
        end
    endfunction

    function automatic logic [3:0] storeByteMask(
        input mem_access_t accessMode,
        input logic [1:0]  offset
    );
        begin
            unique case (accessMode)
                MEM_BYTE: storeByteMask = 4'b0001 << offset;
                MEM_HALF: storeByteMask = (offset == 2'd3) ? 4'b0000 :
                                                        (4'b0011 << offset);
                default:  storeByteMask = 4'b1111;
            endcase
        end
    endfunction

    function automatic logic [DATA_W-1:0] alignStoreData(
        input logic [DATA_W-1:0] writeData,
        input mem_access_t       accessMode,
        input logic [1:0]        offset
    );
        begin
            unique case (accessMode)
                MEM_BYTE: alignStoreData = word_t'(writeData[7:0]) << (offset * 8);
                MEM_HALF: alignStoreData = word_t'(writeData[15:0]) << (offset * 8);
                default:  alignStoreData = writeData;
            endcase
        end
    endfunction

    function automatic logic [DATA_W-1:0] mergeStore(
        input logic [DATA_W-1:0] currentWord,
        input logic [DATA_W-1:0] alignedData,
        input logic [3:0]        byteEnable
    );
        logic [DATA_W-1:0] mergedWord;
        integer lane;
        begin
            mergedWord = currentWord;
            for (lane = 0; lane < 4; lane = lane + 1)
                if (byteEnable[lane])
                    mergedWord[lane*8 +: 8] = alignedData[lane*8 +: 8];
            mergeStore = mergedWord;
        end
    endfunction

    assign wordAddr = requestAddress_i[LOGIC_ADDR_W-1:2];
    assign byteOffset = requestAddress_i[1:0];
    assign uartHit = (requestAddress_i == UART_TX_MMIO_ADDR);
    assign fromHostHit =
        (requestAddress_i[DATA_W-1:2] == FROMHOST_MMIO_ADDR[DATA_W-1:2]);
    assign toHostHit =
        (requestAddress_i[DATA_W-1:2] == TOHOST_MMIO_ADDR[DATA_W-1:2]);

    assign responseSlotAvailable = !responseValidReg || responseReady_i;
    // Stores do not consume the load-response register.  Reads are accepted
    // only when that register is free or being consumed on the same edge.
    assign requestReady_o = rst && (requestWrite_i || responseSlotAvailable);
    assign requestFire = requestValid_i && requestReady_o;
    assign responseValid_o = responseValidReg;
    assign responseData_o = formatLoad(
        readWordReg, readAccessReg, readByteOffsetReg);

    assign writeByteEnable = storeByteMask(requestAccess_i, byteOffset);
    assign shiftedWriteData = alignStoreData(
        requestWriteData_i, requestAccess_i, byteOffset);

    assign toHost_o = toHostReg;
    assign toHostHit_o = toHostHit;
    assign uartHit_o = uartHit;
    assign fromHostHit_o = fromHostHit;

    initial begin
        if ($value$plusargs("data-mem=%s", runtimeMemFile))
            $readmemh(runtimeMemFile, mem);
        else
            $readmemh(MEM_FILE, mem);
    end

    // Reset-free synchronous backing-RAM port.  Reads register their data on
    // the accepting edge; Stores use byte-write enables on that same clocked
    // port.  Keeping RAM access out of the resettable control process is
    // important for BRAM inference.  MMIO values share the registered read
    // response but never access the RAM array.
    always_ff @(posedge clk) begin
        if (requestFire) begin
            if (requestWrite_i) begin
                if (!toHostHit && !uartHit && !fromHostHit) begin
                    for (storeLane = 0; storeLane < 4;
                         storeLane = storeLane + 1) begin
                        if (writeByteEnable[storeLane])
                            mem[wordAddr][storeLane*8 +: 8] <=
                                shiftedWriteData[storeLane*8 +: 8];
                    end
                end
            end else begin
                if (fromHostHit)
                    readWordReg <= fromHost_i;
                else if (toHostHit)
                    readWordReg <= toHostReg;
                else if (uartHit)
                    readWordReg <= '0;
                else
                    readWordReg <= mem[wordAddr];
            end
        end
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            readAccessReg <= MEM_WORD;
            readByteOffsetReg <= '0;
            responseValidReg <= 1'b0;
            toHostReg <= '0;
            uartValid_o <= 1'b0;
            uartData_o <= '0;
        end else begin
            uartValid_o <= 1'b0;

            if (responseValidReg && responseReady_i)
                responseValidReg <= 1'b0;

            if (requestFire) begin
                if (requestWrite_i) begin
                    if (toHostHit) begin
                        toHostReg <= mergeStore(
                            toHostReg, shiftedWriteData, writeByteEnable);
                    end else if (uartHit) begin
                        // requestFire qualifies the pulse, so a stalled request
                        // cannot emit the same UART byte more than once.
                        uartValid_o <= 1'b1;
                        uartData_o <= requestWriteData_i[7:0];
                    end
                end else begin
                    readAccessReg <= requestAccess_i;
                    readByteOffsetReg <= byteOffset;
                    responseValidReg <= 1'b1;
                end
            end
        end
    end

endmodule
