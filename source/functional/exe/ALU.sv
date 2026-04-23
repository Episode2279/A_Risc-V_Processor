module ALU
    import TypesPkg::*;
#(
    parameter int WIDTH = WORD_SIZE,
    parameter int SHAMT_W = $clog2(WIDTH)
)
(
    input  alu_ctr_t          ctr,
    input  logic [WIDTH-1:0]  dataA,
    input  logic [WIDTH-1:0]  dataB,
    output logic [WIDTH-1:0]  out
);

    always_comb begin
        unique case (ctr)
            ALU_ADD:  out = dataA + dataB;
            ALU_SUB:  out = dataA - dataB;
            ALU_AND:  out = dataA & dataB;
            ALU_OR:   out = dataA | dataB;
            ALU_XOR:  out = dataA ^ dataB;
            ALU_SLL:  out = dataA << dataB[SHAMT_W-1:0];
            ALU_SRL:  out = dataA >> dataB[SHAMT_W-1:0];
            ALU_SRA:  out = $signed(dataA) >>> dataB[SHAMT_W-1:0];
            ALU_SLT:  out = ($signed(dataA) < $signed(dataB)) ? {{(WIDTH-1){1'b0}}, 1'b1} : '0;
            ALU_SLTU: out = (dataA < dataB) ? {{(WIDTH-1){1'b0}}, 1'b1} : '0;
            ALU_PASS: out = dataB;
            default:  out = '0;
        endcase
    end

endmodule
