module LoadStoreExecutionUnit
    import TypesPkg::*;
(
    input  logic clk,
    input  logic rst,
    input  logic flush_i,
    input  logic recoverValid_i,
    input  logic [ROB_ENTRY_NUM-1:0] recoverYoungerMask_i,

    input  logic issueValid_i,
    input  renamed_uop_t issueUop_i,
    input  word_t sourceA_i,
    input  word_t sourceB_i,

    input  logic orderingReady_i,
    input  logic forwardValid_i,
    input  word_t forwardData_i,

    // Blocking cache request/response channel.  A non-forwarded Load leaves
    // the IQ only when its request is accepted, then retains its ROB/PRF
    // metadata here until the synchronous cache response arrives.
    input  logic memoryRequestReady_i,
    input  logic memoryResponseValid_i,
    input  rob_tag_t memoryResponseId_i,
    input  word_t memoryResponseData_i,
    output logic memoryResponseReady_o,
    output logic busy_o,

    output logic issueReady_o,

    output logic completionValid_o,
    output rob_tag_t completionRobTag_o,
    output logic completionException_o,
    output logic [5:0] completionCause_o,
    output word_t completionValue_o,
    output logic writebackValid_o,
    output phys_reg_addr_t writebackPhys_o,
    output word_t writebackData_o,

    output logic executeValid_o,
    output logic loadReadValid_o,
    output rob_tag_t loadRequestId_o,
    output logic isStore_o,
    output word_t address_o,
    output logic storeDataValid_o,
    output word_t storeData_o,
    output mem_access_t memoryAccess_o,
    output lsq_tag_t lsqTag_o,

    input  logic completionReady_i
);

    word_t address;
    logic selectedIsLoad;
    logic selectedIsStore;
    logic addressMisaligned;
    logic completionSlotReady;
    logic issueAllowed;
    logic baseIssueReady;
    logic normalCacheLoad;
    logic issueFire;

    logic completionValid;
    rob_tag_t completionRobTag;
    logic completionException;
    logic [5:0] completionCause;
    word_t completionValue;
    logic writebackValid;
    phys_reg_addr_t writebackPhys;
    word_t writebackData;

    logic [ROB_ENTRY_NUM-1:0] pendingValid;
    logic [ROB_ENTRY_NUM-1:0] pendingKilled;
    phys_reg_addr_t pendingDestPhys [ROB_ENTRY_NUM];
    logic pendingRegisterWrite [ROB_ENTRY_NUM];
    word_t pendingAddress [ROB_ENTRY_NUM];
    logic responsePending;
    logic responseKilled;
    logic responseCompletes;
    logic responseFire;
    integer pendingIndex;

    assign address = sourceA_i + issueUop_i.immediate;
    assign selectedIsLoad = issueUop_i.fuClass == FU_MEMORY &&
                            !issueUop_i.dataWriteEnable;
    assign selectedIsStore = issueUop_i.fuClass == FU_MEMORY &&
                             issueUop_i.dataWriteEnable;

    always_comb begin
        unique case (issueUop_i.memCtr)
            MEM_HALF, MEM_HALF_U: addressMisaligned = address[0];
            MEM_WORD: addressMisaligned = |address[1:0];
            default: addressMisaligned = 1'b0;
        endcase
    end

    assign completionSlotReady = !completionValid || completionReady_i;
    assign issueAllowed = !recoverValid_i ||
        !recoverYoungerMask_i[issueUop_i.robTag];
    assign normalCacheLoad = selectedIsLoad && !forwardValid_i &&
        !addressMisaligned && !issueUop_i.decodeException;
    assign responsePending = pendingValid[memoryResponseId_i];
    assign responseKilled = pendingKilled[memoryResponseId_i] || flush_i ||
        (recoverValid_i && recoverYoungerMask_i[memoryResponseId_i]);
    assign responseCompletes = memoryResponseValid_i && responsePending &&
        !responseKilled;
    assign memoryResponseReady_o = responsePending &&
        (responseKilled || completionSlotReady);
    assign responseFire = memoryResponseValid_i && memoryResponseReady_o;

    assign baseIssueReady = orderingReady_i && issueAllowed && !flush_i;

    // Valid is independent of Ready on the cache channel.  The IQ removes the
    // Load only when issueReady_o observes the corresponding request Ready.
    assign loadReadValid_o = issueValid_i && baseIssueReady && normalCacheLoad &&
        !pendingValid[issueUop_i.robTag];
    assign issueReady_o = baseIssueReady &&
        (normalCacheLoad ?
            (!pendingValid[issueUop_i.robTag] && memoryRequestReady_i) :
            (completionSlotReady && !responseCompletes));
    assign issueFire = issueValid_i && issueReady_o;

    // Address/data discovery updates the LSQ when the uop really issues.  A
    // misaligned access instead completes with a precise exception and never
    // touches either the cache or the LSQ address/data ports.
    assign executeValid_o = issueFire && !addressMisaligned &&
        !issueUop_i.decodeException && (selectedIsLoad || selectedIsStore);
    assign loadRequestId_o = issueUop_i.robTag;
    assign isStore_o = selectedIsStore;
    assign address_o = address;
    assign storeDataValid_o = executeValid_o && selectedIsStore &&
        issueUop_i.src2Ready;
    assign storeData_o = sourceB_i;
    assign memoryAccess_o = issueUop_i.memCtr;
    assign lsqTag_o = issueUop_i.lsqTag;

    assign busy_o = |pendingValid;

    assign completionValid_o = completionValid;
    assign completionRobTag_o = completionRobTag;
    assign completionException_o = completionException;
    assign completionCause_o = completionCause;
    assign completionValue_o = completionValue;
    assign writebackValid_o = writebackValid;
    assign writebackPhys_o = writebackPhys;
    assign writebackData_o = writebackData;

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            completionValid <= 1'b0;
            completionRobTag <= '0;
            completionException <= 1'b0;
            completionCause <= '0;
            completionValue <= '0;
            writebackValid <= 1'b0;
            writebackPhys <= '0;
            writebackData <= '0;
            pendingValid <= '0;
            pendingKilled <= '0;
            for (pendingIndex = 0; pendingIndex < ROB_ENTRY_NUM;
                 pendingIndex = pendingIndex + 1) begin
                pendingDestPhys[pendingIndex] <= '0;
                pendingRegisterWrite[pendingIndex] <= 1'b0;
                pendingAddress[pendingIndex] <= '0;
            end
        end else begin
            if (completionSlotReady) begin
                completionValid <= 1'b0;
                writebackValid <= 1'b0;
                completionException <= 1'b0;
            end

            // Accepted cache requests cannot be withdrawn. Recovery marks all
            // affected entries as killed; their tagged responses are drained
            // without producing ROB/PRF side effects.
            for (pendingIndex = 0; pendingIndex < ROB_ENTRY_NUM;
                 pendingIndex = pendingIndex + 1) begin
                if (pendingValid[pendingIndex] &&
                    (flush_i || (recoverValid_i &&
                     recoverYoungerMask_i[pendingIndex])))
                    pendingKilled[pendingIndex] <= 1'b1;
            end

            if (responseFire) begin
                if (!responseKilled) begin
                    completionValid <= 1'b1;
                    completionRobTag <= memoryResponseId_i;
                    completionException <= 1'b0;
                    completionCause <= '0;
                    completionValue <= pendingAddress[memoryResponseId_i];
                    writebackValid <=
                        pendingRegisterWrite[memoryResponseId_i] &&
                        (pendingDestPhys[memoryResponseId_i] != '0);
                    writebackPhys <= pendingDestPhys[memoryResponseId_i];
                    writebackData <= memoryResponseData_i;
                end
                pendingValid[memoryResponseId_i] <= 1'b0;
                pendingKilled[memoryResponseId_i] <= 1'b0;
            end

            if (issueFire && !flush_i) begin
                if (normalCacheLoad) begin
                    pendingValid[issueUop_i.robTag] <= 1'b1;
                    pendingKilled[issueUop_i.robTag] <= 1'b0;
                    pendingDestPhys[issueUop_i.robTag] <= issueUop_i.destPhys;
                    pendingRegisterWrite[issueUop_i.robTag] <=
                        issueUop_i.registerWriteEnable;
                    pendingAddress[issueUop_i.robTag] <= address;
                end else begin
                    // Stores, forwarded Loads, decode exceptions, and
                    // misaligned accesses all complete locally in one cycle.
                    completionValid <= selectedIsLoad || selectedIsStore ||
                                       issueUop_i.decodeException;
                    completionRobTag <= issueUop_i.robTag;
                    completionException <= issueUop_i.decodeException ||
                                           addressMisaligned;
                    completionCause <= issueUop_i.decodeException ?
                        issueUop_i.decodeExceptionCause :
                        (selectedIsStore ? EXC_STORE_ADDR_MISALIGNED :
                                           EXC_LOAD_ADDR_MISALIGNED);
                    completionValue <= issueUop_i.decodeException ?
                        issueUop_i.exceptionValue : address;
                    writebackValid <= selectedIsLoad && forwardValid_i &&
                        !addressMisaligned && !issueUop_i.decodeException &&
                        issueUop_i.registerWriteEnable &&
                        (issueUop_i.destPhys != '0);
                    writebackPhys <= issueUop_i.destPhys;
                    writebackData <= forwardData_i;
                end
            end
        end
    end

endmodule
