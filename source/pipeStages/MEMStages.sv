module MEMStages
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
    input  logic         clk,
    input  logic         rst,
    input  logic [DATA_W-1:0] fromHost_i,
    ExeMemBusIf.sink     mem_bus,
    output logic [DATA_W-1:0] rdData,
    output logic [DATA_W-1:0] toHost_o,
    output logic         uartValid_o,
    output logic [7:0]   uartData_o
);

    dataMem #(
        .DATA_W(DATA_W),
        .LOGIC_ADDR_W(LOGIC_ADDR_W),
        .MEM_BYTES(MEM_BYTES),
        .UART_TX_MMIO_ADDR(UART_TX_MMIO_ADDR),
        .FROMHOST_MMIO_ADDR(FROMHOST_MMIO_ADDR),
        .TOHOST_MMIO_ADDR(TOHOST_MMIO_ADDR),
        .MEM_FILE(MEM_FILE)
    ) dataMem(
        .clk(clk),
        .rst(rst),
        .logicAddr(mem_bus.aluOut),
        .accessCtr(mem_bus.memCtr),
        .writeEnable(mem_bus.dataWriteEnable),
        .data_i(mem_bus.dataB),
        .fromHost_i(fromHost_i),
        .data_o(rdData),
        .toHost_o(toHost_o),
        .uartValid_o(uartValid_o),
        .uartData_o(uartData_o)
    );

endmodule
