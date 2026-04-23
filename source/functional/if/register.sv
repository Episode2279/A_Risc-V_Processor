module register
    import TypesPkg::*;
#(
    // Generic enabled register retained for small datapath helpers.
    parameter int WIDTH = WORD_SIZE,
    parameter logic [WIDTH-1:0] RESET_VALUE = '0
)
(
    // Active-low reset and write-enable match the rest of the pipeline.
    input  logic             clk,
    input  logic             rst,
    input  logic             wrEnable,
    input  logic [WIDTH-1:0] regIn,
    output logic [WIDTH-1:0] regOut
);

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            regOut <= RESET_VALUE;
        end else if (wrEnable) begin
            // Hold the previous value whenever wrEnable is low.
            regOut <= regIn;
        end
    end

endmodule
