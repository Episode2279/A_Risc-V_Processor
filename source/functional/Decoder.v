`include "Types.v"

module Decoder(
    input `instruction insn,

    output logic registerWriteEnable,
    output logic branchCtr,
    output logic aluCtr
);
always_comb begin
    //default controll signal
    registerWriteEnable = FALSE;
    branchCtr = FALSE;
    aluCtr = FALSE;
    // decode structure {func7,func3,opcode}.
end
endmodule