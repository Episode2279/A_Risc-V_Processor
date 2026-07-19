`timescale 1ns/1ps

module icache_tb;
    import TypesPkg::*;

    localparam int CACHE_BYTES = 64;
    localparam int LINE_BYTES = 16;
    localparam int MAX_WAIT_CYCLES = 200;

    logic clk;
    logic rst;
    logic flush;

    logic requestValid;
    logic requestReady;
    word_t requestPc;
    word_t requestPc1;

    logic responseValid;
    logic responseReady;
    instruction_t responseInsn;
    instruction_t responseInsn1;

    logic backingRequestValid;
    logic backingRequestReady;
    word_t backingRequestAddress;
    logic backingResponseValid;
    instruction_t backingResponseWord;

    logic [63:0] perfRequestCount;
    logic [63:0] perfHitCount;
    logic [63:0] perfMissCount;
    logic [63:0] perfLineMissCount;
    logic [63:0] perfMissStallCycles;
    logic [63:0] perfRefillLineCount;
    logic [63:0] perfRefillCycles;
    logic [63:0] perfCrosslineMissCount;
    logic [63:0] perfResponseBackpressureCycles;

    integer backingReadCount;
    integer waitCycles;
    word_t heldInsn;
    word_t heldInsn1;

    InstructionCache #(
        .CACHE_BYTES(CACHE_BYTES),
        .LINE_BYTES(LINE_BYTES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .flush_i(flush),
        .requestValid_i(requestValid),
        .requestReady_o(requestReady),
        .requestPc_i(requestPc),
        .requestPc1_i(requestPc1),
        .responseValid_o(responseValid),
        .responseReady_i(responseReady),
        .responseInsn_o(responseInsn),
        .responseInsn1_o(responseInsn1),
        .backingRequestValid_o(backingRequestValid),
        .backingRequestReady_i(backingRequestReady),
        .backingRequestAddr_o(backingRequestAddress),
        .backingResponseValid_i(backingResponseValid),
        .backingResponseWord_i(backingResponseWord),
        .perfRequestCount_o(perfRequestCount),
        .perfHitCount_o(perfHitCount),
        .perfMissCount_o(perfMissCount),
        .perfLineMissCount_o(perfLineMissCount),
        .perfMissStallCycles_o(perfMissStallCycles),
        .perfRefillLineCount_o(perfRefillLineCount),
        .perfRefillCycles_o(perfRefillCycles),
        .perfCrosslineMissCount_o(perfCrosslineMissCount),
        .perfResponseBackpressureCycles_o(
            perfResponseBackpressureCycles)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic instruction_t backingWord(input word_t address);
        backingWord = 32'hA500_0000 ^ (address >> 2);
    endfunction

    // A fully pipelined synchronous backing SRAM: every accepted word request
    // returns exactly one cycle later.  This permits four consecutive refill
    // beats and also leaves a stale response for the flush test to discard.
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            backingResponseValid <= 1'b0;
            backingResponseWord <= '0;
            backingReadCount <= 0;
        end else begin
            backingResponseValid <= backingRequestValid && backingRequestReady;
            if (backingRequestValid && backingRequestReady) begin
                backingResponseWord <= backingWord(backingRequestAddress);
                backingReadCount <= backingReadCount + 1;
            end
        end
    end

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic issuePair(input word_t pc0, input word_t pc1);
        begin
            @(negedge clk);
            requestPc = pc0;
            requestPc1 = pc1;
            requestValid = 1'b1;
            while (!requestReady)
                @(negedge clk);
            @(posedge clk);
            #1;
            requestValid = 1'b0;
        end
    endtask

    task automatic waitForResponse(
        input instruction_t expected0,
        input instruction_t expected1
    );
        begin
            waitCycles = 0;
            while (!responseValid && (waitCycles < MAX_WAIT_CYCLES)) begin
                tick();
                waitCycles = waitCycles + 1;
            end
            if (!responseValid)
                $fatal(1, "timed out waiting for I-cache response");
            if ((responseInsn !== expected0) || (responseInsn1 !== expected1))
                $fatal(1,
                       "I-cache response mismatch expected=%h/%h got=%h/%h",
                       expected0, expected1, responseInsn, responseInsn1);
        end
    endtask

    task automatic consumeResponse;
        begin
            if (!responseValid)
                $fatal(1, "attempted to consume an invalid I-cache response");
            if (!responseReady)
                $fatal(1, "consumeResponse requires responseReady");
            tick();
        end
    endtask

    initial begin
        integer readsBefore;

        rst = 1'b0;
        flush = 1'b0;
        requestValid = 1'b0;
        requestPc = '0;
        requestPc1 = '0;
        responseReady = 1'b1;
        backingRequestReady = 1'b1;

        repeat (2) tick();
        rst = 1'b1;
        #1;

        // A same-line cold pair installs one complete 16-byte line.
        readsBefore = backingReadCount;
        issuePair(32'h0000_0020, 32'h0000_0024);
        waitForResponse(backingWord(32'h20), backingWord(32'h24));
        if ((backingReadCount - readsBefore) != 4)
            $fatal(1, "same-line refill used %0d reads, expected 4",
                   backingReadCount - readsBefore);
        consumeResponse();

        // The identical lookup is now a synchronous cache hit with no backing
        // traffic.
        readsBefore = backingReadCount;
        issuePair(32'h0000_0020, 32'h0000_0024);
        waitForResponse(backingWord(32'h20), backingWord(32'h24));
        if (backingReadCount != readsBefore)
            $fatal(1, "I-cache hit unexpectedly accessed backing memory");
        consumeResponse();

        // PC=0x3c and PC+4=0x40 occupy adjacent lines.  Both are cold, so the
        // blocking cache must perform two four-word refills before responding.
        readsBefore = backingReadCount;
        issuePair(32'h0000_003c, 32'h0000_0040);
        waitForResponse(backingWord(32'h3c), backingWord(32'h40));
        if ((backingReadCount - readsBefore) != 8)
            $fatal(1, "cross-line refill used %0d reads, expected 8",
                   backingReadCount - readsBefore);
        consumeResponse();

        // A valid response and its data must remain stable while the fetch
        // consumer applies backpressure; the blocking cache accepts no new
        // request during that interval.
        responseReady = 1'b0;
        readsBefore = backingReadCount;
        issuePair(32'h0000_0028, 32'h0000_002c);
        waitForResponse(backingWord(32'h28), backingWord(32'h2c));
        heldInsn = responseInsn;
        heldInsn1 = responseInsn1;
        repeat (3) begin
            tick();
            if (!responseValid || (responseInsn !== heldInsn) ||
                (responseInsn1 !== heldInsn1))
                $fatal(1, "I-cache response changed under backpressure");
            if (requestReady)
                $fatal(1, "I-cache accepted a request while response stalled");
        end
        if (backingReadCount != readsBefore)
            $fatal(1, "stalled hit unexpectedly accessed backing memory");
        responseReady = 1'b1;
        consumeResponse();

        // Consume one cached response and launch another cached pair on the
        // same edge.  The second response must appear without a bubble/refill.
        issuePair(32'h0000_0020, 32'h0000_0024);
        waitForResponse(backingWord(32'h20), backingWord(32'h24));
        @(negedge clk);
        requestPc = 32'h0000_003c;
        requestPc1 = 32'h0000_0040;
        requestValid = 1'b1;
        if (!requestReady)
            $fatal(1, "consumed hit could not accept its replacement request");
        @(posedge clk);
        #1;
        requestValid = 1'b0;
        if (!responseValid ||
            (responseInsn !== backingWord(32'h3c)) ||
            (responseInsn1 !== backingWord(32'h40)))
            $fatal(1, "back-to-back cached fetch pair introduced a bubble");
        consumeResponse();

        // Begin a cold refill, then redirect on the first response edge.  flush
        // must discard the old transaction and accept the cached replacement
        // pair on that same edge; the stale backing response may not leak out.
        readsBefore = backingReadCount;
        issuePair(32'h0000_0100, 32'h0000_0104);
        waitCycles = 0;
        while ((backingReadCount == readsBefore) &&
               (waitCycles < MAX_WAIT_CYCLES)) begin
            tick();
            waitCycles = waitCycles + 1;
        end
        if (backingReadCount == readsBefore)
            $fatal(1, "cold transaction never launched a refill");

        @(negedge clk);
        flush = 1'b1;
        requestPc = 32'h0000_0020;
        requestPc1 = 32'h0000_0024;
        requestValid = 1'b1;
        #1;
        if (!requestReady)
            $fatal(1, "flush did not make the replacement request ready");
        @(posedge clk);
        #1;
        flush = 1'b0;
        requestValid = 1'b0;
        // responseValid is masked combinationally by flush_i.  Allow that mask
        // to settle before deciding whether the replacement hit responded.
        #1;
        waitForResponse(backingWord(32'h20), backingWord(32'h24));
        if ((backingReadCount - readsBefore) != 1)
            $fatal(1, "flushed refill continued for %0d backing reads",
                   backingReadCount - readsBefore);
        consumeResponse();
        repeat (2) tick();
        if (backingReadCount != (readsBefore + 1))
            $fatal(1, "stale refill traffic survived flush");

        // Exercise the harder redirect collision: assert flush on the edge
        // which returns the fourth/final refill word.  A two-port BRAM cannot
        // install that line and perform both redirect reads simultaneously;
        // the cache must defer/retry the replacement lookup instead of pairing
        // its PC with stale Tag/Data output registers.
        readsBefore = backingReadCount;
        issuePair(32'h0000_0200, 32'h0000_0204);
        waitCycles = 0;
        while (((backingReadCount - readsBefore) < 4) &&
               (waitCycles < MAX_WAIT_CYCLES)) begin
            tick();
            waitCycles = waitCycles + 1;
        end
        if ((backingReadCount - readsBefore) != 4)
            $fatal(1, "final-beat collision setup issued %0d refill reads",
                   backingReadCount - readsBefore);

        @(negedge clk);
        flush = 1'b1;
        requestPc = 32'h0000_003c;
        requestPc1 = 32'h0000_0040;
        requestValid = 1'b1;
        #1;
        if (!requestReady)
            $fatal(1, "final-beat flush did not accept redirect lookup");
        @(posedge clk);
        #1;
        flush = 1'b0;
        requestValid = 1'b0;
        #1;
        waitForResponse(backingWord(32'h3c), backingWord(32'h40));
        consumeResponse();

        // The ten accepted fetch pairs above contain four first-look misses:
        // one ordinary cold line, one two-line crossing, and two refills later
        // cancelled by redirects.  Internal post-refill retries must not be
        // counted as additional hits.
        if (perfRequestCount != 64'd10)
            $fatal(1, "I-cache request counter=%0d expected=10",
                   perfRequestCount);
        if ((perfHitCount != 64'd6) || (perfMissCount != 64'd4))
            $fatal(1, "I-cache hit/miss counters=%0d/%0d expected=6/4",
                   perfHitCount, perfMissCount);
        if ((perfLineMissCount != 64'd5) ||
            (perfCrosslineMissCount != 64'd1))
            $fatal(1, "I-cache line/cross counters=%0d/%0d expected=5/1",
                   perfLineMissCount, perfCrosslineMissCount);
        if (perfRefillLineCount != 64'd3)
            $fatal(1, "I-cache completed refill lines=%0d expected=3",
                   perfRefillLineCount);
        if ((perfRefillCycles == 0) ||
            (perfMissStallCycles <= perfRefillCycles))
            $fatal(1, "I-cache miss/refill cycle counters invalid: %0d/%0d",
                   perfMissStallCycles, perfRefillCycles);
        if (perfResponseBackpressureCycles != 64'd3)
            $fatal(1, "I-cache response backpressure=%0d expected=3",
                   perfResponseBackpressureCycles);

        $display("icache_tb PASS");
        $finish;
    end

endmodule
