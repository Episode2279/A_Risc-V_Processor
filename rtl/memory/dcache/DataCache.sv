module DataCache
    import TypesPkg::*;
#(
    parameter int DATA_W = WORD_SIZE,
    parameter int ADDR_W = WORD_SIZE,
    parameter int SET_COUNT = 64,
    parameter int LINE_BYTES = 16,
    parameter logic [ADDR_W-1:0] MMIO_BASE_ADDR = 32'h0000_FFE0,
    parameter logic [ADDR_W-1:0] MMIO_LAST_ADDR = 32'h0000_FFFF
)
(
    input  logic                  clk,
    input  logic                  rst,

    // Elastic CPU-side request/response interface.  Cached Load hits can be
    // accepted and returned every cycle when responseReady_i remains high.
    input  logic                  requestValid_i,
    output logic                  requestReady_o,
    input  logic                  requestWrite_i,
    input  logic [ADDR_W-1:0]     requestAddress_i,
    input  logic [DATA_W-1:0]     requestWriteData_i,
    input  mem_access_t           requestAccess_i,
    input  rob_tag_t              requestId_i,
    output logic                  responseValid_o,
    input  logic                  responseReady_i,
    output logic [DATA_W-1:0]     responseData_o,
    output rob_tag_t              responseId_o,
    output logic                  idle_o,

    // The backing port remains a single ordered request/response stream.
    output logic                  memoryRequestValid_o,
    input  logic                  memoryRequestReady_i,
    output logic                  memoryRequestWrite_o,
    output logic [ADDR_W-1:0]     memoryRequestAddress_o,
    output logic [DATA_W-1:0]     memoryRequestWriteData_o,
    output mem_access_t           memoryRequestAccess_o,
    input  logic                  memoryResponseValid_i,
    output logic                  memoryResponseReady_o,
    input  logic [DATA_W-1:0]     memoryResponseData_i,

    output logic [63:0]           perfRequestCount_o,
    output logic [63:0]           perfLoadHitCount_o,
    output logic [63:0]           perfLoadMissCount_o,
    output logic [63:0]           perfStoreHitCount_o,
    output logic [63:0]           perfStoreMissCount_o,
    output logic [63:0]           perfBusyCycles_o,
    output logic [63:0]           perfRefillLineCount_o,
    output logic [63:0]           perfRefillCycles_o,
    output logic [63:0]           perfMmioRequestCount_o,
    output logic [63:0]           perfRequestBackpressureCycles_o
);

    localparam int WORD_BYTES = DATA_W / 8;
    localparam int WORDS_PER_LINE = LINE_BYTES / WORD_BYTES;
    localparam int SET_W = $clog2(SET_COUNT);
    localparam int LINE_OFFSET_W = $clog2(LINE_BYTES);
    localparam int WORD_OFFSET_W = $clog2(WORDS_PER_LINE);
    localparam int TAG_W = ADDR_W - SET_W - LINE_OFFSET_W;
    localparam logic [WORD_OFFSET_W-1:0] LAST_REFILL_COUNT =
        WORD_OFFSET_W'(WORDS_PER_LINE - 1);

    typedef enum logic [1:0] {
        REFILL_IDLE,
        REFILL_REQUEST,
        REFILL_RESPONSE
    } refill_state_t;

    refill_state_t refillState;

    logic                  validArray [0:SET_COUNT-1];
    // The cache arrays use one synchronous lookup port and one clocked write
    // port.  A refill may therefore write one set while a hit reads another.
    (* ram_style = "block" *)
    logic [TAG_W-1:0]      tagArray [0:SET_COUNT-1];
    (* ram_style = "block" *)
    logic [DATA_W-1:0]     dataBank0 [0:SET_COUNT-1];
    (* ram_style = "block" *)
    logic [DATA_W-1:0]     dataBank1 [0:SET_COUNT-1];
    (* ram_style = "block" *)
    logic [DATA_W-1:0]     dataBank2 [0:SET_COUNT-1];
    (* ram_style = "block" *)
    logic [DATA_W-1:0]     dataBank3 [0:SET_COUNT-1];

    // One-entry elastic synchronous lookup stage.
    logic                  lookupStageValidReg;
    logic                  lookupWriteReg;
    logic [ADDR_W-1:0]     lookupAddressReg;
    logic [DATA_W-1:0]     lookupWriteDataReg;
    mem_access_t           lookupAccessReg;
    rob_tag_t              lookupIdReg;
    logic [SET_W-1:0]      lookupSetReg;
    logic [TAG_W-1:0]      lookupRequestTagReg;
    logic [WORD_OFFSET_W-1:0] lookupWordReg;
    logic                  lookupMmioReg;
    logic                  lookupMmioReadSentReg;
    logic                  lookupLineValidReg;
    logic [TAG_W-1:0]      lookupArrayTagReg;
    logic [DATA_W-1:0]     lookupDataReg;

    // A single miss-status holding register.  The requested word is fetched
    // first and returned before the remaining three words finish refilling.
    logic                  mshrValid;
    logic [ADDR_W-1:0]     mshrAddressReg;
    mem_access_t           mshrAccessReg;
    rob_tag_t              mshrIdReg;
    logic [SET_W-1:0]      mshrSetReg;
    logic [TAG_W-1:0]      mshrTagReg;
    logic [WORD_OFFSET_W-1:0] refillWordReg;
    logic [WORD_OFFSET_W-1:0] refillCountReg;
    logic                  criticalReturnedReg;

    logic [SET_W-1:0]      incomingSet;
    logic [TAG_W-1:0]      incomingTag;
    logic [WORD_OFFSET_W-1:0] incomingWord;
    logic                  incomingMmio;
    logic                  incomingCachedLoad;
    logic                  incomingAllowedDuringRefill;

    logic                  lookupHit;
    logic                  lookupCachedLoad;
    logic                  lookupCachedStore;
    logic                  lookupMmioLoad;
    logic                  lookupMmioStore;
    logic                  lookupLoadHitResponseValid;
    logic                  lookupMmioResponseValid;
    logic                  criticalResponseValid;
    logic                  lookupResponseSelected;
    logic                  lookupResponseFire;

    logic                  requestFire;
    logic                  memoryRequestFire;
    logic                  memoryResponseFire;
    logic                  lookupMissAllocate;
    logic                  lookupStoreFire;
    logic                  lookupMmioRequestFire;
    logic                  lookupMmioResponseFire;
    logic                  lookupStageAdvance;
    logic                  lookupStageSlotAvailable;
    logic                  cacheStructurallyBusy;

    logic                  arrayLookupReadEnable;
    logic                  arrayRefillWriteEnable;
    logic                  arrayStoreWriteEnable;
    logic [DATA_W-1:0]     mergedStoreData;
    logic                  incomingStoreBypass;

    integer resetSet;

    function automatic logic addressIsMmio(
        input logic [ADDR_W-1:0] address
    );
        begin
            addressIsMmio = (address >= MMIO_BASE_ADDR) &&
                            (address <= MMIO_LAST_ADDR);
        end
    endfunction

    function automatic logic [DATA_W-1:0] formatLoad(
        input logic [DATA_W-1:0] rawWord,
        input mem_access_t       accessMode,
        input logic [1:0]        byteOffset
    );
        logic [DATA_W-1:0] shiftedWord;
        begin
            shiftedWord = rawWord >> (byteOffset * 8);
            unique case (accessMode)
                MEM_BYTE:   formatLoad = {{24{shiftedWord[7]}}, shiftedWord[7:0]};
                MEM_HALF:   formatLoad = {{16{shiftedWord[15]}}, shiftedWord[15:0]};
                MEM_BYTE_U: formatLoad = {24'd0, shiftedWord[7:0]};
                MEM_HALF_U: formatLoad = {16'd0, shiftedWord[15:0]};
                default:    formatLoad = rawWord;
            endcase
        end
    endfunction

    function automatic logic [DATA_W-1:0] mergeStore(
        input logic [DATA_W-1:0] currentWord,
        input logic [DATA_W-1:0] writeData,
        input mem_access_t       accessMode,
        input logic [1:0]        byteOffset
    );
        logic [DATA_W-1:0] mergedWord;
        begin
            mergedWord = currentWord;
            unique case (accessMode)
                MEM_BYTE: begin
                    unique case (byteOffset)
                        2'd0: mergedWord[7:0]   = writeData[7:0];
                        2'd1: mergedWord[15:8]  = writeData[7:0];
                        2'd2: mergedWord[23:16] = writeData[7:0];
                        2'd3: mergedWord[31:24] = writeData[7:0];
                    endcase
                end
                MEM_HALF: begin
                    unique case (byteOffset)
                        2'd0: mergedWord[15:0]  = writeData[15:0];
                        2'd1: mergedWord[23:8]  = writeData[15:0];
                        2'd2: mergedWord[31:16] = writeData[15:0];
                        default: mergedWord = currentWord;
                    endcase
                end
                default: mergedWord = writeData;
            endcase
            mergeStore = mergedWord;
        end
    endfunction

    assign incomingSet = requestAddress_i[LINE_OFFSET_W +: SET_W];
    assign incomingTag = requestAddress_i[ADDR_W-1 -: TAG_W];
    assign incomingWord = requestAddress_i[2 +: WORD_OFFSET_W];
    assign incomingMmio = addressIsMmio(requestAddress_i);
    assign incomingCachedLoad = !requestWrite_i && !incomingMmio;
    assign incomingAllowedDuringRefill = incomingCachedLoad &&
        (incomingSet != mshrSetReg);

    assign lookupHit = lookupLineValidReg &&
        (lookupArrayTagReg == lookupRequestTagReg);
    assign lookupCachedLoad = lookupStageValidReg && !lookupWriteReg &&
        !lookupMmioReg;
    assign lookupCachedStore = lookupStageValidReg && lookupWriteReg &&
        !lookupMmioReg;
    assign lookupMmioLoad = lookupStageValidReg && !lookupWriteReg &&
        lookupMmioReg;
    assign lookupMmioStore = lookupStageValidReg && lookupWriteReg &&
        lookupMmioReg;

    assign criticalResponseValid = mshrValid &&
        (refillState == REFILL_RESPONSE) && !criticalReturnedReg &&
        memoryResponseValid_i;
    assign lookupLoadHitResponseValid = lookupCachedLoad && lookupHit;
    assign lookupMmioResponseValid = lookupMmioLoad &&
        lookupMmioReadSentReg && memoryResponseValid_i;
    assign lookupResponseSelected = !criticalResponseValid &&
        (lookupMmioResponseValid || lookupLoadHitResponseValid);

    always_comb begin
        responseValid_o = 1'b0;
        responseData_o = '0;
        responseId_o = '0;

        if (criticalResponseValid) begin
            responseValid_o = 1'b1;
            responseData_o = formatLoad(
                memoryResponseData_i, mshrAccessReg, mshrAddressReg[1:0]);
            responseId_o = mshrIdReg;
        end else if (lookupMmioResponseValid) begin
            responseValid_o = 1'b1;
            // dataMem already formats uncached byte/half loads.
            responseData_o = memoryResponseData_i;
            responseId_o = lookupIdReg;
        end else if (lookupLoadHitResponseValid) begin
            responseValid_o = 1'b1;
            responseData_o = formatLoad(
                lookupDataReg, lookupAccessReg, lookupAddressReg[1:0]);
            responseId_o = lookupIdReg;
        end
    end

    assign lookupResponseFire = lookupResponseSelected && responseReady_i;
    assign lookupMmioResponseFire = lookupMmioResponseValid &&
        !criticalResponseValid && responseReady_i;

    assign lookupMissAllocate = lookupCachedLoad && !lookupHit && !mshrValid;

    // A lookup entry retires only when its irrevocable action completes.
    always_comb begin
        lookupStageAdvance = 1'b0;
        if (lookupCachedLoad) begin
            if (lookupHit)
                lookupStageAdvance = lookupResponseFire;
            else
                lookupStageAdvance = lookupMissAllocate;
        end else if (lookupCachedStore) begin
            lookupStageAdvance = lookupStoreFire;
        end else if (lookupMmioStore) begin
            lookupStageAdvance = lookupMmioRequestFire;
        end else if (lookupMmioLoad && lookupMmioReadSentReg) begin
            lookupStageAdvance = lookupMmioResponseFire;
        end
    end

    assign lookupStageSlotAvailable = !lookupStageValidReg ||
        lookupStageAdvance;
    // Do not replace a just-allocated miss in the same edge.  This keeps the
    // one-entry lookup/miss transfer unambiguous.  While refill is active only
    // cached Loads to another set may enter the lookup pipeline.
    assign requestReady_o = rst && lookupStageSlotAvailable &&
        !lookupMissAllocate &&
        (!mshrValid || incomingAllowedDuringRefill);
    assign requestFire = requestValid_i && requestReady_o;

    assign memoryRequestFire = memoryRequestValid_o && memoryRequestReady_i;
    assign memoryResponseFire = memoryResponseValid_i && memoryResponseReady_o;

    always_comb begin
        memoryRequestValid_o = 1'b0;
        memoryRequestWrite_o = 1'b0;
        memoryRequestAddress_o = '0;
        memoryRequestWriteData_o = '0;
        memoryRequestAccess_o = MEM_WORD;
        memoryResponseReady_o = 1'b0;

        if (refillState == REFILL_REQUEST) begin
            memoryRequestValid_o = 1'b1;
            memoryRequestAddress_o = {
                mshrAddressReg[ADDR_W-1:LINE_OFFSET_W],
                {LINE_OFFSET_W{1'b0}}
            };
            memoryRequestAddress_o[2 +: WORD_OFFSET_W] = refillWordReg;
        end else if (refillState == REFILL_RESPONSE) begin
            // The first (critical) word is coupled directly to the CPU
            // response.  Later refill beats are consumed unconditionally.
            memoryResponseReady_o = criticalReturnedReg ? 1'b1 :
                                                          responseReady_i;
            if (memoryResponseValid_i && memoryResponseReady_o &&
                (refillCountReg != LAST_REFILL_COUNT)) begin
                memoryRequestValid_o = 1'b1;
                memoryRequestAddress_o = {
                    mshrAddressReg[ADDR_W-1:LINE_OFFSET_W],
                    {LINE_OFFSET_W{1'b0}}
                };
                memoryRequestAddress_o[2 +: WORD_OFFSET_W] =
                    refillWordReg + 1'b1;
            end
        end else if (lookupCachedStore) begin
            memoryRequestValid_o = 1'b1;
            memoryRequestWrite_o = 1'b1;
            memoryRequestAddress_o = lookupAddressReg;
            memoryRequestWriteData_o = lookupWriteDataReg;
            memoryRequestAccess_o = lookupAccessReg;
        end else if ((lookupMmioStore || lookupMmioLoad) &&
                     !lookupMmioReadSentReg) begin
            memoryRequestValid_o = 1'b1;
            memoryRequestWrite_o = lookupWriteReg;
            memoryRequestAddress_o = lookupAddressReg;
            memoryRequestWriteData_o = lookupWriteDataReg;
            memoryRequestAccess_o = lookupAccessReg;
        end else if (lookupMmioLoad && lookupMmioReadSentReg) begin
            memoryResponseReady_o = responseReady_i;
        end
    end

    assign lookupStoreFire = lookupCachedStore && memoryRequestFire &&
        (refillState == REFILL_IDLE);
    assign lookupMmioRequestFire = (lookupMmioStore ||
        (lookupMmioLoad && !lookupMmioReadSentReg)) && memoryRequestFire &&
        (refillState == REFILL_IDLE);

    assign arrayLookupReadEnable = requestFire && !incomingMmio;
    assign arrayRefillWriteEnable = (refillState == REFILL_RESPONSE) &&
        memoryResponseFire;
    assign arrayStoreWriteEnable = lookupStoreFire && lookupHit;
    assign mergedStoreData = mergeStore(
        lookupDataReg, lookupWriteDataReg,
        lookupAccessReg, lookupAddressReg[1:0]);
    assign incomingStoreBypass = arrayStoreWriteEnable &&
        (incomingSet == lookupSetReg) &&
        (incomingTag == lookupRequestTagReg) &&
        (incomingWord == lookupWordReg);

    // Reset-free synchronous Tag/Data arrays.  The explicit read and write
    // operations model a simple dual-port BRAM.  Same-address Store-to-next-
    // request forwarding below defines the otherwise device-specific
    // read-during-write behavior.
    always_ff @(posedge clk) begin
        if (arrayLookupReadEnable) begin
            lookupArrayTagReg <= tagArray[incomingSet];
            unique case (incomingWord)
                2'd0: lookupDataReg <= dataBank0[incomingSet];
                2'd1: lookupDataReg <= dataBank1[incomingSet];
                2'd2: lookupDataReg <= dataBank2[incomingSet];
                default: lookupDataReg <= dataBank3[incomingSet];
            endcase
            if (incomingStoreBypass)
                lookupDataReg <= mergedStoreData;
        end

        if (arrayRefillWriteEnable) begin
            unique case (refillWordReg)
                2'd0: dataBank0[mshrSetReg] <= memoryResponseData_i;
                2'd1: dataBank1[mshrSetReg] <= memoryResponseData_i;
                2'd2: dataBank2[mshrSetReg] <= memoryResponseData_i;
                default: dataBank3[mshrSetReg] <= memoryResponseData_i;
            endcase
            if (refillCountReg == LAST_REFILL_COUNT)
                tagArray[mshrSetReg] <= mshrTagReg;
        end else if (arrayStoreWriteEnable) begin
            unique case (lookupWordReg)
                2'd0: dataBank0[lookupSetReg] <= mergedStoreData;
                2'd1: dataBank1[lookupSetReg] <= mergedStoreData;
                2'd2: dataBank2[lookupSetReg] <= mergedStoreData;
                default: dataBank3[lookupSetReg] <= mergedStoreData;
            endcase
        end
    end

    assign cacheStructurallyBusy = mshrValid ||
        (lookupStageValidReg && !lookupStageAdvance);
    assign idle_o = !mshrValid && (refillState == REFILL_IDLE) &&
                    !lookupStageValidReg;

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            lookupStageValidReg <= 1'b0;
            lookupWriteReg <= 1'b0;
            lookupAddressReg <= '0;
            lookupWriteDataReg <= '0;
            lookupAccessReg <= MEM_WORD;
            lookupIdReg <= '0;
            lookupSetReg <= '0;
            lookupRequestTagReg <= '0;
            lookupWordReg <= '0;
            lookupMmioReg <= 1'b0;
            lookupMmioReadSentReg <= 1'b0;
            lookupLineValidReg <= 1'b0;

            refillState <= REFILL_IDLE;
            mshrValid <= 1'b0;
            mshrAddressReg <= '0;
            mshrAccessReg <= MEM_WORD;
            mshrIdReg <= '0;
            mshrSetReg <= '0;
            mshrTagReg <= '0;
            refillWordReg <= '0;
            refillCountReg <= '0;
            criticalReturnedReg <= 1'b0;

            perfRequestCount_o <= '0;
            perfLoadHitCount_o <= '0;
            perfLoadMissCount_o <= '0;
            perfStoreHitCount_o <= '0;
            perfStoreMissCount_o <= '0;
            perfBusyCycles_o <= '0;
            perfRefillLineCount_o <= '0;
            perfRefillCycles_o <= '0;
            perfMmioRequestCount_o <= '0;
            perfRequestBackpressureCycles_o <= '0;

            for (resetSet = 0; resetSet < SET_COUNT; resetSet = resetSet + 1)
                validArray[resetSet] <= 1'b0;
        end else begin
            if (lookupStageAdvance) begin
                lookupStageValidReg <= 1'b0;
                lookupMmioReadSentReg <= 1'b0;
            end

            if (lookupMmioLoad && !lookupMmioReadSentReg &&
                lookupMmioRequestFire)
                lookupMmioReadSentReg <= 1'b1;

            if (requestFire) begin
                lookupStageValidReg <= 1'b1;
                lookupWriteReg <= requestWrite_i;
                lookupAddressReg <= requestAddress_i;
                lookupWriteDataReg <= requestWriteData_i;
                lookupAccessReg <= requestAccess_i;
                lookupIdReg <= requestId_i;
                lookupSetReg <= incomingSet;
                lookupRequestTagReg <= incomingTag;
                lookupWordReg <= incomingWord;
                lookupMmioReg <= incomingMmio;
                lookupMmioReadSentReg <= 1'b0;
                if (!incomingMmio)
                    lookupLineValidReg <= validArray[incomingSet];
            end

            if (lookupMissAllocate) begin
                mshrValid <= 1'b1;
                mshrAddressReg <= lookupAddressReg;
                mshrAccessReg <= lookupAccessReg;
                mshrIdReg <= lookupIdReg;
                mshrSetReg <= lookupSetReg;
                mshrTagReg <= lookupRequestTagReg;
                refillWordReg <= lookupWordReg;
                refillCountReg <= '0;
                criticalReturnedReg <= 1'b0;
                refillState <= REFILL_REQUEST;
                // The old direct-mapped line is no longer readable once its
                // first data bank starts being overwritten.
                validArray[lookupSetReg] <= 1'b0;
            end

            unique case (refillState)
                REFILL_REQUEST: begin
                    if (memoryRequestFire)
                        refillState <= REFILL_RESPONSE;
                end

                REFILL_RESPONSE: begin
                    if (memoryResponseFire) begin
                        if (!criticalReturnedReg)
                            criticalReturnedReg <= 1'b1;

                        if (refillCountReg == LAST_REFILL_COUNT) begin
                            validArray[mshrSetReg] <= 1'b1;
                            refillState <= REFILL_IDLE;
                            mshrValid <= 1'b0;
                        end else begin
                            refillCountReg <= refillCountReg + 1'b1;
                            refillWordReg <= refillWordReg + 1'b1;
                            if (memoryRequestFire)
                                refillState <= REFILL_RESPONSE;
                            else
                                refillState <= REFILL_REQUEST;
                        end
                    end
                end

                default: begin
                end
            endcase

            if (requestFire) begin
                perfRequestCount_o <= perfRequestCount_o + 1'b1;
                if (incomingMmio)
                    perfMmioRequestCount_o <=
                        perfMmioRequestCount_o + 1'b1;
            end
            if (lookupResponseFire && lookupLoadHitResponseValid)
                perfLoadHitCount_o <= perfLoadHitCount_o + 1'b1;
            if (lookupMissAllocate) begin
                perfLoadMissCount_o <= perfLoadMissCount_o + 1'b1;
                perfRefillLineCount_o <= perfRefillLineCount_o + 1'b1;
            end
            if (lookupStoreFire) begin
                if (lookupHit)
                    perfStoreHitCount_o <= perfStoreHitCount_o + 1'b1;
                else
                    perfStoreMissCount_o <= perfStoreMissCount_o + 1'b1;
            end
            if (cacheStructurallyBusy)
                perfBusyCycles_o <= perfBusyCycles_o + 1'b1;
            if (mshrValid)
                perfRefillCycles_o <= perfRefillCycles_o + 1'b1;
            if (requestValid_i && !requestReady_o)
                perfRequestBackpressureCycles_o <=
                    perfRequestBackpressureCycles_o + 1'b1;
        end
    end

    initial begin
        if (DATA_W != 32)
            $error("DataCache currently requires a 32-bit data word");
        if ((SET_COUNT < 2) || ((SET_COUNT & (SET_COUNT-1)) != 0))
            $error("DataCache SET_COUNT must be a power of two");
        if (WORDS_PER_LINE != 4)
            $error("DataCache currently requires four words per cache line");
    end

endmodule
