module dcache_tb;
    import TypesPkg::*;

    logic clk = 1'b0;
    logic rst = 1'b0;

    logic requestValid;
    logic requestReady;
    logic requestWrite;
    word_t requestAddress;
    word_t requestWriteData;
    mem_access_t requestAccess;
    rob_tag_t requestId;
    logic responseValid;
    logic responseReady;
    word_t responseData;
    rob_tag_t responseId;

    logic memoryRequestValid;
    logic memoryRequestReady;
    logic memoryRequestWrite;
    word_t memoryRequestAddress;
    word_t memoryRequestWriteData;
    mem_access_t memoryRequestAccess;
    logic memoryResponseValid;
    logic memoryResponseReady;
    word_t memoryResponseData;

    word_t fromHost;
    word_t toHost;
    logic uartValid;
    logic [7:0] uartData;
    logic toHostHit;
    logic uartHit;
    logic fromHostHit;

    logic [63:0] perfRequestCount;
    logic [63:0] perfLoadHitCount;
    logic [63:0] perfLoadMissCount;
    logic [63:0] perfStoreHitCount;
    logic [63:0] perfStoreMissCount;
    logic [63:0] perfBusyCycles;
    logic [63:0] perfRefillLineCount;
    logic [63:0] perfRefillCycles;
    logic [63:0] perfMmioRequestCount;
    logic [63:0] perfRequestBackpressureCycles;

    integer backingReadCount;
    integer backingWriteCount;
    integer mmioReadCount;
    integer mmioWriteCount;
    integer uartPulseCount;
    logic [7:0] lastUartData;
    word_t backingReadAddressLog [0:63];

    always #5 clk = ~clk;

    DataCache dut (
        .clk(clk),
        .rst(rst),
        .requestValid_i(requestValid),
        .requestReady_o(requestReady),
        .requestWrite_i(requestWrite),
        .requestAddress_i(requestAddress),
        .requestWriteData_i(requestWriteData),
        .requestAccess_i(requestAccess),
        .requestId_i(requestId),
        .responseValid_o(responseValid),
        .responseReady_i(responseReady),
        .responseData_o(responseData),
        .responseId_o(responseId),
        .idle_o(),
        .memoryRequestValid_o(memoryRequestValid),
        .memoryRequestReady_i(memoryRequestReady),
        .memoryRequestWrite_o(memoryRequestWrite),
        .memoryRequestAddress_o(memoryRequestAddress),
        .memoryRequestWriteData_o(memoryRequestWriteData),
        .memoryRequestAccess_o(memoryRequestAccess),
        .memoryResponseValid_i(memoryResponseValid),
        .memoryResponseReady_o(memoryResponseReady),
        .memoryResponseData_i(memoryResponseData),
        .perfRequestCount_o(perfRequestCount),
        .perfLoadHitCount_o(perfLoadHitCount),
        .perfLoadMissCount_o(perfLoadMissCount),
        .perfStoreHitCount_o(perfStoreHitCount),
        .perfStoreMissCount_o(perfStoreMissCount),
        .perfBusyCycles_o(perfBusyCycles),
        .perfRefillLineCount_o(perfRefillLineCount),
        .perfRefillCycles_o(perfRefillCycles),
        .perfMmioRequestCount_o(perfMmioRequestCount),
        .perfRequestBackpressureCycles_o(perfRequestBackpressureCycles)
    );

    dataMem backingMem (
        .clk(clk),
        .rst(rst),
        .requestValid_i(memoryRequestValid),
        .requestReady_o(memoryRequestReady),
        .requestWrite_i(memoryRequestWrite),
        .requestAddress_i(memoryRequestAddress),
        .requestWriteData_i(memoryRequestWriteData),
        .requestAccess_i(memoryRequestAccess),
        .responseValid_o(memoryResponseValid),
        .responseReady_i(memoryResponseReady),
        .responseData_o(memoryResponseData),
        .fromHost_i(fromHost),
        .toHost_o(toHost),
        .uartValid_o(uartValid),
        .uartData_o(uartData),
        .toHostHit_o(toHostHit),
        .uartHit_o(uartHit),
        .fromHostHit_o(fromHostHit)
    );

    function automatic logic isMmio(input word_t address);
        begin
            isMmio = (address >= 32'h0000_FFE0) &&
                     (address <= 32'h0000_FFFF);
        end
    endfunction

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            backingReadCount <= 0;
            backingWriteCount <= 0;
            mmioReadCount <= 0;
            mmioWriteCount <= 0;
            uartPulseCount <= 0;
            lastUartData <= '0;
        end else begin
            if (memoryRequestValid && memoryRequestReady) begin
                if (memoryRequestWrite) begin
                    backingWriteCount <= backingWriteCount + 1;
                    if (isMmio(memoryRequestAddress))
                        mmioWriteCount <= mmioWriteCount + 1;
                end else begin
                    backingReadAddressLog[backingReadCount] <=
                        memoryRequestAddress;
                    backingReadCount <= backingReadCount + 1;
                    if (isMmio(memoryRequestAddress))
                        mmioReadCount <= mmioReadCount + 1;
                end
            end

            if (uartValid) begin
                uartPulseCount <= uartPulseCount + 1;
                lastUartData <= uartData;
            end
        end
    end

    task automatic driveRequestUntilAccepted(
        input logic writeRequest,
        input word_t address,
        input word_t writeData,
        input mem_access_t accessMode,
        input rob_tag_t id
    );
        begin
            @(negedge clk);
            requestValid = 1'b1;
            requestWrite = writeRequest;
            requestAddress = address;
            requestWriteData = writeData;
            requestAccess = accessMode;
            requestId = id;
            while (!requestReady)
                @(negedge clk);
            @(posedge clk);
            #1;
            requestValid = 1'b0;
        end
    endtask

    task automatic expectResponse(
        input word_t expectedData,
        input rob_tag_t expectedId
    );
        begin
            while (!responseValid)
                @(negedge clk);
            if ((responseData !== expectedData) ||
                (responseId !== expectedId)) begin
                $fatal(1,
                    "response mismatch: expected id=%0d data=%08x, got id=%0d data=%08x",
                    expectedId, expectedData, responseId, responseData);
            end
            @(posedge clk);
            #1;
        end
    endtask

    task automatic expectLoad(
        input word_t address,
        input mem_access_t accessMode,
        input word_t expectedData,
        input rob_tag_t id
    );
        begin
            driveRequestUntilAccepted(1'b0, address, '0, accessMode, id);
            expectResponse(expectedData, id);
        end
    endtask

    task automatic waitRefillComplete;
        begin
            while (dut.mshrValid)
                @(negedge clk);
        end
    endtask

    task automatic sendStoreAndWaitForBacking(
        input word_t address,
        input word_t writeData,
        input mem_access_t accessMode,
        input rob_tag_t id
    );
        integer countBefore;
        begin
            countBefore = backingWriteCount;
            driveRequestUntilAccepted(
                1'b1, address, writeData, accessMode, id);
            while (backingWriteCount == countBefore)
                @(negedge clk);
        end
    endtask

    initial begin : watchdog
        repeat (5000) @(posedge clk);
        $fatal(1, "dcache_tb timed out");
    end

    initial begin : test_sequence
        integer countBefore;
        integer firstRead;
        integer hitIndex;
        word_t hitAddress [0:5];
        word_t hitData [0:5];
        rob_tag_t hitId [0:5];
        word_t heldData;
        rob_tag_t heldId;

        requestValid = 1'b0;
        requestWrite = 1'b0;
        requestAddress = '0;
        requestWriteData = '0;
        requestAccess = MEM_WORD;
        requestId = '0;
        responseReady = 1'b1;
        fromHost = 32'hD00D_F00D;

        repeat (2) @(negedge clk);
        // Line A, set 0.
        backingMem.mem[0] = 32'h80FF_7F01;
        backingMem.mem[1] = 32'h1122_3344;
        backingMem.mem[2] = 32'h5566_7788;
        backingMem.mem[3] = 32'h99AA_BBCC;
        // Line B, set 1.
        backingMem.mem[4] = 32'hDEAD_BEEF;
        backingMem.mem[5] = 32'h0102_0304;
        backingMem.mem[6] = 32'h0506_0708;
        backingMem.mem[7] = 32'h090A_0B0C;
        // Line C, set 2, used for hit-under-miss.
        backingMem.mem[8] = 32'hCAFE_BABE;
        backingMem.mem[9] = 32'h1357_2468;
        backingMem.mem[10] = 32'h89AB_CDEF;
        backingMem.mem[11] = 32'h7654_3210;
        // 0x400 conflicts with line A.
        backingMem.mem[256] = 32'h0BAD_F00D;
        backingMem.mem[257] = 32'h1111_2222;
        backingMem.mem[258] = 32'h3333_4444;
        backingMem.mem[259] = 32'h5555_6666;
        rst = 1'b1;

        // Critical-word-first: a cold access to word 2 must issue addresses
        // 8,c,0,4 and return after only the first backing read has launched.
        firstRead = backingReadCount;
        driveRequestUntilAccepted(
            1'b0, 32'h0000_0008, '0, MEM_WORD, rob_tag_t'(1));
        while (!responseValid)
            @(negedge clk);
        if ((responseData !== 32'h5566_7788) ||
            (responseId !== rob_tag_t'(1)))
            $fatal(1, "critical response data/id mismatch");
        if (backingReadCount != firstRead + 1)
            $fatal(1, "early restart waited for more than the critical read");
        @(posedge clk);
        #1;
        waitRefillComplete();
        if (backingReadCount != firstRead + 4)
            $fatal(1, "refill did not issue exactly four reads");
        if ((backingReadAddressLog[firstRead+0] !== 32'h0000_0008) ||
            (backingReadAddressLog[firstRead+1] !== 32'h0000_000C) ||
            (backingReadAddressLog[firstRead+2] !== 32'h0000_0000) ||
            (backingReadAddressLog[firstRead+3] !== 32'h0000_0004))
            $fatal(1, "critical-word-first refill order mismatch");

        // Warm a second set for sustained hit and hit-under-miss tests.
        expectLoad(32'h0000_0010, MEM_WORD, 32'hDEAD_BEEF,
                   rob_tag_t'(2));
        waitRefillComplete();

        // Six hit Loads must be accepted on six consecutive rising edges;
        // each synchronous result appears with the matching request ID.
        hitAddress[0] = 32'h0000_0000;
        hitAddress[1] = 32'h0000_0004;
        hitAddress[2] = 32'h0000_0008;
        hitAddress[3] = 32'h0000_000C;
        hitAddress[4] = 32'h0000_0010;
        hitAddress[5] = 32'h0000_0014;
        hitData[0] = 32'h80FF_7F01;
        hitData[1] = 32'h1122_3344;
        hitData[2] = 32'h5566_7788;
        hitData[3] = 32'h99AA_BBCC;
        hitData[4] = 32'hDEAD_BEEF;
        hitData[5] = 32'h0102_0304;
        for (hitIndex = 0; hitIndex < 6; hitIndex = hitIndex + 1)
            hitId[hitIndex] = rob_tag_t'(10 + hitIndex);

        countBefore = backingReadCount;
        for (hitIndex = 0; hitIndex < 6; hitIndex = hitIndex + 1) begin
            @(negedge clk);
            requestValid = 1'b1;
            requestWrite = 1'b0;
            requestAddress = hitAddress[hitIndex];
            requestWriteData = '0;
            requestAccess = MEM_WORD;
            requestId = hitId[hitIndex];
            if (!requestReady)
                $fatal(1, "hit pipeline inserted a request bubble at %0d",
                       hitIndex);
            @(posedge clk);
            #1;
            if (!responseValid || (responseData !== hitData[hitIndex]) ||
                (responseId !== hitId[hitIndex]))
                $fatal(1, "pipelined hit response mismatch at %0d", hitIndex);
        end
        @(negedge clk);
        requestValid = 1'b0;
        @(posedge clk);
        #1;
        if (backingReadCount != countBefore)
            $fatal(1, "pipelined hits accessed backing memory");

        // Response backpressure holds both data and ID stable.
        responseReady = 1'b0;
        driveRequestUntilAccepted(
            1'b0, 32'h0000_0010, '0, MEM_WORD, rob_tag_t'(20));
        while (!responseValid)
            @(negedge clk);
        heldData = responseData;
        heldId = responseId;
        repeat (3) begin
            @(negedge clk);
            if (!responseValid || (responseData !== heldData) ||
                (responseId !== heldId) || requestReady)
                $fatal(1, "backpressured response was not held safely");
        end
        responseReady = 1'b1;
        @(posedge clk);
        #1;

        // Miss line C at word 1.  When its critical response is consumed,
        // accept a hit to set 1 in the same edge while refill remains active.
        firstRead = backingReadCount;
        driveRequestUntilAccepted(
            1'b0, 32'h0000_0024, '0, MEM_WORD, rob_tag_t'(21));
        while (!responseValid)
            @(negedge clk);
        if ((responseData !== 32'h1357_2468) ||
            (responseId !== rob_tag_t'(21)) || !dut.mshrValid)
            $fatal(1, "hit-under-miss critical response mismatch");

        @(negedge clk);
        requestValid = 1'b1;
        requestWrite = 1'b0;
        requestAddress = 32'h0000_0010;
        requestWriteData = '0;
        requestAccess = MEM_WORD;
        requestId = rob_tag_t'(22);
        #1;
        if (!requestReady)
            $fatal(1,
                "different-set hit blocked: mshr=%0b mset=%0d iset=%0d lvalid=%0b advance=%0b missalloc=%0b",
                dut.mshrValid, dut.mshrSetReg, dut.incomingSet,
                dut.lookupStageValidReg, dut.lookupStageAdvance,
                dut.lookupMissAllocate);
        @(posedge clk);
        #1;
        if (!responseValid || (responseData !== 32'hDEAD_BEEF) ||
            (responseId !== rob_tag_t'(22)) || !dut.mshrValid)
            $fatal(1, "different-set hit-under-miss response mismatch");

        // Stores, MMIO, and same-set Loads are all safely serialized while a
        // refill owns the single backing port / direct-mapped destination set.
        @(negedge clk);
        requestWrite = 1'b1;
        requestAddress = 32'h0000_0000;
        requestWriteData = 32'h1234_5678;
        requestId = rob_tag_t'(23);
        #1;
        if (requestReady)
            $fatal(1, "Store entered during active refill");
        requestWrite = 1'b0;
        requestAddress = FROMHOST_ADDR;
        #1;
        if (requestReady)
            $fatal(1, "MMIO request entered during active refill");
        requestAddress = 32'h0000_0420;
        #1;
        if (requestReady)
            $fatal(1, "same-set request entered during partial refill");
        @(posedge clk);
        #1;
        requestValid = 1'b0;
        waitRefillComplete();
        if (backingReadCount != firstRead + 4)
            $fatal(1, "hit-under-miss refill read count mismatch");

        // A Store hit writes through and a same-edge following Load receives
        // the merged value rather than the BRAM's old read-during-write data.
        @(negedge clk);
        requestValid = 1'b1;
        requestWrite = 1'b1;
        requestAddress = 32'h0000_0001;
        requestWriteData = 32'h0000_00AA;
        requestAccess = MEM_BYTE;
        requestId = rob_tag_t'(24);
        if (!requestReady)
            $fatal(1, "Store hit was not accepted");
        @(posedge clk);
        #1;
        @(negedge clk);
        requestWrite = 1'b0;
        requestAddress = 32'h0000_0000;
        requestWriteData = '0;
        requestAccess = MEM_WORD;
        requestId = rob_tag_t'(25);
        if (!requestReady)
            $fatal(1, "Store-to-Load pipeline inserted a bubble");
        @(posedge clk);
        #1;
        if (!responseValid || (responseData !== 32'h80FF_AA01) ||
            (responseId !== rob_tag_t'(25)))
            $fatal(1, "Store-to-Load BRAM bypass failed");
        @(negedge clk);
        requestValid = 1'b0;
        @(posedge clk);
        #1;
        if (backingMem.mem[0] !== 32'h80FF_AA01)
            $fatal(1, "Store hit did not write through");

        // A same-set Store miss writes backing memory without allocating or
        // evicting the resident line.
        sendStoreAndWaitForBacking(
            32'h0000_0400, 32'hAABB_CCDD, MEM_WORD, rob_tag_t'(26));
        if (backingMem.mem[256] !== 32'hAABB_CCDD)
            $fatal(1, "Store-miss backing write failed");
        countBefore = backingReadCount;
        expectLoad(32'h0000_0000, MEM_WORD, 32'h80FF_AA01,
                   rob_tag_t'(27));
        if (backingReadCount != countBefore)
            $fatal(1, "Store miss allocated or evicted the resident line");

        // All RV32I cached load formatting remains intact.
        expectLoad(32'h0000_0002, MEM_BYTE,   32'hFFFF_FFFF,
                   rob_tag_t'(28));
        expectLoad(32'h0000_0002, MEM_BYTE_U, 32'h0000_00FF,
                   rob_tag_t'(29));
        expectLoad(32'h0000_0002, MEM_HALF,   32'hFFFF_80FF,
                   rob_tag_t'(30));
        expectLoad(32'h0000_0002, MEM_HALF_U, 32'h0000_80FF,
                   rob_tag_t'(31));

        sendStoreAndWaitForBacking(
            32'h0000_0002, 32'h0000_1234, MEM_HALF, rob_tag_t'(35));
        expectLoad(32'h0000_0000, MEM_WORD, 32'h1234_AA01,
                   rob_tag_t'(36));
        sendStoreAndWaitForBacking(
            32'h0000_0000, 32'h5566_7788, MEM_WORD, rob_tag_t'(37));
        expectLoad(32'h0000_0000, MEM_WORD, 32'h5566_7788,
                   rob_tag_t'(38));

        // MMIO bypasses the cache exactly once and preserves response IDs.
        countBefore = mmioReadCount;
        expectLoad(FROMHOST_ADDR, MEM_WORD, 32'hD00D_F00D,
                   rob_tag_t'(32));
        if (mmioReadCount != countBefore + 1)
            $fatal(1, "fromhost did not issue one uncached read");

        countBefore = mmioWriteCount;
        sendStoreAndWaitForBacking(
            TOHOST_ADDR, 32'h0000_0001, MEM_WORD, rob_tag_t'(33));
        sendStoreAndWaitForBacking(
            UART_TX_ADDR, 32'h0000_0041, MEM_BYTE, rob_tag_t'(34));
        repeat (2) @(negedge clk);
        if ((toHost !== 32'h0000_0001) ||
            (mmioWriteCount != countBefore + 2) ||
            (uartPulseCount != 1) || (lastUartData != 8'h41))
            $fatal(1, "MMIO Store side effect mismatch");

        if (perfRequestCount < 64'd20)
            $fatal(1, "request counter did not advance");
        if ((perfLoadHitCount == 0) || (perfLoadMissCount < 3) ||
            (perfStoreHitCount == 0) || (perfStoreMissCount == 0) ||
            (perfRefillLineCount != perfLoadMissCount) ||
            (perfRefillCycles == 0) || (perfBusyCycles == 0) ||
            (perfMmioRequestCount != 3) ||
            (perfRequestBackpressureCycles == 0))
            $fatal(1, "cache performance counter mismatch");

        $display("dcache_tb PASS: requests=%0d hits=%0d misses=%0d refillCycles=%0d",
                 perfRequestCount, perfLoadHitCount, perfLoadMissCount,
                 perfRefillCycles);
        $finish;
    end

endmodule
