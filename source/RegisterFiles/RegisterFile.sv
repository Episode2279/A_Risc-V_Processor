module RegisterFile
    import TypesPkg::*;
#(
    parameter int DATA_W = WORD_SIZE,
    parameter int REG_COUNT = REG_NUM,
    parameter int REG_ADDR_W = REG_ADDR,
    parameter logic [DATA_W-1:0] RESET_VALUE = RESET_VECTOR,
    parameter logic [REG_ADDR_W-1:0] ZERO_REG = '0
)
(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  writeEnable,
    input  logic [DATA_W-1:0]     data_i,
    input  logic [REG_ADDR_W-1:0] wrAddr,
    input  logic [REG_ADDR_W-1:0] rdAddrA,
    input  logic [REG_ADDR_W-1:0] rdAddrB,
    output logic [DATA_W-1:0]     rdA,
    output logic [DATA_W-1:0]     rdB
);

    logic [DATA_W-1:0] regMem [0:REG_COUNT-1];

    always_ff @(posedge clk or negedge rst) begin
        if (~rst) begin
            for (int idx = 0; idx < REG_COUNT; idx++) begin
                regMem[idx] <= RESET_VALUE;
            end
        end else if (writeEnable && (wrAddr != ZERO_REG)) begin
            regMem[wrAddr] <= data_i;
        end
    end

    assign rdA = (rdAddrA == ZERO_REG) ? '0 :
                 ((writeEnable && (wrAddr != ZERO_REG) && (wrAddr == rdAddrA)) ? data_i : regMem[rdAddrA]);
    assign rdB = (rdAddrB == ZERO_REG) ? '0 :
                 ((writeEnable && (wrAddr != ZERO_REG) && (wrAddr == rdAddrB)) ? data_i : regMem[rdAddrB]);

endmodule
