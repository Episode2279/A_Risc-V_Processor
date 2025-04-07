`include "Types.v"
module Mux (
    input `regAddr in1,
    input `regAddr in2,

    input logic sel,

    output `regAddr out
);

    assign out=(sel==0)?in1:in2;

endmodule