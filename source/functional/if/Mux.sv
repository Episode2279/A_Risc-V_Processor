module Mux
    import TypesPkg::*;
#(
    // Generic two-input mux width. Defaults to REG_ADDR for legacy use, but
    // callers can override it for data or address paths.
    parameter int WIDTH = REG_ADDR
)
(
    // sel=0 chooses in1, sel=1 chooses in2.
    input  logic [WIDTH-1:0] in1,
    input  logic [WIDTH-1:0] in2,
    input  logic             sel,
    output logic [WIDTH-1:0] out
);

    // Pure combinational select with no registered state.
    assign out = sel ? in2 : in1;

endmodule
