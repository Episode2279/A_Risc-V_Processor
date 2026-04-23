module RegisterFile
    import TypesPkg::*;
#(
    // RV32I defaults: 32 registers, 32-bit data, 5-bit register addresses.
    parameter int DATA_W = WORD_SIZE,
    parameter int REG_COUNT = REG_NUM,
    parameter int REG_ADDR_W = REG_ADDR,
    // Register reset value is configurable for simulation experiments.
    parameter logic [DATA_W-1:0] RESET_VALUE = RESET_VECTOR,
    // Architectural x0 encoding. Writes to this register are discarded.
    parameter logic [REG_ADDR_W-1:0] ZERO_REG = '0
)
(
    // Two synchronous write ports and four combinational read ports for the
    // conservative two-issue pipeline. The original A/B read names are kept for
    // slot0, while C/D serve slot1.
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  writeEnable,
    input  logic [DATA_W-1:0]     data_i,
    input  logic [REG_ADDR_W-1:0] wrAddr,
    input  logic                  writeEnableB,
    input  logic [DATA_W-1:0]     dataB_i,
    input  logic [REG_ADDR_W-1:0] wrAddrB,
    input  logic [REG_ADDR_W-1:0] rdAddrA,
    input  logic [REG_ADDR_W-1:0] rdAddrB,
    input  logic [REG_ADDR_W-1:0] rdAddrC,
    input  logic [REG_ADDR_W-1:0] rdAddrD,
    output logic [DATA_W-1:0]     rdA,
    output logic [DATA_W-1:0]     rdB,
    output logic [DATA_W-1:0]     rdC,
    output logic [DATA_W-1:0]     rdD
);

    logic [DATA_W-1:0] regMem [0:REG_COUNT-1];

    function automatic logic [DATA_W-1:0] read_with_bypass(
        input logic [REG_ADDR_W-1:0] rdAddr
    );
        begin
            if (rdAddr == ZERO_REG) begin
                read_with_bypass = '0;
            end else if (writeEnableB && (wrAddrB != ZERO_REG) && (wrAddrB == rdAddr)) begin
                // Slot1 is younger than slot0, so it wins same-cycle WAW/read
                // bypass priority when both write the same destination.
                read_with_bypass = dataB_i;
            end else if (writeEnable && (wrAddr != ZERO_REG) && (wrAddr == rdAddr)) begin
                read_with_bypass = data_i;
            end else begin
                read_with_bypass = regMem[rdAddr];
            end
        end
    endfunction

    always_ff @(posedge clk or negedge rst) begin
        if (~rst) begin
            // Reset all physical registers. Reads of x0 are still forced to 0
            // below even if RESET_VALUE is changed for experiments.
            for (int idx = 0; idx < REG_COUNT; idx++) begin
                regMem[idx] <= RESET_VALUE;
            end
        end else if (writeEnable && (wrAddr != ZERO_REG)) begin
            // Keep x0 hardwired to zero by suppressing writes to ZERO_REG.
            regMem[wrAddr] <= data_i;
        end

        if (rst && writeEnableB && (wrAddrB != ZERO_REG)) begin
            regMem[wrAddrB] <= dataB_i;
        end
    end

    // Same-cycle write-first bypass lets decode see a value being written back
    // without waiting an extra cycle.
    assign rdA = read_with_bypass(rdAddrA);
    assign rdB = read_with_bypass(rdAddrB);
    assign rdC = read_with_bypass(rdAddrC);
    assign rdD = read_with_bypass(rdAddrD);

endmodule
