module IdStages
    import TypesPkg::*;
#(
    // Decoder sizing follows instruction/register widths from the package.
    parameter int INSN_W = INS_SIZE,
    parameter int REG_ADDR_W = REG_ADDR,
    parameter int IMM_W = WORD_SIZE
)
(
    // ID consumes the IF/ID packet and produces control/register metadata for
    // the ID/EX bus. Register-file data is attached in topCPU.
    InstructionPacketIf.sink id_packet,
    IdExeBusIf.decode        id_bus
);

    // A zero instruction is treated as a bubble for visualization/retirement.
    assign id_bus.valid = (id_packet.insn != '0);
    // Carry the fetch PC alongside all decoded controls.
    assign id_bus.pc = id_packet.pc;
    assign id_bus.predictedTaken = id_packet.predictedTaken;
    assign id_bus.predictedTarget = id_packet.predictedTarget;
    assign id_bus.predictorIndex = id_packet.predictorIndex;
    assign id_bus.historySnapshot = id_packet.historySnapshot;
    assign id_bus.predictedBtbHit = id_packet.predictedBtbHit;
    assign id_bus.predictedRasUsed = id_packet.predictedRasUsed;

    // Decoder owns ISA bitfield interpretation. The stage wrapper simply maps
    // decoder outputs into the strongly typed pipeline interface.
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
        .immediate(id_bus.immediate),
        .decodeException(id_bus.decodeException),
        .decodeExceptionCause(id_bus.decodeExceptionCause),
        .exceptionValue(id_bus.exceptionValue),
        .serialize(id_bus.serialize),
        .mret(id_bus.mret)
    );

endmodule
