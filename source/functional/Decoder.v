`include "Types.v"

module Decoder(
    input `instruction insn,

    output logic registerWriteEnable,
    output logic dataWriteEnable,
    output logic branchCtr,
    output logic aluCtr
);
always_comb begin
    //default controll signal
    registerWriteEnable = `FALSE;
    branchCtr = `FALSE;
    aluCtr = `FALSE;
    // decode structure {func7,func3,opcode}.
    casex ({insn[31:25],insn[14:12],insn[6:0]})
        17'bxxxxxxx_011_0000011:begin //ld
            registerWriteEnable = `TRUE;
        end
        17'bxxxxxxx_011_0100011:begin //sd
            dataWriteEnable = `TRUE;
        end
    endcase
end
endmodule