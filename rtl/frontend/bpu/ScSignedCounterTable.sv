// One logical signed-counter prediction table with two synchronous reads and
// one retirement update. Same-address forwarding defines read-during-write
// behavior independently of the inferred SRAM implementation.
module ScSignedCounterTable #(
    parameter int ENTRIES = 256,
    parameter int COUNTER_WIDTH = 6,
    parameter int INDEX_WIDTH = $clog2(ENTRIES)
) (
    input  logic clk,
    input  logic rst,
    input  logic [INDEX_WIDTH-1:0] queryIndex_i,
    input  logic [INDEX_WIDTH-1:0] queryIndex1_i,
    output logic signed [COUNTER_WIDTH-1:0] responseCounter_o,
    output logic signed [COUNTER_WIDTH-1:0] responseCounter1_o,
    input  logic updateValid_i,
    input  logic [INDEX_WIDTH-1:0] updateIndex_i,
    input  logic updateTaken_i
);

    localparam logic signed [COUNTER_WIDTH-1:0] COUNTER_MAX =
        {1'b0, {(COUNTER_WIDTH-1){1'b1}}};
    localparam logic signed [COUNTER_WIDTH-1:0] COUNTER_MIN =
        {1'b1, {(COUNTER_WIDTH-1){1'b0}}};

    logic signed [COUNTER_WIDTH-1:0] counterTable [ENTRIES];
    logic signed [COUNTER_WIDTH-1:0] updatedCounter;

    initial begin
        counterTable = '{default:'0};
    end

    always_comb begin
        if (updateTaken_i)
            updatedCounter =
                (counterTable[updateIndex_i] == COUNTER_MAX) ?
                counterTable[updateIndex_i] :
                counterTable[updateIndex_i] + COUNTER_WIDTH'(1);
        else
            updatedCounter =
                (counterTable[updateIndex_i] == COUNTER_MIN) ?
                counterTable[updateIndex_i] :
                counterTable[updateIndex_i] - COUNTER_WIDTH'(1);
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            responseCounter_o <= '0;
            responseCounter1_o <= '0;
        end else begin
            responseCounter_o <=
                (updateValid_i && updateIndex_i == queryIndex_i) ?
                updatedCounter : counterTable[queryIndex_i];
            responseCounter1_o <=
                (updateValid_i && updateIndex_i == queryIndex1_i) ?
                updatedCounter : counterTable[queryIndex1_i];
            if (updateValid_i)
                counterTable[updateIndex_i] <= updatedCounter;
        end
    end

endmodule
