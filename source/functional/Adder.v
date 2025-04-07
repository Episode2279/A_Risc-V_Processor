`include "Types.v"

module Adder(
    input `data in1,
    input `data in2,

    output `data out
);

    assign out = in1 + in2;

endmodule