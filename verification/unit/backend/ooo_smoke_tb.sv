`timescale 1ns/1ps

module ooo_smoke_tb;
    import TypesPkg::*;

    logic clk = 1'b0;
    logic rst = 1'b0;
    always #5 clk = ~clk;

    reg_addr_t ratSourceA [2];
    reg_addr_t ratSourceB [2];
    phys_reg_addr_t ratSourceAPhys [2];
    phys_reg_addr_t ratSourceBPhys [2];
    logic [1:0] renameValid;
    reg_addr_t renameArchRd [2];
    phys_reg_addr_t renameNewPhys [2];
    phys_reg_addr_t renameOldPhys [2];
    logic [1:0] commitMapValid;
    reg_addr_t commitMapArch [2];
    phys_reg_addr_t commitMapPhys [2];
    logic [PHYS_REG_NUM-1:0] committedFreeMask;

    logic [1:0] freeAllocRequest;
    logic [1:0] freeAllocReady;
    phys_reg_addr_t freeAllocPhys [2];
    logic [1:0] freeValid;
    phys_reg_addr_t freePhys [2];
    logic [$clog2(PHYS_REG_NUM+1)-1:0] freeCount;

    phys_reg_addr_t prfReadAddr [4];
    word_t prfReadData [4];
    logic [3:0] prfReadReady;
    logic [1:0] prfAllocValid;
    phys_reg_addr_t prfAllocPhys [2];
    logic [1:0] prfWriteValid;
    phys_reg_addr_t prfWritePhys [2];
    word_t prfWriteData [2];

    logic [1:0] robAllocValid;
    rob_entry_t robAllocEntry [2];
    logic [1:0] robAllocReady;
    rob_tag_t robAllocTag [2];
    logic [1:0] robCompleteValid;
    rob_tag_t robCompleteTag [2];
    logic [1:0] robCompleteException;
    logic [5:0] robCompleteCause [2];
    word_t robCompleteValue [2];
    logic [1:0] robCommitValid;
    rob_entry_t robCommitEntry [2];
    logic [1:0] robCommitReady;
    logic robEmpty;
    logic robFull;
    logic [$clog2(ROB_ENTRY_NUM+1)-1:0] robCount;
    rob_tag_t savedRobTag0;
    rob_tag_t savedRobTag1;

    renamed_uop_t iqDispatch [2];
    logic [1:0] iqDispatchReady;
    logic [1:0] iqWakeValid;
    phys_reg_addr_t iqWakePhys [2];
    logic iqRecoverValid;
    rob_tag_t iqRecoverTag;
    logic [ROB_ENTRY_NUM-1:0] iqRecoverYoungerMask;
    logic [1:0] iqIssueValid;
    renamed_uop_t iqIssueUop [2];
    logic [1:0] iqIssueReady;
    logic iqFallbackValid;
    renamed_uop_t iqFallbackUop;
    logic iqFallbackReady;
    logic iqEmpty;
    logic iqFull;
    logic [$clog2(UNIFIED_IQ_ENTRY_NUM+1)-1:0] iqCount;

    logic [1:0] lsqAllocValid;
    lsq_entry_t lsqAllocEntry [2];
    logic [1:0] lsqAllocReady;
    lsq_tag_t lsqAllocTag [2];
    logic [1:0] lsqAddressValid;
    lsq_tag_t lsqAddressTag [2];
    word_t lsqAddress [2];
    logic [1:0] lsqStoreDataValid;
    lsq_tag_t lsqStoreDataTag [2];
    word_t lsqStoreData [2];
    lsq_entry_t lsqHead [2];
    lsq_tag_t lsqHeadTag [2];
    logic [1:0] lsqRetireCount;
    logic lsqIssueValid;
    lsq_tag_t lsqIssueTag;
    word_t lsqIssueAddress;
    mem_access_t lsqIssueMemCtr;
    logic lsqIssueReady;
    logic lsqForwardValid;
    word_t lsqForwardData;
    logic lsqEmpty;
    logic lsqFull;
    logic [$clog2(LSQ_ENTRY_NUM+1)-1:0] lsqCount;
    lsq_tag_t savedLsqTag;
    lsq_tag_t savedLsqLoadTag;

    RenameMapTable rat (
        .clk(clk), .rst(rst), .restoreCommitted_i(1'b0),
        .checkpointValid_i('0), .checkpointTag_i('{default:'0}),
        .recoverValid_i(1'b0), .recoverTag_i('0),
        .sourceA_i(ratSourceA), .sourceB_i(ratSourceB),
        .sourceAPhys_o(ratSourceAPhys), .sourceBPhys_o(ratSourceBPhys),
        .renameValid_i(renameValid), .renameArchRd_i(renameArchRd),
        .renameNewPhys_i(renameNewPhys), .renameOldPhys_o(renameOldPhys),
        .commitValid_i(commitMapValid), .commitArchRd_i(commitMapArch),
        .commitNewPhys_i(commitMapPhys),
        .committedFreeMask_o(committedFreeMask)
    );

    PhysicalFreeList freeList (
        .clk(clk), .rst(rst), .restore_i(1'b0), .restoreFreeMask_i('0),
        .checkpointValid_i('0), .checkpointTag_i('{default:'0}),
        .recoverValid_i(1'b0), .recoverTag_i('0),
        .allocRequest_i(freeAllocRequest), .allocReady_o(freeAllocReady),
        .allocPhys_o(freeAllocPhys), .freeValid_i(freeValid),
        .freePhys_i(freePhys), .freeCount_o(freeCount)
    );

    PhysicalRegisterFile prf (
        .clk(clk), .rst(rst), .readAddr_i(prfReadAddr),
        .readData_o(prfReadData), .readReady_o(prfReadReady),
        .allocValid_i(prfAllocValid), .allocPhys_i(prfAllocPhys),
        .writebackValid_i(prfWriteValid), .writebackPhys_i(prfWritePhys),
        .writebackData_i(prfWriteData)
    );

    ReorderBuffer rob (
        .clk(clk), .rst(rst), .flush_i(1'b0),
        .recoverValid_i(1'b0), .recoverTag_i('0), .recoverYoungerMask_o(),
        .queryBranchValid_i(1'b0), .queryBranchTag_i('0),
        .queryHasOlderUnresolvedBranch_o(),
        .allocValid_i(robAllocValid), .allocEntry_i(robAllocEntry),
        .allocReady_o(robAllocReady), .allocTag_o(robAllocTag),
        .completeValid_i(robCompleteValid), .completeTag_i(robCompleteTag),
        .completeException_i(robCompleteException), .completeCause_i(robCompleteCause),
        .completeValue_i(robCompleteValue),
        .branchResolveValid_i(1'b0), .branchResolveTag_i('0),
        .branchTaken_i(1'b0), .branchTarget_i('0),
        .branchMispredicted_i(1'b0),
        .commitValid_o(robCommitValid), .commitTag_o(),
        .commitEntry_o(robCommitEntry),
        .commitReady_i(robCommitReady), .empty_o(robEmpty), .full_o(robFull),
        .count_o(robCount)
    );

    IssueQueue issueQueue (
        .clk(clk), .rst(rst), .flush_i(1'b0),
        .recoverValid_i(iqRecoverValid), .recoverTag_i(iqRecoverTag),
        .recoverYoungerMask_i(iqRecoverYoungerMask),
        .dispatchUop_i(iqDispatch), .dispatchReady_o(iqDispatchReady),
        .wakeupValid_i(iqWakeValid), .wakeupPhys_i(iqWakePhys),
        .issueValid_o(iqIssueValid), .issueUop_o(iqIssueUop),
        .issueReady_i(iqIssueReady),
        .fallbackValid_o(iqFallbackValid),
        .fallbackUop_o(iqFallbackUop),
        .fallbackReady_i(iqFallbackReady),
        .empty_o(iqEmpty), .full_o(iqFull),
        .count_o(iqCount)
    );

    LoadStoreQueue lsq (
        .clk(clk), .rst(rst), .flush_i(1'b0),
        .recoverValid_i(1'b0), .recoverYoungerMask_i('0),
        .allocValid_i(lsqAllocValid), .allocEntry_i(lsqAllocEntry),
        .allocReady_o(lsqAllocReady), .allocTag_o(lsqAllocTag),
        .addressValid_i(lsqAddressValid), .addressTag_i(lsqAddressTag),
        .address_i(lsqAddress), .storeDataValid_i(lsqStoreDataValid),
        .storeDataTag_i(lsqStoreDataTag), .storeData_i(lsqStoreData),
        .dataWakeupValid_i(prfWriteValid),
        .dataWakeupPhys_i(prfWritePhys),
        .dataWakeupValue_i(prfWriteData),
        .issueValid_i(lsqIssueValid), .issueTag_i(lsqIssueTag),
        .issueAddress_i(lsqIssueAddress), .issueMemCtr_i(lsqIssueMemCtr),
        .issueReady_o(lsqIssueReady),
        .issueForwardValid_o(lsqForwardValid),
        .issueForwardData_o(lsqForwardData),
        .headEntry_o(lsqHead), .headTag_o(lsqHeadTag),
        .retireCount_i(lsqRetireCount),
        .empty_o(lsqEmpty), .full_o(lsqFull), .count_o(lsqCount)
    );

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    initial begin
        ratSourceA = '{default:'0};
        ratSourceB = '{default:'0};
        renameValid = '0;
        renameArchRd = '{default:'0};
        renameNewPhys = '{default:'0};
        commitMapValid = '0;
        commitMapArch = '{default:'0};
        commitMapPhys = '{default:'0};
        freeAllocRequest = '0;
        freeValid = '0;
        freePhys = '{default:'0};
        prfReadAddr = '{default:'0};
        prfAllocValid = '0;
        prfAllocPhys = '{default:'0};
        prfWriteValid = '0;
        prfWritePhys = '{default:'0};
        prfWriteData = '{default:'0};
        robAllocValid = '0;
        robAllocEntry = '{default:'0};
        robCompleteValid = '0;
        robCompleteTag = '{default:'0};
        robCompleteException = '0;
        robCompleteCause = '{default:'0};
        robCompleteValue = '{default:'0};
        robCommitReady = '0;
        iqDispatch = '{default:'0};
        iqWakeValid = '0;
        iqWakePhys = '{default:'0};
        iqRecoverValid = 1'b0;
        iqRecoverTag = '0;
        iqRecoverYoungerMask = '0;
        iqIssueReady = 2'b11;
        iqFallbackReady = 1'b0;
        lsqAllocValid = '0;
        lsqAllocEntry = '{default:'0};
        lsqAddressValid = '0;
        lsqAddressTag = '{default:'0};
        lsqAddress = '{default:'0};
        lsqStoreDataValid = '0;
        lsqStoreDataTag = '{default:'0};
        lsqStoreData = '{default:'0};
        lsqRetireCount = '0;
        lsqIssueValid = 1'b0;
        lsqIssueTag = '0;
        lsqIssueAddress = '0;
        lsqIssueMemCtr = MEM_WORD;

        tick();
        rst = 1'b1;
        #1;

        if (freeCount != 16 || freeAllocPhys[0] != 32 || freeAllocPhys[1] != 32)
            $fatal(1, "free-list reset/allocation view is incorrect");
        // Lane 1 receives a distinct tag when both lanes actually request one.
        freeAllocRequest = 2'b11;
        #1;
        if (!&freeAllocReady || freeAllocPhys[0] != 32 || freeAllocPhys[1] != 33)
            $fatal(1, "dual free-list allocation is incorrect");

        renameValid = 2'b11;
        renameArchRd[0] = 5;
        renameArchRd[1] = 5;
        renameNewPhys[0] = 32;
        renameNewPhys[1] = 33;
        ratSourceA[1] = 5;
        #1;
        if (renameOldPhys[0] != 5 || renameOldPhys[1] != 32 || ratSourceAPhys[1] != 32)
            $fatal(1, "same-cycle rename bypass is incorrect");
        tick();
        renameValid = '0;
        freeAllocRequest = '0;
        ratSourceA[0] = 5;
        #1;
        if (ratSourceAPhys[0] != 33) $fatal(1, "speculative RAT update failed");

        prfAllocValid[0] = 1'b1;
        prfAllocPhys[0] = 34;
        tick();
        prfAllocValid = '0;
        prfReadAddr[0] = 34;
        #1;
        if (prfReadReady[0]) $fatal(1, "new PRF destination must be busy");
        prfWriteValid[0] = 1'b1;
        prfWritePhys[0] = 34;
        prfWriteData[0] = 32'h1234_5678;
        #1;
        if (!prfReadReady[0] || prfReadData[0] != 32'h1234_5678)
            $fatal(1, "PRF writeback bypass failed");
        tick();
        prfWriteValid = '0;

        robAllocEntry[0].pc = 32'h100;
        robAllocEntry[1].pc = 32'h104;
        robAllocValid = 2'b11;
        #1;
        savedRobTag0 = robAllocTag[0];
        savedRobTag1 = robAllocTag[1];
        tick();
        robAllocValid = '0;
        robCompleteValid[0] = 1'b1;
        robCompleteTag[0] = savedRobTag1;
        tick();
        robCompleteValid = '0;
        if (robCommitValid != 2'b00) $fatal(1, "ROB retired past an incomplete head");
        robCompleteValid[0] = 1'b1;
        robCompleteTag[0] = savedRobTag0;
        tick();
        robCompleteValid = '0;
        if (robCommitValid != 2'b11) $fatal(1, "ROB did not expose completed prefix");
        robCommitReady = 2'b11;
        tick();
        robCommitReady = '0;
        if (!robEmpty) $fatal(1, "ROB did not retire both entries");

        iqDispatch[0].valid = 1'b1;
        iqDispatch[0].useRs1 = 1'b1;
        iqDispatch[0].src1Phys = 35;
        iqDispatch[0].src1Ready = 1'b0;
        tick();
        iqDispatch = '{default:'0};
        if (|iqIssueValid) $fatal(1, "IQ issued an unready operation");
        iqWakeValid[0] = 1'b1;
        iqWakePhys[0] = 35;
        #1;
        if (!((iqIssueValid[0] && (iqIssueUop[0].src1Phys == 35)) ||
              (iqIssueValid[1] && (iqIssueUop[1].src1Phys == 35))))
            $fatal(1, "IQ same-cycle wakeup/select failed");
        tick();
        iqWakeValid = '0;
        if (!iqEmpty) $fatal(1, "IQ did not remove issued operation");

        iqDispatch[0].valid = 1'b1;
        iqDispatch[0].useRs1 = 1'b1;
        iqDispatch[0].src1Phys = 36;
        iqDispatch[0].src1Ready = 1'b0;
        iqWakeValid[0] = 1'b1;
        iqWakePhys[0] = 36;
        tick();
        iqDispatch = '{default:'0};
        iqWakeValid = '0;
        if (!(|iqIssueValid)) $fatal(1, "IQ lost a dispatch-cycle wakeup");
        tick();
        if (!iqEmpty) $fatal(1, "IQ did not issue dispatch-cycle wakeup operation");

        // Exercise sparse dual-dispatch lanes. Ages must reflect accepted
        // program order; using the original lane number gives the lane-1 uop
        // and the following cycle's lane-0 uop equal ages.
        iqIssueReady = 2'b00;
        rst = 1'b0;
        tick();
        rst = 1'b1;
        #1;
        iqDispatch[1].valid = 1'b1;
        iqDispatch[1].pc = 32'h208;
        tick();
        iqDispatch = '{default:'0};
        iqDispatch[0].valid = 1'b1;
        iqDispatch[0].pc = 32'h20c;
        tick();
        iqDispatch = '{default:'0};
        #1;
        if (iqCount != 2 ||
            issueQueue.entries[0].pc != 32'h208 ||
            issueQueue.entries[1].pc != 32'h20c ||
            issueQueue.ages[0] >= issueQueue.ages[1])
            $fatal(1, "IQ sparse-lane age ordering failed: count=%0d pc=%h/%h/%h/%h age=%0d/%0d/%0d/%0d",
                   iqCount,
                   issueQueue.entries[0].pc, issueQueue.entries[1].pc,
                   issueQueue.entries[2].pc, issueQueue.entries[3].pc,
                   issueQueue.ages[0], issueQueue.ages[1],
                   issueQueue.ages[2], issueQueue.ages[3]);
        iqIssueReady = 2'b11;
        tick();
        tick();
        tick();
        tick();
        if (!iqEmpty) $fatal(1, "IQ sparse-lane test did not drain");

        // Two independent integer uops must be selected together from the
        // unified queue.  This is the basic ALU+ALU dual-issue case that the
        // former split single-issue queues could not perform.
        iqIssueReady = 2'b00;
        iqDispatch[0].valid = 1'b1;
        iqDispatch[0].fuClass = FU_INTEGER;
        iqDispatch[0].pc = 32'h300;
        iqDispatch[1].valid = 1'b1;
        iqDispatch[1].fuClass = FU_INTEGER;
        iqDispatch[1].pc = 32'h304;
        #1;
        if (iqDispatchReady != 2'b11)
            $fatal(1, "unified IQ rejected dual dispatch: ready=%b count=%0d",
                   iqDispatchReady, iqCount);
        tick();
        iqDispatch = '{default:'0};
        #1;
        if (iqIssueValid != 2'b11 ||
            !(((iqIssueUop[0].pc == 32'h300) && (iqIssueUop[1].pc == 32'h304)) ||
              ((iqIssueUop[0].pc == 32'h304) && (iqIssueUop[1].pc == 32'h300))))
            $fatal(1, "unified IQ failed ALU+ALU dual selection: valid=%b pc=%h/%h count=%0d",
                   iqIssueValid, iqIssueUop[0].pc, iqIssueUop[1].pc, iqCount);
        iqIssueReady = 2'b11;
        tick();
        if (!iqEmpty) $fatal(1, "unified IQ did not retire both issue ports");

        // A blocked memory candidate must not consume one of the two issue
        // slots when two independent ALU uops are available.
        iqIssueReady = 2'b00;
        iqDispatch[0].valid = 1'b1;
        iqDispatch[0].fuClass = FU_MEMORY;
        iqDispatch[0].wbSelect = WB_MEM;
        iqDispatch[0].pc = 32'h310;
        iqDispatch[1].valid = 1'b1;
        iqDispatch[1].fuClass = FU_INTEGER;
        iqDispatch[1].pc = 32'h314;
        tick();
        iqDispatch = '{default:'0};
        iqDispatch[0].valid = 1'b1;
        iqDispatch[0].fuClass = FU_INTEGER;
        iqDispatch[0].pc = 32'h318;
        tick();
        iqDispatch = '{default:'0};
        #1;
        if (!iqIssueValid[0] || (iqIssueUop[0].pc != 32'h310) ||
            !iqIssueValid[1] || (iqIssueUop[1].pc != 32'h314) ||
            !iqFallbackValid || (iqFallbackUop.pc != 32'h318))
            $fatal(1,
                   "IQ did not expose memory + two ALU candidates: valid=%b fallback=%b pc=%h/%h/%h",
                   iqIssueValid, iqFallbackValid, iqIssueUop[0].pc,
                   iqIssueUop[1].pc, iqFallbackUop.pc);
        iqIssueReady = 2'b10;
        iqFallbackReady = 1'b1;
        tick();
        iqIssueReady = 2'b00;
        iqFallbackReady = 1'b0;
        #1;
        if ((iqCount != 1) || !iqIssueValid[0] ||
            (iqIssueUop[0].pc != 32'h310))
            $fatal(1,
                   "IQ fallback did not retain only the blocked memory uop: count=%0d valid=%b pc=%h",
                   iqCount, iqIssueValid, iqIssueUop[0].pc);
        iqIssueReady = 2'b01;
        tick();
        iqIssueReady = 2'b00;
        if (!iqEmpty) $fatal(1, "IQ failed to retire retained memory candidate");

        // A Store becomes schedulable when its address source is ready even
        // if its data source is still pending. The outgoing uop must preserve
        // src2Ready=0 so the LSU does not capture stale PRF data.
        iqDispatch[0].valid = 1'b1;
        iqDispatch[0].fuClass = FU_MEMORY;
        iqDispatch[0].dataWriteEnable = 1'b1;
        iqDispatch[0].useRs1 = 1'b1;
        iqDispatch[0].useRs2 = 1'b1;
        iqDispatch[0].src1Phys = phys_reg_addr_t'(1);
        iqDispatch[0].src1Ready = 1'b1;
        iqDispatch[0].src2Phys = phys_reg_addr_t'(37);
        iqDispatch[0].src2Ready = 1'b0;
        iqDispatch[0].pc = 32'h31c;
        tick();
        iqDispatch = '{default:'0};
        #1;
        if (!iqIssueValid[0] || (iqIssueUop[0].pc != 32'h31c) ||
            iqIssueUop[0].src2Ready)
            $fatal(1, "IQ did not split Store address/data readiness");
        iqIssueReady = 2'b01;
        tick();
        iqIssueReady = 2'b00;
        if (!iqEmpty) $fatal(1, "address-ready Store did not leave IQ");

        // A recovery can coincide with both issue handshakes.  The older Load
        // on port 0 survives the branch's younger mask architecturally, but it
        // has nevertheless left the IQ and must not remain as a stale entry
        // after its LSQ/ROB tags are eventually recycled.
        iqIssueReady = 2'b00;
        iqDispatch[0].valid = 1'b1;
        iqDispatch[0].fuClass = FU_MEMORY;
        iqDispatch[0].wbSelect = WB_MEM;
        iqDispatch[0].pc = 32'h400;
        iqDispatch[0].robTag = rob_tag_t'(3);
        iqDispatch[0].lsqTag = lsq_tag_t'(2);
        iqDispatch[1].valid = 1'b1;
        iqDispatch[1].fuClass = FU_BRANCH;
        iqDispatch[1].branchCtr = BR_BNE;
        iqDispatch[1].pc = 32'h404;
        iqDispatch[1].robTag = rob_tag_t'(4);
        tick();
        iqDispatch = '{default:'0};
        #1;
        if (iqIssueValid != 2'b11 ||
            (iqIssueUop[0].pc != 32'h400) ||
            (iqIssueUop[1].pc != 32'h404))
            $fatal(1,
                   "IQ recovery setup did not select older Load + branch: valid=%b pc=%h/%h",
                   iqIssueValid, iqIssueUop[0].pc, iqIssueUop[1].pc);

        iqRecoverValid = 1'b1;
        iqRecoverTag = rob_tag_t'(4);
        iqRecoverYoungerMask = '0;
        iqIssueReady = 2'b11;
        tick();
        iqRecoverValid = 1'b0;
        iqIssueReady = 2'b00;
        #1;
        if (!iqEmpty || (iqCount != 0))
            $fatal(1,
                   "IQ retained an older Load issued with a recovering branch: count=%0d",
                   iqCount);

        lsqAllocEntry[0].isStore = 1'b1;
        lsqAllocEntry[0].robTag = 3;
        lsqAllocEntry[0].memCtr = MEM_WORD;
        lsqAllocEntry[0].storeDataPhys = phys_reg_addr_t'(37);
        lsqAllocEntry[1].isLoad = 1'b1;
        lsqAllocEntry[1].robTag = 4;
        lsqAllocEntry[1].memCtr = MEM_WORD;
        lsqAllocValid = 2'b11;
        #1;
        savedLsqTag = lsqAllocTag[0];
        savedLsqLoadTag = lsqAllocTag[1];
        tick();
        lsqAllocValid = '0;
        lsqIssueValid = 1'b1;
        lsqIssueTag = savedLsqLoadTag;
        lsqIssueAddress = 32'h200;
        #1;
        if (lsqIssueReady)
            $fatal(1, "load passed an older store with unknown address");
        lsqAddressValid[0] = 1'b1;
        lsqAddressTag[0] = savedLsqTag;
        lsqAddress[0] = 32'h200;
        // Data arrives independently over the PRF writeback broadcast after
        // the Store address has already executed.
        prfWriteValid[0] = 1'b1;
        prfWritePhys[0] = phys_reg_addr_t'(37);
        prfWriteData[0] = 32'hCAFE_BABE;
        tick();
        lsqAddressValid = '0;
        prfWriteValid = '0;
        if (!lsqHead[0].addressReady || !lsqHead[0].dataReady ||
            lsqHead[0].address != 32'h200 || lsqHead[0].storeData != 32'hCAFE_BABE)
            $fatal(1, "LSQ readiness update failed");
        #1;
        if (!lsqIssueReady || !lsqForwardValid ||
            lsqForwardData != 32'hCAFE_BABE)
            $fatal(1, "LSQ store-to-load forwarding failed");
        lsqIssueAddress = 32'h204;
        #1;
        if (!lsqIssueReady || lsqForwardValid)
            $fatal(1, "non-aliasing load was unnecessarily blocked");
        lsqIssueValid = 1'b0;
        lsqRetireCount = 2;
        tick();
        lsqRetireCount = '0;
        if (!lsqEmpty) $fatal(1, "LSQ retirement failed");

        $display("OoO structure smoke test: PASS");
        $finish;
    end

endmodule
