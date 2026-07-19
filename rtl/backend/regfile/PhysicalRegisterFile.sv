module PhysicalRegisterFile
    import TypesPkg::*;
#(
    parameter int DATA_W = WORD_SIZE,
    parameter int PHYS_REGS = PHYS_REG_NUM,
    parameter int READ_PORTS = 4,
    parameter int ALLOC_WIDTH = 2,
    parameter int WRITEBACK_WIDTH = 2
)
(
    input  logic clk,
    input  logic rst,

    input  phys_reg_addr_t readAddr_i [READ_PORTS],
    output logic [DATA_W-1:0] readData_o [READ_PORTS],
    output logic [READ_PORTS-1:0] readReady_o,

    input  logic [ALLOC_WIDTH-1:0] allocValid_i,
    input  phys_reg_addr_t allocPhys_i [ALLOC_WIDTH],

    input  logic [WRITEBACK_WIDTH-1:0] writebackValid_i,
    input  phys_reg_addr_t writebackPhys_i [WRITEBACK_WIDTH],
    input  logic [DATA_W-1:0] writebackData_i [WRITEBACK_WIDTH]
);

    logic [DATA_W-1:0] registers [PHYS_REGS];
    logic [PHYS_REGS-1:0] readyTable;
    integer combReadPort;
    integer combWritePort;
    integer seqPort;
    integer seqPhysIndex;

    always_comb begin
        for (combReadPort = 0; combReadPort < READ_PORTS; combReadPort = combReadPort + 1) begin
            readData_o[combReadPort] = registers[readAddr_i[combReadPort]];
            readReady_o[combReadPort] = readyTable[readAddr_i[combReadPort]];

            for (combWritePort = 0; combWritePort < WRITEBACK_WIDTH; combWritePort = combWritePort + 1) begin
                if (writebackValid_i[combWritePort] &&
                    (writebackPhys_i[combWritePort] == readAddr_i[combReadPort])) begin
                    readData_o[combReadPort] = writebackData_i[combWritePort];
                    readReady_o[combReadPort] = 1'b1;
                end
            end

            if (readAddr_i[combReadPort] == '0) begin
                readData_o[combReadPort] = '0;
                readReady_o[combReadPort] = 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            for (seqPhysIndex = 0; seqPhysIndex < PHYS_REGS; seqPhysIndex = seqPhysIndex + 1) begin
                registers[seqPhysIndex] <= '0;
                readyTable[seqPhysIndex] <= (seqPhysIndex < REG_NUM);
            end
        end else begin
            for (seqPort = 0; seqPort < ALLOC_WIDTH; seqPort = seqPort + 1) begin
                if (allocValid_i[seqPort] && (allocPhys_i[seqPort] != '0)) begin
                    readyTable[allocPhys_i[seqPort]] <= 1'b0;
                end
            end
            for (seqPort = 0; seqPort < WRITEBACK_WIDTH; seqPort = seqPort + 1) begin
                if (writebackValid_i[seqPort] && (writebackPhys_i[seqPort] != '0)) begin
                    registers[writebackPhys_i[seqPort]] <= writebackData_i[seqPort];
                    readyTable[writebackPhys_i[seqPort]] <= 1'b1;
                end
            end
            registers[0] <= '0;
            readyTable[0] <= 1'b1;
        end
    end

endmodule
