module ExeStages
    import TypesPkg::*;
#(
    // Execute datapath width. Defaults to RV32.
    parameter int DATA_W = WORD_SIZE
)
(
    // Decoded controls and forwarded operands enter EX.
    IdExeBusIf.sink exe_bus,
    input  logic [DATA_W-1:0] dataA,
    input  logic [DATA_W-1:0] dataB,
    output logic [DATA_W-1:0] aluOut,
    output logic              equal,
    output logic              lessThan,
    output logic              lessThanUnsigned
);

    logic [DATA_W-1:0] aluInA;
    logic [DATA_W-1:0] aluInB;

    // ALU source muxing supports register-register, register-immediate,
    // PC-relative branches/JAL/AUIPC, and address calculations.
    assign aluInA = exe_bus.aluSrcASelect ? exe_bus.pc : dataA;
    assign aluInB = exe_bus.aluSrcBSelect ? exe_bus.immediate : dataB;

    // Branch comparisons use forwarded register operands, not ALU mux inputs,
    // because branch conditions compare rs1 against rs2.
    assign equal = (dataA == dataB);
    assign lessThan = ($signed(dataA) < $signed(dataB));
    assign lessThanUnsigned = (dataA < dataB);

    ALU #(
        .WIDTH(DATA_W)
    ) alu(
        .ctr(exe_bus.aluCtr),
        .dataA(aluInA),
        .dataB(aluInB),
        .out(aluOut)
    );

endmodule
