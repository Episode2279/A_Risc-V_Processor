`include "Types.v"

module controller(
    input `regAddr in1,
    input `regAddr in2,

    output logic wrEnable,
    output logic stall
);

    assign wrEnable = `TRUE;
    assign stall = `FALSE;

endmodule