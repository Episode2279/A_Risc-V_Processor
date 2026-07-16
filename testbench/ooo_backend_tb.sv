`timescale 1ns/1ps

module ooo_backend_tb;
    import TypesPkg::*;

    logic clk = 1'b0;
    logic rst = 1'b0;
    logic flush;
    always #5 clk = ~clk;

    IdExeBusIf decode0();
    IdExeBusIf decode1();
    logic [1:0] dispatchAccept;
    logic dispatchStall;
    word_t memoryReadData;
    logic memoryValid;
    logic memoryWrite;
    word_t memoryAddress;
    word_t memoryWriteData;
    mem_access_t memoryAccess;
    word_t csrReadData;
    logic csrValid;
    csr_op_t csrOp;
    csr_addr_t csrAddr;
    word_t csrWriteData;
    logic branchResolved;
    instruction_addr_t branchPc;
    logic branchIsConditional;
    bpu_index_t branchPredictorIndex;
    logic branchTaken;
    instruction_addr_t branchTarget;
    logic branchMispredicted;
    instruction_addr_t branchRedirect;
    logic trapValid;
    instruction_addr_t trapPc;
    logic [5:0] trapCause;
    word_t trapValue;
    logic mretCommit;
    logic [1:0] commitValid;
    instruction_addr_t commitPc [2];
    reg_addr_t commitRd [2];
    word_t commitData [2];
    logic [1:0] retireCount;
    logic [$clog2(ROB_ENTRY_NUM+1)-1:0] robCount;
    logic [$clog2(ISSUE_QUEUE_ENTRY_NUM+LSQ_ENTRY_NUM+1)-1:0] issueCount;
    logic [$clog2(LSQ_ENTRY_NUM+1)-1:0] lsqCount;

    assign flush = 1'b0;

    OoOBackend dut (
        .clk(clk), .rst(rst), .flush_i(flush),
        .decode0_bus(decode0), .decode1_bus(decode1),
        .dispatchAccept_o(dispatchAccept), .dispatchStall_o(dispatchStall),
        .memoryReadData_i(memoryReadData), .memoryValid_o(memoryValid),
        .memoryWrite_o(memoryWrite), .memoryAddress_o(memoryAddress),
        .memoryWriteData_o(memoryWriteData), .memoryAccess_o(memoryAccess),
        .csrReadData_i(csrReadData), .csrValid_o(csrValid), .csrOp_o(csrOp),
        .csrAddr_o(csrAddr), .csrWriteData_o(csrWriteData),
        .branchResolved_o(branchResolved), .branchPc_o(branchPc),
        .branchIsConditional_o(branchIsConditional),
        .branchIsCall_o(), .branchIsReturn_o(),
        .branchPredictorIndex_o(branchPredictorIndex),
        .branchTaken_o(branchTaken), .branchTarget_o(branchTarget),
        .branchMispredicted_o(branchMispredicted),
        .branchRedirect_o(branchRedirect),
        .branchRobTag_o(), .branchCheckpointValid_o(),
        .branchCheckpointTag_o(), .branchCheckpointHistory_o(),
        .trapValid_o(trapValid), .trapPc_o(trapPc),
        .trapCause_o(trapCause), .trapValue_o(trapValue),
        .mretCommit_o(mretCommit), .commitValid_o(commitValid),
        .commitPc_o(commitPc), .commitArchRd_o(commitRd),
        .commitData_o(commitData), .retireCount_o(retireCount),
        .robCount_o(robCount), .issueCount_o(issueCount), .lsqCount_o(lsqCount),
        .perfDualIssueCycles_o(), .perfSingleIssueCycles_o(), .perfIqNoReadyCycles_o(),
        .perfPort0LsuBlockedCycles_o(), .perfPort0BranchBlockedCycles_o(),
        .perfRobFullCycles_o(), .perfIqFullCycles_o(), .perfLsqFullCycles_o(),
        .perfPrfEmptyCycles_o(), .perfBranchCount_o(), .perfBranchMispredictCount_o(),
        .perfJumpSerializationCycles_o()
        ,.perfConditionalCount_o(),.perfConditionalMispredictCount_o(),
        .perfDirectionMispredictCount_o(),.perfTargetMispredictCount_o(),.perfBtbMissCount_o(),
        .perfJalMispredictCount_o(),.perfJalrMispredictCount_o(),.perfRasMissCount_o()
    );

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    task automatic clear_lane0;
        begin
            decode0.valid = 1'b0;
            decode0.pc = '0;
            decode0.predictedTaken = 1'b0;
            decode0.predictedTarget = '0;
            decode0.predictorIndex = '0;
            decode0.registerWriteEnable = 1'b0;
            decode0.dataWriteEnable = 1'b0;
            decode0.wbSelect = WB_ALU;
            decode0.csrOp = CSR_NONE;
            decode0.csrAddr = '0;
            decode0.csrUseImm = 1'b0;
            decode0.csrImm = '0;
            decode0.branchCtr = BR_NONE;
            decode0.aluCtr = ALU_ADD;
            decode0.memCtr = MEM_WORD;
            decode0.aluSrcASelect = 1'b0;
            decode0.aluSrcBSelect = 1'b0;
            decode0.useRs1 = 1'b0;
            decode0.useRs2 = 1'b0;
            decode0.dataA = '0;
            decode0.dataB = '0;
            decode0.regA = '0;
            decode0.regB = '0;
            decode0.rd = '0;
            decode0.immediate = '0;
            decode0.decodeException = 1'b0;
            decode0.decodeExceptionCause = '0;
            decode0.exceptionValue = '0;
            decode0.serialize = 1'b0;
            decode0.mret = 1'b0;
        end
    endtask

    task automatic clear_lane1;
        begin
            decode1.valid = 1'b0;
            decode1.pc = '0;
            decode1.predictedTaken = 1'b0;
            decode1.predictedTarget = '0;
            decode1.predictorIndex = '0;
            decode1.registerWriteEnable = 1'b0;
            decode1.dataWriteEnable = 1'b0;
            decode1.wbSelect = WB_ALU;
            decode1.csrOp = CSR_NONE;
            decode1.csrAddr = '0;
            decode1.csrUseImm = 1'b0;
            decode1.csrImm = '0;
            decode1.branchCtr = BR_NONE;
            decode1.aluCtr = ALU_ADD;
            decode1.memCtr = MEM_WORD;
            decode1.aluSrcASelect = 1'b0;
            decode1.aluSrcBSelect = 1'b0;
            decode1.useRs1 = 1'b0;
            decode1.useRs2 = 1'b0;
            decode1.dataA = '0;
            decode1.dataB = '0;
            decode1.regA = '0;
            decode1.regB = '0;
            decode1.rd = '0;
            decode1.immediate = '0;
            decode1.decodeException = 1'b0;
            decode1.decodeExceptionCause = '0;
            decode1.exceptionValue = '0;
            decode1.serialize = 1'b0;
            decode1.mret = 1'b0;
        end
    endtask

    task automatic set_addi0(input word_t pc, input reg_addr_t rd,
                             input reg_addr_t rs1, input word_t imm);
        begin
            clear_lane0();
            decode0.valid = 1'b1;
            decode0.pc = pc;
            decode0.registerWriteEnable = 1'b1;
            decode0.wbSelect = WB_ALU;
            decode0.aluCtr = ALU_ADD;
            decode0.aluSrcBSelect = 1'b1;
            decode0.useRs1 = 1'b1;
            decode0.regA = rs1;
            decode0.rd = rd;
            decode0.immediate = imm;
        end
    endtask

    task automatic set_addi1(input word_t pc, input reg_addr_t rd,
                             input reg_addr_t rs1, input word_t imm);
        begin
            clear_lane1();
            decode1.valid = 1'b1;
            decode1.pc = pc;
            decode1.registerWriteEnable = 1'b1;
            decode1.wbSelect = WB_ALU;
            decode1.aluCtr = ALU_ADD;
            decode1.aluSrcBSelect = 1'b1;
            decode1.useRs1 = 1'b1;
            decode1.regA = rs1;
            decode1.rd = rd;
            decode1.immediate = imm;
        end
    endtask

    task automatic wait_commit(input reg_addr_t expectedRd, input word_t expectedData);
        integer cycles;
        logic matched;
        begin
            cycles = 0;
            matched = 1'b0;
            while (!matched && (cycles < 40)) begin
                tick();
                if (commitValid[0] && (commitRd[0] == expectedRd)) begin
                    if (commitData[0] != expectedData)
                        $fatal(1, "commit x%0d expected %h got %h", expectedRd,
                               expectedData, commitData[0]);
                    matched = 1'b1;
                end
                if (commitValid[1] && (commitRd[1] == expectedRd)) begin
                    if (commitData[1] != expectedData)
                        $fatal(1, "commit x%0d expected %h got %h", expectedRd,
                               expectedData, commitData[1]);
                    matched = 1'b1;
                end
                cycles = cycles + 1;
            end
            if (!matched) $fatal(1, "timed out waiting for commit x%0d", expectedRd);
        end
    endtask

    task automatic wait_lane0_accept;
        integer cycles;
        begin
            cycles = 0;
            #1;
            while (!dispatchAccept[0] && (cycles < 40)) begin
                tick();
                cycles = cycles + 1;
            end
            if (!dispatchAccept[0]) $fatal(1, "timed out waiting for dispatch");
            tick();
            clear_lane0();
        end
    endtask

    initial begin
        clear_lane0();
        clear_lane1();
        memoryReadData = 32'hDEAD_BEEF;
        csrReadData = 32'h0000_0055;
        tick();
        rst = 1'b1;
        #1;

        // Same-cycle lane dependency: lane 1 must wait for lane 0's new tag.
        set_addi0(32'h100, 1, 0, 5);
        set_addi1(32'h104, 2, 1, 3);
        #1;
        if (dispatchAccept != 2'b11) $fatal(1, "dual integer dispatch failed");
        tick();
        clear_lane0();
        clear_lane1();
        wait_commit(1, 5);
        wait_commit(2, 8);

        // After x1/x2 commit, their old low-numbered physical registers are
        // recycled. The younger RAW must not observe their stale ready/data.
        set_addi0(32'h108, 3, 0, 7);
        set_addi1(32'h10c, 4, 3, 1);
        #1;
        if (dispatchAccept != 2'b11) $fatal(1, "recycled-tag dispatch failed");
        tick();
        clear_lane0();
        clear_lane1();
        wait_commit(3, 7);
        wait_commit(4, 8);

        // Load uses the LSU while preserving the same PRF/ROB completion path.
        clear_lane0();
        decode0.valid = 1'b1;
        decode0.pc = 32'h110;
        decode0.registerWriteEnable = 1'b1;
        decode0.wbSelect = WB_MEM;
        decode0.aluCtr = ALU_ADD;
        decode0.aluSrcBSelect = 1'b1;
        decode0.useRs1 = 1'b1;
        decode0.regA = 0;
        decode0.rd = 5;
        decode0.immediate = 32'h20;
        wait_lane0_accept();
        while (!memoryValid) tick();
        if (memoryWrite || memoryAddress != 32'h20)
            $fatal(1, "load request is incorrect");
        wait_commit(5, 32'hDEAD_BEEF);

        // Store may not lose its PRF-sourced data before commit-time writing.
        clear_lane0();
        decode0.valid = 1'b1;
        decode0.pc = 32'h114;
        decode0.dataWriteEnable = 1'b1;
        decode0.aluCtr = ALU_ADD;
        decode0.aluSrcBSelect = 1'b1;
        decode0.useRs1 = 1'b1;
        decode0.useRs2 = 1'b1;
        decode0.regA = 0;
        decode0.regB = 5;
        decode0.immediate = 32'h24;
        wait_lane0_accept();
        while (!memoryValid) tick();
        if (!memoryWrite || memoryAddress != 32'h24 ||
            memoryWriteData != 32'hDEAD_BEEF)
            $fatal(1, "store request is incorrect");

        // A younger load may execute before an older Store retires and must
        // receive the Store value rather than the stale memory-port value.
        while (robCount != 0) tick();
        memoryReadData = 32'hA5A5_A5A5;
        clear_lane0();
        decode0.valid = 1'b1;
        decode0.pc = 32'h118;
        decode0.dataWriteEnable = 1'b1;
        decode0.aluCtr = ALU_ADD;
        decode0.aluSrcBSelect = 1'b1;
        decode0.useRs1 = 1'b1;
        decode0.useRs2 = 1'b1;
        decode0.regA = 0;
        decode0.regB = 5;
        // Store encodings carry immediate bits in the decoder's rd field. A
        // nonzero pseudo-rd must not update the committed rename map.
        decode0.rd = 5;
        decode0.immediate = 32'h30;
        clear_lane1();
        decode1.valid = 1'b1;
        decode1.pc = 32'h11c;
        decode1.registerWriteEnable = 1'b1;
        decode1.wbSelect = WB_MEM;
        decode1.aluCtr = ALU_ADD;
        decode1.aluSrcBSelect = 1'b1;
        decode1.useRs1 = 1'b1;
        decode1.regA = 0;
        decode1.rd = 7;
        decode1.immediate = 32'h30;
        #1;
        if (dispatchAccept != 2'b11)
            $fatal(1, "dual memory dispatch failed");
        tick();
        clear_lane0();
        clear_lane1();
        tick();
        if (memoryWrite)
            $fatal(1, "Store became visible at execute instead of retirement");
        while (!memoryWrite) tick();
        if (memoryAddress != 32'h30 || memoryWriteData != 32'hDEAD_BEEF)
            $fatal(1, "retiring Store request is incorrect");
        if (!commitValid[0] || commitPc[0] != 32'h118)
            $fatal(1, "Store write was not coupled to ROB retirement");
        wait_commit(7, 32'hDEAD_BEEF);
        set_addi0(32'h120, 8, 5, 1);
        wait_lane0_accept();
        wait_commit(8, 32'hDEAD_BEF0);
        memoryReadData = 32'hDEAD_BEEF;

        // A lane-0 branch and lane-1 integer operation dispatch together. The
        // unified IQ steers the branch to the branch-capable secondary port
        // and the integer operation to the primary port in the same cycle.
        while (robCount != 0) tick();
        clear_lane0();
        decode0.valid = 1'b1;
        decode0.pc = 32'h124;
        decode0.predictedTaken = 1'b1;
        decode0.predictedTarget = 32'h134;
        decode0.branchCtr = BR_BEQ;
        decode0.aluCtr = ALU_ADD;
        decode0.aluSrcASelect = 1'b1;
        decode0.aluSrcBSelect = 1'b1;
        decode0.useRs1 = 1'b1;
        decode0.useRs2 = 1'b1;
        decode0.immediate = 32'h10;
        set_addi1(32'h128, 9, 0, 7);
        #1;
        if (dispatchAccept != 2'b11)
            $fatal(1, "branch+integer dual dispatch failed");
        tick();
        clear_lane0();
        clear_lane1();
        #1;
        if (!branchTaken || branchPc != 32'h124 || !branchIsConditional ||
            branchTarget != 32'h134 || branchMispredicted ||
            branchRedirect != 32'h134)
            $fatal(1, "branch resolution is incorrect");
        if (!branchResolved || !dut.branchIssueLane ||
            !dut.issueValid[0] || !dut.issueValid[1] ||
            (dut.issueUop[0].pc != 32'h128) ||
            (dut.issueUop[1].pc != 32'h124))
            $fatal(1, "branch/int port steering failed: resolved=%0b lane=%0b issue=%b pc0=%h pc1=%h",
                   branchResolved, dut.branchIssueLane, dut.issueValid,
                   dut.issueUop[0].pc, dut.issueUop[1].pc);
        tick();
        wait_commit(9, 32'd7);

        // A direction miss squashes a co-issued younger integer operation,
        // suppresses its delayed PRF writeback, restores committed rename
        // state, and permits correct-path work.
        while (robCount != 0) tick();
        clear_lane0();
        decode0.valid = 1'b1;
        decode0.pc = 32'h130;
        decode0.predictedTaken = 1'b1;
        decode0.predictedTarget = 32'h180;
        decode0.branchCtr = BR_BNE;
        decode0.useRs1 = 1'b1;
        decode0.useRs2 = 1'b1;
        decode0.immediate = 32'h50;
        set_addi1(32'h180, 10, 0, 99);
        #1;
        if (dispatchAccept != 2'b11)
            $fatal(1, "mispredict branch+integer dispatch failed");
        tick();
        clear_lane0();
        clear_lane1();
        #1;
        if (!branchResolved || branchTaken || !branchMispredicted ||
            branchRedirect != 32'h134 || !dut.branchIssueLane)
            $fatal(1, "conditional misprediction recovery trigger failed");
        tick();
        #1;
        if (robCount != 1 || issueCount != 0 || lsqCount != 0)
            $fatal(1, "misprediction squash state rob=%0d issue=%0d lsq=%0d mask=%h",
                   robCount, issueCount, lsqCount,
                   dut.recoveryYoungerMask);
        while (robCount != 0) tick();
        set_addi0(32'h134, 11, 10, 1);
        wait_lane0_accept();
        wait_commit(11, 32'd1);

        // CSR returns the old CSR value and emits the serialized write request.
        while (robCount != 0) tick();
        clear_lane0();
        decode0.valid = 1'b1;
        decode0.pc = 32'h134;
        decode0.registerWriteEnable = 1'b1;
        decode0.wbSelect = WB_CSR;
        decode0.csrOp = CSR_RW;
        decode0.csrAddr = 12'h340;
        decode0.csrUseImm = 1'b1;
        decode0.csrImm = 32'hAA;
        decode0.rd = 6;
        wait_lane0_accept();
        while (!csrValid) tick();
        if (csrOp != CSR_RW || csrAddr != 12'h340 || csrWriteData != 32'hAA)
            $fatal(1, "CSR execution request is incorrect");
        wait_commit(6, 32'h55);

        // An excepting uop completes out of order like any other operation but
        // must stop at the ROB head and expose precise trap metadata without
        // retiring architectural state.
        while (robCount != 0) tick();
        clear_lane0();
        decode0.valid = 1'b1;
        decode0.pc = 32'h200;
        decode0.decodeException = 1'b1;
        decode0.decodeExceptionCause = EXC_ILLEGAL_INSN;
        decode0.exceptionValue = 32'hffff_ffff;
        decode0.serialize = 1'b1;
        wait_lane0_accept();
        clear_lane0();
        while (!trapValid) tick();
        if (trapPc != 32'h200 || trapCause != EXC_ILLEGAL_INSN ||
            trapValue != 32'hffff_ffff || |commitValid)
            $fatal(1, "precise trap metadata/retirement is incorrect");

        $display("OoO backend smoke test: PASS");
        $finish;
    end

endmodule
