`timescale 1ns/1ps

module lsu_pending_tb;
    import TypesPkg::*;

    logic clk;
    logic rst;
    logic flush;
    logic recoverValid;
    logic [ROB_ENTRY_NUM-1:0] recoverYoungerMask;

    logic issueValid;
    renamed_uop_t issueUop;
    word_t sourceA;
    word_t sourceB;
    logic orderingReady;
    logic forwardValid;
    word_t forwardData;

    logic memoryRequestReady;
    logic memoryResponseValid;
    rob_tag_t memoryResponseId;
    word_t memoryResponseData;
    logic memoryResponseReady;
    logic busy;
    logic issueReady;

    logic completionValid;
    rob_tag_t completionRobTag;
    logic completionException;
    logic [5:0] completionCause;
    word_t completionValue;
    logic writebackValid;
    phys_reg_addr_t writebackPhys;
    word_t writebackData;

    logic executeValid;
    logic loadReadValid;
    rob_tag_t loadRequestId;
    logic isStore;
    word_t address;
    word_t storeData;
    mem_access_t memoryAccess;
    lsq_tag_t lsqTag;
    logic completionReady;

    integer cycleCount;
    integer acceptedLoadCount;
    integer firstAcceptCycle;
    integer secondAcceptCycle;

    LoadStoreExecutionUnit dut (
        .clk(clk),
        .rst(rst),
        .flush_i(flush),
        .recoverValid_i(recoverValid),
        .recoverYoungerMask_i(recoverYoungerMask),
        .issueValid_i(issueValid),
        .issueUop_i(issueUop),
        .sourceA_i(sourceA),
        .sourceB_i(sourceB),
        .orderingReady_i(orderingReady),
        .forwardValid_i(forwardValid),
        .forwardData_i(forwardData),
        .memoryRequestReady_i(memoryRequestReady),
        .memoryResponseValid_i(memoryResponseValid),
        .memoryResponseId_i(memoryResponseId),
        .memoryResponseData_i(memoryResponseData),
        .memoryResponseReady_o(memoryResponseReady),
        .busy_o(busy),
        .issueReady_o(issueReady),
        .completionValid_o(completionValid),
        .completionRobTag_o(completionRobTag),
        .completionException_o(completionException),
        .completionCause_o(completionCause),
        .completionValue_o(completionValue),
        .writebackValid_o(writebackValid),
        .writebackPhys_o(writebackPhys),
        .writebackData_o(writebackData),
        .executeValid_o(executeValid),
        .loadReadValid_o(loadReadValid),
        .loadRequestId_o(loadRequestId),
        .isStore_o(isStore),
        .address_o(address),
        .storeData_o(storeData),
        .memoryAccess_o(memoryAccess),
        .lsqTag_o(lsqTag),
        .completionReady_i(completionReady)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            cycleCount <= 0;
            acceptedLoadCount <= 0;
            firstAcceptCycle <= -1;
            secondAcceptCycle <= -1;
        end else begin
            cycleCount <= cycleCount + 1;
            if (loadReadValid && issueReady) begin
                if (acceptedLoadCount == 0)
                    firstAcceptCycle <= cycleCount;
                else if (acceptedLoadCount == 1)
                    secondAcceptCycle <= cycleCount;
                acceptedLoadCount <= acceptedLoadCount + 1;
            end
        end
    end

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic issueLoad(
        input rob_tag_t tag,
        input phys_reg_addr_t destination,
        input lsq_tag_t queueTag,
        input word_t base,
        input word_t offset
    );
        begin
            @(negedge clk);
            issueUop = '0;
            issueUop.valid = 1'b1;
            issueUop.fuClass = FU_MEMORY;
            issueUop.registerWriteEnable = 1'b1;
            issueUop.dataWriteEnable = 1'b0;
            issueUop.memCtr = MEM_WORD;
            issueUop.destPhys = destination;
            issueUop.robTag = tag;
            issueUop.lsqTag = queueTag;
            issueUop.immediate = offset;
            sourceA = base;
            sourceB = '0;
            issueValid = 1'b1;
            #1;
            if (!loadReadValid || !issueReady)
                $fatal(1, "Load tag %0d was not accepted", tag);
            if ((loadRequestId != tag) || (address != (base + offset)) ||
                !executeValid || isStore || (memoryAccess != MEM_WORD))
                $fatal(1, "Load request metadata mismatch for tag %0d", tag);
            @(posedge clk);
            #1;
            issueValid = 1'b0;
        end
    endtask

    task automatic returnLoad(
        input rob_tag_t tag,
        input phys_reg_addr_t expectedPhys,
        input word_t expectedAddress,
        input word_t data
    );
        begin
            @(negedge clk);
            memoryResponseId = tag;
            memoryResponseData = data;
            memoryResponseValid = 1'b1;
            #1;
            if (!memoryResponseReady)
                $fatal(1, "Load response tag %0d was not accepted", tag);
            @(posedge clk);
            #1;
            memoryResponseValid = 1'b0;
            if (!completionValid || (completionRobTag != tag) ||
                completionException || (completionCause != '0) ||
                (completionValue != expectedAddress))
                $fatal(1, "ROB completion mismatch for Load tag %0d", tag);
            if (!writebackValid || (writebackPhys != expectedPhys) ||
                (writebackData != data))
                $fatal(1, "PRF writeback mismatch for Load tag %0d", tag);
        end
    endtask

    initial begin
        localparam rob_tag_t FIRST_TAG = rob_tag_t'(3);
        localparam rob_tag_t SECOND_TAG = rob_tag_t'(11);
        localparam rob_tag_t KILLED_TAG = rob_tag_t'(7);
        localparam phys_reg_addr_t FIRST_PHYS = phys_reg_addr_t'(18);
        localparam phys_reg_addr_t SECOND_PHYS = phys_reg_addr_t'(27);
        localparam phys_reg_addr_t KILLED_PHYS = phys_reg_addr_t'(31);

        rst = 1'b0;
        flush = 1'b0;
        recoverValid = 1'b0;
        recoverYoungerMask = '0;
        issueValid = 1'b0;
        issueUop = '0;
        sourceA = '0;
        sourceB = '0;
        orderingReady = 1'b1;
        forwardValid = 1'b0;
        forwardData = '0;
        memoryRequestReady = 1'b1;
        memoryResponseValid = 1'b0;
        memoryResponseId = '0;
        memoryResponseData = '0;
        completionReady = 1'b1;

        repeat (2) tick();
        rst = 1'b1;
        #1;

        // Two independent misses leave the IQ on consecutive cycles.  The
        // response ID, rather than response order, must select saved metadata.
        issueLoad(FIRST_TAG, FIRST_PHYS, lsq_tag_t'(1),
                  32'h0000_1000, 32'h0000_0020);
        issueLoad(SECOND_TAG, SECOND_PHYS, lsq_tag_t'(2),
                  32'h0000_2000, 32'h0000_0040);
        if ((acceptedLoadCount != 2) ||
            (secondAcceptCycle != (firstAcceptCycle + 1)))
            $fatal(1, "Loads were not accepted on consecutive cycles: %0d/%0d",
                   firstAcceptCycle, secondAcceptCycle);
        if (!busy)
            $fatal(1, "LSU did not retain the two pending Loads");

        // Complete the younger request first, then the older one one cycle
        // later.  Both ROB and PRF destinations/data must follow the tags.
        returnLoad(SECOND_TAG, SECOND_PHYS, 32'h0000_2040,
                   32'hBBBB_2222);
        returnLoad(FIRST_TAG, FIRST_PHYS, 32'h0000_1020,
                   32'hAAAA_1111);
        tick();
        if (busy || completionValid || writebackValid)
            $fatal(1, "LSU did not retire both reverse-order responses");

        // Recovery marks a pending younger Load as killed.  Its eventual
        // response still handshakes and drains, but produces no ROB/PRF event.
        issueLoad(KILLED_TAG, KILLED_PHYS, lsq_tag_t'(3),
                  32'h0000_3000, 32'h0000_000c);
        @(negedge clk);
        recoverYoungerMask = '0;
        recoverYoungerMask[KILLED_TAG] = 1'b1;
        recoverValid = 1'b1;
        @(posedge clk);
        #1;
        recoverValid = 1'b0;
        recoverYoungerMask = '0;

        @(negedge clk);
        memoryResponseId = KILLED_TAG;
        memoryResponseData = 32'hDEAD_BEEF;
        memoryResponseValid = 1'b1;
        #1;
        if (!memoryResponseReady)
            $fatal(1, "Killed Load response was not drained");
        @(posedge clk);
        #1;
        memoryResponseValid = 1'b0;
        if (completionValid || writebackValid || busy)
            $fatal(1, "Killed Load response produced an architectural event");

        repeat (2) tick();
        if (completionValid || writebackValid)
            $fatal(1, "Killed response leaked a delayed completion");

        $display("lsu_pending_tb PASS");
        $finish;
    end

endmodule
