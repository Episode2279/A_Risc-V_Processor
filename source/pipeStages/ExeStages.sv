module ExeStages
    import TypesPkg::*;
#(
    parameter int DATA_W = WORD_SIZE
)
(
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

    assign aluInA = exe_bus.aluSrcASelect ? exe_bus.pc : dataA;
    assign aluInB = exe_bus.aluSrcBSelect ? exe_bus.immediate : dataB;

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
