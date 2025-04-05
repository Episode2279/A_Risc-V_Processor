`include "Types.v"

module Decoder(
    input `instruction insn,

    output logic registerWriteEnable,
    output logic dataWriteEnable,
    output logic branchCtr,
    output `ctrALU aluCtr
);
always_comb begin
    //default controll signal
    registerWriteEnable = `FALSE;
    branchCtr = `FALSE;
    aluCtr = `AND;

    // decode structure {func7,func3,opcode}.
    casex ({insn[31:25],insn[14:12],insn[6:0]})
        17'bxxxxxxx_010_0000011:begin //lw
            registerWriteEnable = `TRUE;
        end
        17'bxxxxxxx_010_0100011:begin //sw
            dataWriteEnable = `TRUE;
        end
        17'b0000000_111_0110011:begin //and
            registerWriteEnable = `TRUE;
        end
        17'b0000000_110_0110011:begin //or
            registerWriteEnable = `TRUE;
            aluCtr = `OR;
        end
        17'b0000000_000_0110011:begin //add
            registerWriteEnable = `TRUE;
            aluCtr = `ADD;
        end
        17'b0100000_000_0110011:begin //sub
            registerWriteEnable = `TRUE;
            aluCtr = `SUB;
        end
    endcase
end
endmodule