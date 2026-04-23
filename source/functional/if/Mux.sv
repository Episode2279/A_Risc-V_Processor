module Mux
    import TypesPkg::*;
#(
    parameter int WIDTH = REG_ADDR
)
(
    input  logic [WIDTH-1:0] in1,
    input  logic [WIDTH-1:0] in2,
    input  logic             sel,
    output logic [WIDTH-1:0] out
);

    assign out = sel ? in2 : in1;

endmodule
