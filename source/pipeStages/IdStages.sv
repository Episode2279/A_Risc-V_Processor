module IdStages
    import TypesPkg::*;
#(
    parameter int INSN_W = INS_SIZE,
    parameter int REG_ADDR_W = REG_ADDR,
    parameter int IMM_W = WORD_SIZE
)
(
    InstructionPacketIf.sink id_packet,
    IdExeBusIf.decode        id_bus
);

    assign id_bus.valid = (id_packet.insn != '0);
    assign id_bus.pc = id_packet.pc;

    Decoder #(
        .INSN_W(INSN_W),
        .REG_ADDR_W(REG_ADDR_W),
        .IMM_W(IMM_W)
    ) decoder(
        .insn(id_packet.insn),
        .registerWriteEnable(id_bus.registerWriteEnable),
        .dataWriteEnable(id_bus.dataWriteEnable),
        .wbSelect(id_bus.wbSelect),
        .csrOp(id_bus.csrOp),
        .csrAddr(id_bus.csrAddr),
        .csrUseImm(id_bus.csrUseImm),
        .csrImm(id_bus.csrImm),
        .branchCtr(id_bus.branchCtr),
        .aluCtr(id_bus.aluCtr),
        .memCtr(id_bus.memCtr),
        .aluSrcASelect(id_bus.aluSrcASelect),
        .aluSrcBSelect(id_bus.aluSrcBSelect),
        .useRs1(id_bus.useRs1),
        .useRs2(id_bus.useRs2),
        .rs1(id_bus.regA),
        .rs2(id_bus.regB),
        .rd(id_bus.rd),
        .immediate(id_bus.immediate)
    );

endmodule
