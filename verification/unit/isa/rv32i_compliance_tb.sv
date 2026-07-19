`timescale 1ns/1ps

module rv32i_compliance_tb;
    import TypesPkg::*;

    instruction_t insn;
    logic registerWriteEnable;
    logic dataWriteEnable;
    wb_select_t wbSelect;
    csr_op_t csrOp;
    csr_addr_t csrAddr;
    logic csrUseImm;
    word_t csrImm;
    branch_ctr_t branchCtr;
    alu_ctr_t aluCtr;
    mem_access_t memCtr;
    logic aluSrcASelect;
    logic aluSrcBSelect;
    logic useRs1;
    logic useRs2;
    reg_addr_t rs1;
    reg_addr_t rs2;
    reg_addr_t rd;
    word_t immediate;
    logic decodeException;
    logic [5:0] decodeExceptionCause;
    word_t exceptionValue;
    logic serialize;
    logic mret;

    Decoder dut (
        .insn(insn), .registerWriteEnable(registerWriteEnable),
        .dataWriteEnable(dataWriteEnable), .wbSelect(wbSelect),
        .csrOp(csrOp), .csrAddr(csrAddr), .csrUseImm(csrUseImm),
        .csrImm(csrImm), .branchCtr(branchCtr), .aluCtr(aluCtr),
        .memCtr(memCtr), .aluSrcASelect(aluSrcASelect),
        .aluSrcBSelect(aluSrcBSelect), .useRs1(useRs1), .useRs2(useRs2),
        .rs1(rs1), .rs2(rs2), .rd(rd), .immediate(immediate),
        .decodeException(decodeException),
        .decodeExceptionCause(decodeExceptionCause),
        .exceptionValue(exceptionValue), .serialize(serialize), .mret(mret)
    );

    task automatic expect_legal(input instruction_t value);
        insn = value;
        #1;
        if (decodeException)
            $fatal(1, "legal RV32I instruction rejected: insn=%h cause=%0d",
                   insn, decodeExceptionCause);
    endtask

    task automatic expect_illegal(input instruction_t value);
        insn = value;
        #1;
        if (!decodeException || decodeExceptionCause != EXC_ILLEGAL_INSN ||
            exceptionValue != value)
            $fatal(1, "illegal instruction was not reported precisely: insn=%h",
                   value);
    endtask

    initial begin
        // Representative legal encoding from every RV32I computational class.
        expect_legal(32'h0031_00b3); // add x1,x2,x3
        expect_legal(32'h4031_00b3); // sub x1,x2,x3
        expect_legal(32'h0011_1093); // slli x1,x2,1
        expect_legal(32'h4011_5093); // srai x1,x2,1
        expect_legal(32'h0041_2083); // lw x1,4(x2)
        expect_legal(32'h0011_2223); // sw x1,4(x2)
        expect_legal(32'h0031_0463); // beq x2,x3,+8
        expect_legal(32'h0080_00ef); // jal x1,+8
        expect_legal(32'h0001_00e7); // jalr x1,0(x2)
        expect_legal(32'h1234_50b7); // lui x1,0x12345
        expect_legal(32'h1234_5097); // auipc x1,0x12345

        expect_legal(32'h0000_000f); // fence
        if (!serialize) $fatal(1, "FENCE must serialize memory ordering");

        insn = 32'h0000_0073; #1; // ecall
        if (!decodeException || decodeExceptionCause != EXC_ECALL_MMODE ||
            !serialize) $fatal(1, "ECALL decode is incorrect");
        insn = 32'h0010_0073; #1; // ebreak
        if (!decodeException || decodeExceptionCause != EXC_BREAKPOINT ||
            !serialize) $fatal(1, "EBREAK decode is incorrect");
        insn = 32'h3020_0073; #1; // mret
        if (decodeException || !mret || branchCtr != BR_MRET || !serialize)
            $fatal(1, "MRET decode is incorrect");

        expect_illegal(32'h0231_00b3); // MUL encoding without M extension
        expect_legal(32'h0000_100f); // FENCE.I synchronization point
        expect_illegal(32'hffff_ffff); // unknown opcode

        $display("RV32I compliance smoke test: PASS");
        $finish;
    end
endmodule
