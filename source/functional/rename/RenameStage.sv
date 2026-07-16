module RenameStage
    import TypesPkg::*;
#(
    parameter int RENAME_WIDTH = 2,
    parameter int COMMIT_WIDTH = 2
)
(
    input  logic clk,
    input  logic rst,
    input  logic restoreCommitted_i,
    input  logic recoverValid_i,
    input  rob_tag_t recoverTag_i,

    IdExeBusIf.sink decode0_bus,
    IdExeBusIf.sink decode1_bus,

    // The dispatch controller asserts a lane only after ROB/IQ/LSQ and PRF
    // destination resources have been reserved atomically.
    input  logic [RENAME_WIDTH-1:0] renameEnable_i,
    input  rob_tag_t robTag_i [RENAME_WIDTH],
    input  lsq_tag_t lsqTag_i [RENAME_WIDTH],

    // PRF busy-table lookup corresponding to sourcePhys_o.
    output phys_reg_addr_t sourcePhys_o [RENAME_WIDTH*2],
    input  logic [RENAME_WIDTH*2-1:0] sourceReady_i,

    output logic [RENAME_WIDTH-1:0] destinationAvailable_o,
    output logic [RENAME_WIDTH-1:0] destinationAllocValid_o,
    output phys_reg_addr_t destinationPhys_o [RENAME_WIDTH],
    output renamed_uop_t renamedUop_o [RENAME_WIDTH],
    output rob_entry_t robEntry_o [RENAME_WIDTH],
    output lsq_entry_t lsqEntry_o [RENAME_WIDTH],

    input  logic [COMMIT_WIDTH-1:0] commitValid_i,
    input  reg_addr_t commitArchRd_i [COMMIT_WIDTH],
    input  phys_reg_addr_t commitNewPhys_i [COMMIT_WIDTH],
    input  phys_reg_addr_t commitOldPhys_i [COMMIT_WIDTH],
    output logic [$clog2(PHYS_REG_NUM+1)-1:0] freePhysCount_o
);

    reg_addr_t sourceArchA [RENAME_WIDTH];
    reg_addr_t sourceArchB [RENAME_WIDTH];
    reg_addr_t destinationArch [RENAME_WIDTH];
    phys_reg_addr_t sourcePhysA [RENAME_WIDTH];
    phys_reg_addr_t sourcePhysB [RENAME_WIDTH];
    phys_reg_addr_t oldDestinationPhys [RENAME_WIDTH];
    logic [RENAME_WIDTH-1:0] writesDestination;
    logic [RENAME_WIDTH-1:0] freeRequest;
    logic [RENAME_WIDTH-1:0] freeReady;
    phys_reg_addr_t freePhys [RENAME_WIDTH];
    logic [COMMIT_WIDTH-1:0] freeCommitValid;
    logic [PHYS_REG_NUM-1:0] committedFreeMask;
    logic [RENAME_WIDTH-1:0] checkpointValid;
    rob_tag_t checkpointTag [RENAME_WIDTH];
    integer prepLane;
    integer packLane;
    integer checkpointLane;

    always_comb begin
        sourceArchA[0] = decode0_bus.regA;
        sourceArchB[0] = decode0_bus.regB;
        destinationArch[0] = decode0_bus.rd;
        sourceArchA[1] = decode1_bus.regA;
        sourceArchB[1] = decode1_bus.regB;
        destinationArch[1] = decode1_bus.rd;

        writesDestination[0] = decode0_bus.valid && decode0_bus.registerWriteEnable &&
                               (decode0_bus.rd != '0);
        writesDestination[1] = decode1_bus.valid && decode1_bus.registerWriteEnable &&
                               (decode1_bus.rd != '0);
        freeRequest = renameEnable_i & writesDestination;
        freeCommitValid[0] = commitValid_i[0] && (commitArchRd_i[0] != '0) &&
                             (commitOldPhys_i[0] != '0);
        freeCommitValid[1] = commitValid_i[1] && (commitArchRd_i[1] != '0) &&
                             (commitOldPhys_i[1] != '0);
        for (checkpointLane = 0; checkpointLane < RENAME_WIDTH;
             checkpointLane = checkpointLane + 1) begin
            checkpointValid[checkpointLane] = renameEnable_i[checkpointLane] &&
                ((checkpointLane == 0 ? decode0_bus.branchCtr :
                                        decode1_bus.branchCtr) != BR_NONE);
            checkpointTag[checkpointLane] = robTag_i[checkpointLane];
        end
    end

    always_comb begin
        destinationAllocValid_o = freeRequest & freeReady;
        for (prepLane = 0; prepLane < RENAME_WIDTH; prepLane = prepLane + 1) begin
            sourcePhys_o[prepLane*2] = sourcePhysA[prepLane];
            sourcePhys_o[prepLane*2+1] = sourcePhysB[prepLane];
            destinationAvailable_o[prepLane] = !writesDestination[prepLane] || freeReady[prepLane];
            destinationPhys_o[prepLane] = writesDestination[prepLane] ? freePhys[prepLane] : '0;
        end
    end

    always_comb begin
        for (packLane = 0; packLane < RENAME_WIDTH; packLane = packLane + 1) begin
            renamedUop_o[packLane] = '0;
            robEntry_o[packLane] = '0;
            lsqEntry_o[packLane] = '0;
        end

        renamedUop_o[0].valid = decode0_bus.valid && renameEnable_i[0] &&
                                 destinationAvailable_o[0];
        renamedUop_o[0].pc = decode0_bus.pc;
        renamedUop_o[0].predictedTaken = decode0_bus.predictedTaken;
        renamedUop_o[0].predictedTarget = decode0_bus.predictedTarget;
        renamedUop_o[0].predictorIndex = decode0_bus.predictorIndex;
        renamedUop_o[0].historySnapshot = decode0_bus.historySnapshot;
        renamedUop_o[0].predictedBtbHit = decode0_bus.predictedBtbHit;
        renamedUop_o[0].predictedRasUsed = decode0_bus.predictedRasUsed;
        renamedUop_o[0].isCall = ((decode0_bus.branchCtr == BR_JAL) || (decode0_bus.branchCtr == BR_JALR)) &&
                                 ((decode0_bus.rd == 5'd1) || (decode0_bus.rd == 5'd5));
        renamedUop_o[0].isReturn = (decode0_bus.branchCtr == BR_JALR) && (decode0_bus.rd == 0) &&
                                   ((decode0_bus.regA == 5'd1) || (decode0_bus.regA == 5'd5));
        renamedUop_o[0].registerWriteEnable = decode0_bus.registerWriteEnable;
        renamedUop_o[0].dataWriteEnable = decode0_bus.dataWriteEnable;
        renamedUop_o[0].wbSelect = decode0_bus.wbSelect;
        renamedUop_o[0].csrOp = decode0_bus.csrOp;
        renamedUop_o[0].csrAddr = decode0_bus.csrAddr;
        renamedUop_o[0].csrUseImm = decode0_bus.csrUseImm;
        renamedUop_o[0].csrImm = decode0_bus.csrImm;
        renamedUop_o[0].branchCtr = decode0_bus.branchCtr;
        renamedUop_o[0].aluCtr = decode0_bus.aluCtr;
        renamedUop_o[0].memCtr = decode0_bus.memCtr;
        renamedUop_o[0].aluSrcASelect = decode0_bus.aluSrcASelect;
        renamedUop_o[0].aluSrcBSelect = decode0_bus.aluSrcBSelect;
        renamedUop_o[0].useRs1 = decode0_bus.useRs1;
        renamedUop_o[0].useRs2 = decode0_bus.useRs2;
        renamedUop_o[0].src1Phys = sourcePhysA[0];
        renamedUop_o[0].src2Phys = sourcePhysB[0];
        renamedUop_o[0].src1Ready = sourceReady_i[0];
        renamedUop_o[0].src2Ready = sourceReady_i[1];
        renamedUop_o[0].destPhys = destinationPhys_o[0];
        renamedUop_o[0].robTag = robTag_i[0];
        renamedUop_o[0].lsqTag = lsqTag_i[0];
        renamedUop_o[0].immediate = decode0_bus.immediate;
        renamedUop_o[0].decodeException = decode0_bus.decodeException;
        renamedUop_o[0].decodeExceptionCause = decode0_bus.decodeExceptionCause;
        renamedUop_o[0].exceptionValue = decode0_bus.exceptionValue;
        renamedUop_o[0].serialize = decode0_bus.serialize;
        renamedUop_o[0].mret = decode0_bus.mret;

        renamedUop_o[1].valid = decode1_bus.valid && renameEnable_i[1] &&
                                 destinationAvailable_o[1];
        renamedUop_o[1].pc = decode1_bus.pc;
        renamedUop_o[1].predictedTaken = decode1_bus.predictedTaken;
        renamedUop_o[1].predictedTarget = decode1_bus.predictedTarget;
        renamedUop_o[1].predictorIndex = decode1_bus.predictorIndex;
        renamedUop_o[1].historySnapshot = decode1_bus.historySnapshot;
        renamedUop_o[1].predictedBtbHit = decode1_bus.predictedBtbHit;
        renamedUop_o[1].predictedRasUsed = decode1_bus.predictedRasUsed;
        renamedUop_o[1].isCall = ((decode1_bus.branchCtr == BR_JAL) || (decode1_bus.branchCtr == BR_JALR)) &&
                                 ((decode1_bus.rd == 5'd1) || (decode1_bus.rd == 5'd5));
        renamedUop_o[1].isReturn = (decode1_bus.branchCtr == BR_JALR) && (decode1_bus.rd == 0) &&
                                   ((decode1_bus.regA == 5'd1) || (decode1_bus.regA == 5'd5));
        renamedUop_o[1].registerWriteEnable = decode1_bus.registerWriteEnable;
        renamedUop_o[1].dataWriteEnable = decode1_bus.dataWriteEnable;
        renamedUop_o[1].wbSelect = decode1_bus.wbSelect;
        renamedUop_o[1].csrOp = decode1_bus.csrOp;
        renamedUop_o[1].csrAddr = decode1_bus.csrAddr;
        renamedUop_o[1].csrUseImm = decode1_bus.csrUseImm;
        renamedUop_o[1].csrImm = decode1_bus.csrImm;
        renamedUop_o[1].branchCtr = decode1_bus.branchCtr;
        renamedUop_o[1].aluCtr = decode1_bus.aluCtr;
        renamedUop_o[1].memCtr = decode1_bus.memCtr;
        renamedUop_o[1].aluSrcASelect = decode1_bus.aluSrcASelect;
        renamedUop_o[1].aluSrcBSelect = decode1_bus.aluSrcBSelect;
        renamedUop_o[1].useRs1 = decode1_bus.useRs1;
        renamedUop_o[1].useRs2 = decode1_bus.useRs2;
        renamedUop_o[1].src1Phys = sourcePhysA[1];
        renamedUop_o[1].src2Phys = sourcePhysB[1];
        // A younger lane consuming the older lane's newly allocated physical
        // destination must wait for the new value. The PRF may still report
        // the recycled register as ready until allocation is clocked.
        renamedUop_o[1].src1Ready = sourceReady_i[2] &&
            !(destinationAllocValid_o[0] &&
              (sourcePhysA[1] == destinationPhys_o[0]));
        renamedUop_o[1].src2Ready = sourceReady_i[3] &&
            !(destinationAllocValid_o[0] &&
              (sourcePhysB[1] == destinationPhys_o[0]));
        renamedUop_o[1].destPhys = destinationPhys_o[1];
        renamedUop_o[1].robTag = robTag_i[1];
        renamedUop_o[1].lsqTag = lsqTag_i[1];
        renamedUop_o[1].immediate = decode1_bus.immediate;
        renamedUop_o[1].decodeException = decode1_bus.decodeException;
        renamedUop_o[1].decodeExceptionCause = decode1_bus.decodeExceptionCause;
        renamedUop_o[1].exceptionValue = decode1_bus.exceptionValue;
        renamedUop_o[1].serialize = decode1_bus.serialize;
        renamedUop_o[1].mret = decode1_bus.mret;

        for (packLane = 0; packLane < RENAME_WIDTH; packLane = packLane + 1) begin
            if ((renamedUop_o[packLane].wbSelect == WB_CSR)) begin
                renamedUop_o[packLane].fuClass = FU_CSR;
            end else if (renamedUop_o[packLane].dataWriteEnable ||
                         (renamedUop_o[packLane].wbSelect == WB_MEM)) begin
                renamedUop_o[packLane].fuClass = FU_MEMORY;
            end else if (renamedUop_o[packLane].branchCtr != BR_NONE) begin
                renamedUop_o[packLane].fuClass = FU_BRANCH;
            end else begin
                renamedUop_o[packLane].fuClass = FU_INTEGER;
            end

            robEntry_o[packLane].valid = renamedUop_o[packLane].valid;
            robEntry_o[packLane].pc = renamedUop_o[packLane].pc;
            robEntry_o[packLane].writesRd = writesDestination[packLane];
            // S/B encodings reuse instruction bits [11:7] for immediates. They
            // must never reach the committed map as a false destination.
            robEntry_o[packLane].archRd = writesDestination[packLane] ?
                                           destinationArch[packLane] : '0;
            robEntry_o[packLane].newPhys = destinationPhys_o[packLane];
            robEntry_o[packLane].oldPhys = writesDestination[packLane] ?
                                            oldDestinationPhys[packLane] : '0;
            robEntry_o[packLane].isMemory =
                (renamedUop_o[packLane].fuClass == FU_MEMORY);
            robEntry_o[packLane].lsqTag = lsqTag_i[packLane];
            robEntry_o[packLane].isStore = renamedUop_o[packLane].dataWriteEnable;
            robEntry_o[packLane].isBranch = (renamedUop_o[packLane].branchCtr != BR_NONE);
            robEntry_o[packLane].isCsr = (renamedUop_o[packLane].wbSelect == WB_CSR);
            robEntry_o[packLane].exceptionValue = renamedUop_o[packLane].exceptionValue;
            robEntry_o[packLane].mret = renamedUop_o[packLane].mret;

            lsqEntry_o[packLane].valid = renamedUop_o[packLane].valid &&
                                         (renamedUop_o[packLane].fuClass == FU_MEMORY);
            lsqEntry_o[packLane].isLoad = (renamedUop_o[packLane].wbSelect == WB_MEM);
            lsqEntry_o[packLane].isStore = renamedUop_o[packLane].dataWriteEnable;
            lsqEntry_o[packLane].robTag = robTag_i[packLane];
            lsqEntry_o[packLane].destPhys = destinationPhys_o[packLane];
            lsqEntry_o[packLane].memCtr = renamedUop_o[packLane].memCtr;
            lsqEntry_o[packLane].pc = renamedUop_o[packLane].pc;
        end
    end

    RenameMapTable #(
        .RENAME_WIDTH(RENAME_WIDTH),
        .COMMIT_WIDTH(COMMIT_WIDTH)
    ) mapTable (
        .clk(clk),
        .rst(rst),
        .restoreCommitted_i(restoreCommitted_i),
        .checkpointValid_i(checkpointValid),
        .checkpointTag_i(checkpointTag),
        .recoverValid_i(recoverValid_i),
        .recoverTag_i(recoverTag_i),
        .sourceA_i(sourceArchA),
        .sourceB_i(sourceArchB),
        .sourceAPhys_o(sourcePhysA),
        .sourceBPhys_o(sourcePhysB),
        .renameValid_i(destinationAllocValid_o),
        .renameArchRd_i(destinationArch),
        .renameNewPhys_i(destinationPhys_o),
        .renameOldPhys_o(oldDestinationPhys),
        .commitValid_i(commitValid_i),
        .commitArchRd_i(commitArchRd_i),
        .commitNewPhys_i(commitNewPhys_i),
        .committedFreeMask_o(committedFreeMask)
    );

    PhysicalFreeList #(
        .ALLOC_WIDTH(RENAME_WIDTH),
        .FREE_WIDTH(COMMIT_WIDTH)
    ) freeList (
        .clk(clk),
        .rst(rst),
        .restore_i(restoreCommitted_i),
        .restoreFreeMask_i(committedFreeMask),
        .checkpointValid_i(checkpointValid),
        .checkpointTag_i(checkpointTag),
        .recoverValid_i(recoverValid_i),
        .recoverTag_i(recoverTag_i),
        .allocRequest_i(freeRequest),
        .allocReady_o(freeReady),
        .allocPhys_o(freePhys),
        .freeValid_i(freeCommitValid),
        .freePhys_i(commitOldPhys_i),
        .freeCount_o(freePhysCount_o)
    );

endmodule
