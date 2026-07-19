// Blocking direct-mapped instruction cache.
//
// The cache launches two synchronous tag/data reads for PC and PC+4.  The two
// addresses normally share a line, but independent read contexts also cover a
// fetch pair that crosses a 16-byte line boundary.  A hit response is held
// until responseReady_i; when it is consumed, the next lookup may be accepted
// on the same edge, preserving one fetch pair per cycle in the hit path.
//
// Misses are blocking.  Every missing line is refilled as four consecutive
// backing-memory word requests, installed atomically, and then synchronously
// retried from the retained lookup context. flush_i cancels all in-flight state without
// invalidating cache contents.  This is safe for wrong-path instruction fills
// and lets a redirect launch a replacement lookup on the flush edge.
module InstructionCache
    import TypesPkg::*;
#(
    parameter int ADDR_W = WORD_SIZE,
    parameter int INSN_W = INS_SIZE,
    parameter int CACHE_BYTES = 4096,
    parameter int LINE_BYTES = 16
)
(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  flush_i,

    input  logic                  requestValid_i,
    output logic                  requestReady_o,
    input  logic [ADDR_W-1:0]     requestPc_i,
    input  logic [ADDR_W-1:0]     requestPc1_i,

    output logic                  responseValid_o,
    input  logic                  responseReady_i,
    output logic [INSN_W-1:0]     responseInsn_o,
    output logic [INSN_W-1:0]     responseInsn1_o,

    output logic                  backingRequestValid_o,
    input  logic                  backingRequestReady_i,
    output logic [ADDR_W-1:0]     backingRequestAddr_o,
    input  logic                  backingResponseValid_i,
    input  logic [INSN_W-1:0]     backingResponseWord_i,

    output logic [63:0]           perfRequestCount_o,
    output logic [63:0]           perfHitCount_o,
    output logic [63:0]           perfMissCount_o,
    output logic [63:0]           perfLineMissCount_o,
    output logic [63:0]           perfMissStallCycles_o,
    output logic [63:0]           perfRefillLineCount_o,
    output logic [63:0]           perfRefillCycles_o,
    output logic [63:0]           perfCrosslineMissCount_o,
    output logic [63:0]           perfResponseBackpressureCycles_o
);

    localparam int WORD_BYTES = INSN_W / 8;
    localparam int WORD_BYTE_OFFSET_W = $clog2(WORD_BYTES);
    localparam int WORDS_PER_LINE = LINE_BYTES / WORD_BYTES;
    localparam int LINE_W = LINE_BYTES * 8;
    localparam int SET_NUM = CACHE_BYTES / LINE_BYTES;
    localparam int LINE_OFFSET_W = $clog2(LINE_BYTES);
    localparam int INDEX_W = $clog2(SET_NUM);
    localparam int TAG_W = ADDR_W - LINE_OFFSET_W - INDEX_W;
    localparam int WORD_INDEX_W = $clog2(WORDS_PER_LINE);
    localparam int REFILL_COUNT_W = $clog2(WORDS_PER_LINE + 1);

    // The Tag/Data arrays deliberately live in a reset-free synchronous RAM
    // process below.  Valid bits make uninitialised contents unobservable.
    // ram_style is understood by FPGA tools such as Vivado; other tools may
    // ignore the hint while still recognising the synchronous RAM template.
    (* ram_style = "block" *)
    logic [TAG_W-1:0] tagArray [0:SET_NUM-1];
    (* ram_style = "block" *)
    logic [LINE_W-1:0] dataArray [0:SET_NUM-1];
    logic [SET_NUM-1:0] validArray;

    logic lookupValid;
    logic [ADDR_W-1:0] lookupPc;
    logic [ADDR_W-1:0] lookupPc1;
    logic [TAG_W-1:0] lookupTag;
    logic [TAG_W-1:0] lookupTag1;
    logic lookupReadValid;
    logic lookupReadValid1;
    logic [TAG_W-1:0] lookupReadTag;
    logic [TAG_W-1:0] lookupReadTag1;
    logic [LINE_W-1:0] lookupReadLine;
    logic [LINE_W-1:0] lookupReadLine1;

    logic [INDEX_W-1:0] requestIndex;
    logic [INDEX_W-1:0] requestIndex1;
    logic [TAG_W-1:0] requestTag;
    logic [TAG_W-1:0] requestTag1;
    logic [WORD_INDEX_W-1:0] responseWordIndex;
    logic [WORD_INDEX_W-1:0] responseWordIndex1;
    logic lookupHit;
    logic lookupHit1;
    logic requestFire;
    logic initialLookupPending;
    logic initialLookupHit;
    logic initialLookupMiss;
    logic [1:0] initialLineMissCount;
    logic initialCrosslineMiss;

    logic refillActive;
    logic retryPending;
    logic [ADDR_W-1:0] refillLineBase;
    logic [INDEX_W-1:0] refillIndex;
    logic [TAG_W-1:0] refillTag;
    logic secondRefillPending;
    logic [ADDR_W-1:0] secondRefillLineBase;
    logic [REFILL_COUNT_W-1:0] refillIssuedCount;
    logic [REFILL_COUNT_W-1:0] refillReceivedCount;
    logic [LINE_W-1:0] refillBuffer;
    logic [LINE_W-1:0] refillBufferWithResponse;
    logic backingRequestFire;
    logic arrayReadEnable;
    logic [INDEX_W-1:0] arrayReadIndex;
    logic [INDEX_W-1:0] arrayReadIndex1;
    logic arrayWriteEnable;

    integer refillWord;

    function automatic logic [ADDR_W-1:0] lineBase(
        input logic [ADDR_W-1:0] address
    );
        lineBase = {address[ADDR_W-1:LINE_OFFSET_W],
                    {LINE_OFFSET_W{1'b0}}};
    endfunction

    function automatic logic [INDEX_W-1:0] lineIndex(
        input logic [ADDR_W-1:0] address
    );
        lineIndex = address[LINE_OFFSET_W + INDEX_W - 1:LINE_OFFSET_W];
    endfunction

    function automatic logic [TAG_W-1:0] lineTag(
        input logic [ADDR_W-1:0] address
    );
        lineTag = address[ADDR_W-1:LINE_OFFSET_W + INDEX_W];
    endfunction

    assign requestIndex = lineIndex(requestPc_i);
    assign requestIndex1 = lineIndex(requestPc1_i);
    assign requestTag = lineTag(requestPc_i);
    assign requestTag1 = lineTag(requestPc1_i);

    assign responseWordIndex =
        lookupPc[LINE_OFFSET_W-1:WORD_BYTE_OFFSET_W];
    assign responseWordIndex1 =
        lookupPc1[LINE_OFFSET_W-1:WORD_BYTE_OFFSET_W];

    assign lookupHit = lookupValid && lookupReadValid &&
                       (lookupReadTag == lookupTag);
    assign lookupHit1 = lookupValid && lookupReadValid1 &&
                        (lookupReadTag1 == lookupTag1);
    assign responseValid_o = !flush_i && lookupHit && lookupHit1;

    // Only the first synchronous lookup of an accepted fetch pair contributes
    // a Hit/Miss classification.  The internal lookup after a refill is a
    // retry of that same request and must not turn one miss into a later hit.
    // initialLookupPending also prevents a held response from being counted on
    // every response-backpressure cycle.
    assign initialLookupHit = !flush_i && initialLookupPending &&
        lookupValid && lookupHit && lookupHit1;
    assign initialLookupMiss = !flush_i && initialLookupPending &&
        lookupValid && !(lookupHit && lookupHit1);
    assign initialLineMissCount =
        {1'b0, !lookupHit} +
        {1'b0, (lineBase(lookupPc1) != lineBase(lookupPc)) && !lookupHit1};
    assign initialCrosslineMiss = initialLookupMiss &&
        (lineBase(lookupPc1) != lineBase(lookupPc));

    // With no buffered lookup, a request can launch immediately.  A consumed
    // hit can be replaced on the same edge.  A detected miss closes ready
    // combinationally, preventing a duplicate request before refill starts.
    assign requestReady_o = rst && (flush_i ||
        (!refillActive && !retryPending && (!lookupValid ||
         (responseValid_o && responseReady_i))));
    assign requestFire = requestValid_i && requestReady_o;

    always_comb begin
        responseInsn_o = '0;
        responseInsn1_o = '0;
        if (responseValid_o) begin
            responseInsn_o = INSN_W'(lookupReadLine >>
                (responseWordIndex * INSN_W));
            responseInsn1_o = INSN_W'(lookupReadLine1 >>
                (responseWordIndex1 * INSN_W));
        end
    end

    assign backingRequestValid_o = !flush_i && refillActive &&
        (refillIssuedCount < REFILL_COUNT_W'(WORDS_PER_LINE));
    assign backingRequestFire = backingRequestValid_o &&
                                backingRequestReady_i;
    assign backingRequestAddr_o = refillLineBase +
        ({{(ADDR_W-REFILL_COUNT_W){1'b0}}, refillIssuedCount}
         << WORD_BYTE_OFFSET_W);

    assign arrayReadEnable = (requestFire && !arrayWriteEnable) || retryPending;
    assign arrayReadIndex = requestFire ? requestIndex : lineIndex(lookupPc);
    assign arrayReadIndex1 = requestFire ? requestIndex1 : lineIndex(lookupPc1);
    assign arrayWriteEnable = !flush_i && refillActive && backingResponseValid_i &&
        (refillReceivedCount == REFILL_COUNT_W'(WORDS_PER_LINE-1));

    // Merge the current synchronous backing-memory response into the partial
    // line.  The loop avoids an out-of-range variable part-select when the
    // counter is at its terminal value outside a valid response cycle.
    always_comb begin
        refillBufferWithResponse = refillBuffer;
        for (refillWord = 0; refillWord < WORDS_PER_LINE;
             refillWord = refillWord + 1) begin
            if (refillReceivedCount == REFILL_COUNT_W'(refillWord))
                refillBufferWithResponse[
                    refillWord * INSN_W +: INSN_W] =
                    backingResponseWord_i;
        end
    end

    // Two synchronous read ports are needed only for the PC/PC+4 pair.  A
    // refill write is mutually exclusive with a lookup, allowing the two
    // physical BRAM ports to be reused rather than creating asynchronous or
    // combinational reads.  No reset on this process is intentional: clearing
    // large RAM arrays would normally force synthesis into flip-flops/LUT RAM.
    always_ff @(posedge clk) begin
        if (arrayWriteEnable) begin
            dataArray[refillIndex] <= refillBufferWithResponse;
            tagArray[refillIndex] <= refillTag;
        end else if (arrayReadEnable) begin
            lookupReadTag <= tagArray[arrayReadIndex];
            lookupReadTag1 <= tagArray[arrayReadIndex1];
            lookupReadLine <= dataArray[arrayReadIndex];
            lookupReadLine1 <= dataArray[arrayReadIndex1];
        end
    end

    // Simulation/performance counters use the same reset-to-reset observation
    // window as the existing backend counters.  A request is one accepted
    // PC/PC+4 fetch pair; line misses may therefore increase by two for a
    // cross-line pair.  Miss-stall cycles deliberately exclude downstream
    // response backpressure, which is reported separately.
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            perfRequestCount_o <= '0;
            perfHitCount_o <= '0;
            perfMissCount_o <= '0;
            perfLineMissCount_o <= '0;
            perfMissStallCycles_o <= '0;
            perfRefillLineCount_o <= '0;
            perfRefillCycles_o <= '0;
            perfCrosslineMissCount_o <= '0;
            perfResponseBackpressureCycles_o <= '0;
        end else begin
            perfRequestCount_o <= perfRequestCount_o +
                (requestFire ? 64'd1 : 64'd0);
            perfHitCount_o <= perfHitCount_o +
                (initialLookupHit ? 64'd1 : 64'd0);
            perfMissCount_o <= perfMissCount_o +
                (initialLookupMiss ? 64'd1 : 64'd0);
            perfLineMissCount_o <= perfLineMissCount_o +
                (initialLookupMiss ?
                    {{62{1'b0}}, initialLineMissCount} : 64'd0);
            perfMissStallCycles_o <= perfMissStallCycles_o +
                ((!flush_i &&
                  (initialLookupMiss || refillActive || retryPending)) ?
                    64'd1 : 64'd0);
            perfRefillLineCount_o <= perfRefillLineCount_o +
                (arrayWriteEnable ? 64'd1 : 64'd0);
            perfRefillCycles_o <= perfRefillCycles_o +
                ((refillActive && !flush_i) ? 64'd1 : 64'd0);
            perfCrosslineMissCount_o <= perfCrosslineMissCount_o +
                (initialCrosslineMiss ? 64'd1 : 64'd0);
            perfResponseBackpressureCycles_o <=
                perfResponseBackpressureCycles_o +
                ((responseValid_o && !responseReady_i) ? 64'd1 : 64'd0);
        end
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            lookupValid <= 1'b0;
            initialLookupPending <= 1'b0;
            lookupPc <= '0;
            lookupPc1 <= '0;
            lookupTag <= '0;
            lookupTag1 <= '0;
            lookupReadValid <= 1'b0;
            lookupReadValid1 <= 1'b0;
            refillActive <= 1'b0;
            retryPending <= 1'b0;
            refillLineBase <= '0;
            refillIndex <= '0;
            refillTag <= '0;
            secondRefillPending <= 1'b0;
            secondRefillLineBase <= '0;
            refillIssuedCount <= '0;
            refillReceivedCount <= '0;
            refillBuffer <= '0;
            validArray <= '0;
        end else begin
            if (flush_i) begin
                // Cache lines survive redirects.  Only transient lookup and
                // refill state is discarded; any one-cycle stale backing
                // response is ignored because refillActive is cleared.
                lookupValid <= 1'b0;
                initialLookupPending <= 1'b0;
                refillActive <= 1'b0;
                retryPending <= 1'b0;
                secondRefillPending <= 1'b0;
                refillIssuedCount <= '0;
                refillReceivedCount <= '0;
                refillBuffer <= '0;
            end else if (refillActive) begin
                if (backingRequestFire)
                    refillIssuedCount <= refillIssuedCount + 1'b1;

                if (backingResponseValid_i) begin
                    refillBuffer <= refillBufferWithResponse;
                    if (refillReceivedCount ==
                        REFILL_COUNT_W'(WORDS_PER_LINE-1)) begin
                        validArray[refillIndex] <= 1'b1;

                        refillIssuedCount <= '0;
                        refillReceivedCount <= '0;
                        refillBuffer <= '0;
                        if (secondRefillPending) begin
                            refillLineBase <= secondRefillLineBase;
                            refillIndex <= lineIndex(secondRefillLineBase);
                            refillTag <= lineTag(secondRefillLineBase);
                            secondRefillPending <= 1'b0;
                        end else begin
                            refillActive <= 1'b0;
                            // The miss still owns the original accepted F0
                            // request.  Retry its two synchronous array reads
                            // internally after the installed line is visible;
                            // do not ask the fetch controller/BPU to reissue it.
                            retryPending <= 1'b1;
                        end
                    end else begin
                        refillReceivedCount <= refillReceivedCount + 1'b1;
                    end
                end
            end else if (retryPending) begin
                retryPending <= 1'b0;
                lookupValid <= 1'b1;
                lookupReadValid <= validArray[lineIndex(lookupPc)];
                lookupReadValid1 <= validArray[lineIndex(lookupPc1)];
            end else if (lookupValid) begin
                if (initialLookupHit || initialLookupMiss)
                    initialLookupPending <= 1'b0;
                if (responseValid_o) begin
                    if (responseReady_i)
                        lookupValid <= 1'b0;
                end else begin
                    // At least one of the two line lookups missed.  Refill the
                    // older address first, then the second address only when it
                    // belongs to a distinct line and also missed.
                    lookupValid <= 1'b0;
                    refillActive <= 1'b1;
                    refillIssuedCount <= '0;
                    refillReceivedCount <= '0;
                    refillBuffer <= '0;
                    if (!lookupHit) begin
                        refillLineBase <= lineBase(lookupPc);
                        refillIndex <= lineIndex(lookupPc);
                        refillTag <= lineTag(lookupPc);
                        secondRefillPending <=
                            (lineBase(lookupPc1) != lineBase(lookupPc)) &&
                            !lookupHit1;
                        secondRefillLineBase <= lineBase(lookupPc1);
                    end else begin
                        refillLineBase <= lineBase(lookupPc1);
                        refillIndex <= lineIndex(lookupPc1);
                        refillTag <= lineTag(lookupPc1);
                        secondRefillPending <= 1'b0;
                        secondRefillLineBase <= '0;
                    end
                end
            end

            // A redirect may cancel old state and launch its replacement lookup
            // on the same edge.  In the normal hit path this block also replaces
            // a consumed response without introducing a bubble.
            if (requestFire) begin
                // A redirect is allowed to replace a refill on the same edge.
                // If that edge also installs the final refill beat, the two
                // BRAM ports are occupied by the write, so defer the redirect
                // lookup by one cycle rather than pretending a read occurred.
                lookupValid <= !arrayWriteEnable;
                initialLookupPending <= 1'b1;
                if (arrayWriteEnable)
                    retryPending <= 1'b1;
                lookupPc <= requestPc_i;
                lookupPc1 <= requestPc1_i;
                lookupTag <= requestTag;
                lookupTag1 <= requestTag1;
                if (!arrayWriteEnable) begin
                    lookupReadValid <= validArray[requestIndex];
                    lookupReadValid1 <= validArray[requestIndex1];
                end
            end
        end
    end

    initial begin
        if ((CACHE_BYTES <= 0) || (LINE_BYTES <= 0) ||
            ((CACHE_BYTES % LINE_BYTES) != 0) ||
            ((LINE_BYTES % WORD_BYTES) != 0) ||
            ((1 << INDEX_W) != SET_NUM) ||
            ((1 << LINE_OFFSET_W) != LINE_BYTES) ||
            (WORDS_PER_LINE != 4))
            $error("InstructionCache geometry must be power-of-two 4-word lines");
    end

endmodule
