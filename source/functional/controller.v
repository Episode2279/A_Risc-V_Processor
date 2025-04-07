`include "Types.v"

module controller(
    input `regAddr in1,
    input `regAddr in2,

    output logic wrEnable,
    output logic stall
);

    always@(*)begin
        wrEnable = `TRUE;
        stall = `FALSE;
    end

endmodule