`include "Types.v"

module Decoder(
    input `instruction insn,

    output logic registerWriteEnable,
    output logic dataWriteEnable,
    output logic regSelect,
    output `ctrBranch branchCtr,
    output `ctrALU aluCtr,

    output `regAddr rs1,
    output `regAddr rs2,
    output `regAddr rd,
    output `instructionAddrPath offset
);

    always @(*) begin

        //addressing
        rs1 = insn[19:15];
        rs2 = insn[24:20];
        rsd = insn[11:7];
        offset = insn[11:7];

        //default controll signal
        regSelect = `FALSE;
        dataWriteEnable = `FALSE;
        registerWriteEnable = `FALSE;
        branchCtr = `NO_JUMP;
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
                regSelect = `TRUE;
            end
            17'b0000000_110_0110011:begin //or
                registerWriteEnable = `TRUE;
                aluCtr = `OR;
                regSelect = `TRUE;
            end
            17'b0000000_000_0110011:begin //add
                registerWriteEnable = `TRUE;
                aluCtr = `ADD;
                regSelect = `TRUE;
            end
            17'b0100000_000_0110011:begin //sub
                registerWriteEnable = `TRUE;
                aluCtr = `SUB;
                regSelect = `TRUE;
            end
            17'b0100000_000_110011:begin //BEQ
                aluCtr = `SUB;
                branchCtr = `BEQ;
            end
            17'b0100000_100_110011:begin //BLT
                aluCtr = `SUB;
                branchCtr = `BLT;
            end
        endcase
    end
endmodule