`include "Types.v"
module Mux #(parameter integer LENGTH)(
    input logic in1[LENGTH-1:0],
    input logic in2[LENGTH-1:0],

    input logic sel,

    output logic out[LENGTH-1:0]
);

    assign out=(sel==0)?in1:in2;

endmodule