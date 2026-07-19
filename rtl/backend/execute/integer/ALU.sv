module ALU
    import TypesPkg::*;
#(
    // ALU datapath width. RV32 uses 32 bits, but keeping this parameterized
    // makes the arithmetic block reusable in experiments.
    parameter int WIDTH = WORD_SIZE,
    // Shift amount width is derived from the datapath width. For RV32 this is
    // 5 bits, matching the ISA rule that shifts use rs2[4:0] or shamt[4:0].
    parameter int SHAMT_W = $clog2(WIDTH)
)
(
    // Operation selector produced by the decoder/control path.
    input  alu_ctr_t          ctr,
    // Source operands after execute-stage muxing and forwarding.
    input  logic [WIDTH-1:0]  dataA,
    input  logic [WIDTH-1:0]  dataB,
    // Combinational ALU result forwarded to branch, memory, and writeback paths.
    output logic [WIDTH-1:0]  out
);

    always_comb begin
        // unique case asks simulators to warn if the encoded control value is
        // ambiguous, which helps catch decoder mistakes during RTL simulation.
        unique case (ctr)
            ALU_ADD:  out = dataA + dataB;
            ALU_SUB:  out = dataA - dataB;
            ALU_AND:  out = dataA & dataB;
            ALU_OR:   out = dataA | dataB;
            ALU_XOR:  out = dataA ^ dataB;
            // RV32 shift operations only consume the low SHAMT_W bits of dataB.
            ALU_SLL:  out = dataA << dataB[SHAMT_W-1:0];
            ALU_SRL:  out = dataA >> dataB[SHAMT_W-1:0];
            ALU_SRA:  out = $signed(dataA) >>> dataB[SHAMT_W-1:0];
            // Set-less-than instructions return exactly 0 or 1 in XLEN bits.
            ALU_SLT:  out = ($signed(dataA) < $signed(dataB)) ? {{(WIDTH-1){1'b0}}, 1'b1} : '0;
            ALU_SLTU: out = (dataA < dataB) ? {{(WIDTH-1){1'b0}}, 1'b1} : '0;
            // PASS is useful for simple move/immediate-style datapath cases.
            ALU_PASS: out = dataB;
            default:  out = '0;
        endcase
    end

endmodule
