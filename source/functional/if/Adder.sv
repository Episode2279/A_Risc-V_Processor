module Adder
    import TypesPkg::*;
#(
    // Generic adder width. This simple helper is mostly used for PC-style
    // address arithmetic in small datapath experiments.
    parameter int WIDTH = WORD_SIZE
)
(
    // Combinational operands and sum.
    input  logic [WIDTH-1:0] in1,
    input  logic [WIDTH-1:0] in2,
    output logic [WIDTH-1:0] out
);

    // No carry/overflow flags are needed by the current RV32I datapath.
    assign out = in1 + in2;

endmodule
