`include "Types.v"

module ALU(
    input `ctrALU ctr,

    input `data dataA,
    input `data dataB,

    output `data out,
    output logic zero //check if equal
);

    assign zero = (out==0);

    always @(*) begin
        case(ctr)
            `AND:out = dataA & dataB;
            `OR:out = dataA | dataB;
            `SUB:out = dataA - dataB;
            `ADD:out = dataA + dataB;
        endcase
    end

endmodule