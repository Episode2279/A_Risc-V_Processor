module MEMStages
    import TypesPkg::*;
#(
    parameter int DATA_W = WORD_SIZE,
    parameter int LOGIC_ADDR_W = DATA_ADDR,
    parameter int MEM_BYTES = DATA_ADDR_SIZE,
    parameter int CACHE_SET_COUNT = 64,
    parameter int CACHE_LINE_BYTES = 16,
    parameter logic [DATA_W-1:0] UART_TX_MMIO_ADDR = UART_TX_ADDR,
    parameter logic [DATA_W-1:0] FROMHOST_MMIO_ADDR = FROMHOST_ADDR,
    parameter logic [DATA_W-1:0] TOHOST_MMIO_ADDR = TOHOST_ADDR,
    parameter logic [DATA_W-1:0] MMIO_BASE_ADDR = 32'h0000_FFE0,
    parameter logic [DATA_W-1:0] MMIO_LAST_ADDR = 32'h0000_FFFF,
    parameter string MEM_FILE = "build/images/data.mem"
)
(
    input  logic                  clk,
    input  logic                  rst,
    input  logic [DATA_W-1:0]     fromHost_i,

    input  logic                  requestValid_i,
    output logic                  requestReady_o,
    input  logic                  requestWrite_i,
    input  rob_tag_t              requestId_i,
    input  logic [DATA_W-1:0]     requestAddress_i,
    input  logic [DATA_W-1:0]     requestWriteData_i,
    input  mem_access_t           requestAccess_i,
    output logic                  responseValid_o,
    input  logic                  responseReady_i,
    output rob_tag_t              responseId_o,
    output logic                  idle_o,
    output logic [DATA_W-1:0]     responseData_o,

    output logic [DATA_W-1:0]     toHost_o,
    output logic                  uartValid_o,
    output logic [7:0]            uartData_o,
    output logic                  toHostHit_o,
    output logic                  uartHit_o,
    output logic                  fromHostHit_o
    ,output logic [63:0]          perfRequestCount_o
    ,output logic [63:0]          perfLoadHitCount_o
    ,output logic [63:0]          perfLoadMissCount_o
    ,output logic [63:0]          perfStoreHitCount_o
    ,output logic [63:0]          perfStoreMissCount_o
    ,output logic [63:0]          perfBusyCycles_o
    ,output logic [63:0]          perfRefillLineCount_o
    ,output logic [63:0]          perfRefillCycles_o
    ,output logic [63:0]          perfMmioRequestCount_o
    ,output logic [63:0]          perfRequestBackpressureCycles_o
);

    logic              memoryRequestValid;
    logic              memoryRequestReady;
    logic              memoryRequestWrite;
    logic [DATA_W-1:0] memoryRequestAddress;
    logic [DATA_W-1:0] memoryRequestWriteData;
    mem_access_t       memoryRequestAccess;
    logic              memoryResponseValid;
    logic              memoryResponseReady;
    logic [DATA_W-1:0] memoryResponseData;

    DataCache #(
        .DATA_W(DATA_W),
        .ADDR_W(DATA_W),
        .SET_COUNT(CACHE_SET_COUNT),
        .LINE_BYTES(CACHE_LINE_BYTES),
        .MMIO_BASE_ADDR(MMIO_BASE_ADDR),
        .MMIO_LAST_ADDR(MMIO_LAST_ADDR)
    ) dataCache (
        .clk(clk),
        .rst(rst),
        .requestValid_i(requestValid_i),
        .requestReady_o(requestReady_o),
        .requestWrite_i(requestWrite_i),
        .requestId_i(requestId_i),
        .requestAddress_i(requestAddress_i),
        .requestWriteData_i(requestWriteData_i),
        .requestAccess_i(requestAccess_i),
        .responseValid_o(responseValid_o),
        .responseReady_i(responseReady_i),
        .responseId_o(responseId_o),
        .idle_o(idle_o),
        .responseData_o(responseData_o),
        .memoryRequestValid_o(memoryRequestValid),
        .memoryRequestReady_i(memoryRequestReady),
        .memoryRequestWrite_o(memoryRequestWrite),
        .memoryRequestAddress_o(memoryRequestAddress),
        .memoryRequestWriteData_o(memoryRequestWriteData),
        .memoryRequestAccess_o(memoryRequestAccess),
        .memoryResponseValid_i(memoryResponseValid),
        .memoryResponseReady_o(memoryResponseReady),
        .memoryResponseData_i(memoryResponseData),
        .perfRequestCount_o(perfRequestCount_o),
        .perfLoadHitCount_o(perfLoadHitCount_o),
        .perfLoadMissCount_o(perfLoadMissCount_o),
        .perfStoreHitCount_o(perfStoreHitCount_o),
        .perfStoreMissCount_o(perfStoreMissCount_o),
        .perfBusyCycles_o(perfBusyCycles_o),
        .perfRefillLineCount_o(perfRefillLineCount_o),
        .perfRefillCycles_o(perfRefillCycles_o),
        .perfMmioRequestCount_o(perfMmioRequestCount_o),
        .perfRequestBackpressureCycles_o(
            perfRequestBackpressureCycles_o)
    );

    // Keep this instance name and its mem array stable: simulation tooling
    // loads data images through dut.memStage.dataMem.mem.
    dataMem #(
        .DATA_W(DATA_W),
        .LOGIC_ADDR_W(LOGIC_ADDR_W),
        .MEM_BYTES(MEM_BYTES),
        .UART_TX_MMIO_ADDR(UART_TX_MMIO_ADDR),
        .FROMHOST_MMIO_ADDR(FROMHOST_MMIO_ADDR),
        .TOHOST_MMIO_ADDR(TOHOST_MMIO_ADDR),
        .MEM_FILE(MEM_FILE)
    ) dataMem (
        .clk(clk),
        .rst(rst),
        .requestValid_i(memoryRequestValid),
        .requestReady_o(memoryRequestReady),
        .requestWrite_i(memoryRequestWrite),
        .requestAddress_i(memoryRequestAddress),
        .requestWriteData_i(memoryRequestWriteData),
        .requestAccess_i(memoryRequestAccess),
        .responseValid_o(memoryResponseValid),
        .responseReady_i(memoryResponseReady),
        .responseData_o(memoryResponseData),
        .fromHost_i(fromHost_i),
        .toHost_o(toHost_o),
        .uartValid_o(uartValid_o),
        .uartData_o(uartData_o),
        .toHostHit_o(toHostHit_o),
        .uartHit_o(uartHit_o),
        .fromHostHit_o(fromHostHit_o)
    );

endmodule
