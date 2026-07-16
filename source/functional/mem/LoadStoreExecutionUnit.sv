module LoadStoreExecutionUnit
    import TypesPkg::*;
(
    input  logic clk,
    input  logic rst,
    input  logic flush_i,

    input  logic issueValid_i,
    input  renamed_uop_t issueUop_i,
    input  word_t sourceA_i,
    input  word_t sourceB_i,

    input  logic orderingReady_i,
    input  logic forwardValid_i,
    input  word_t forwardData_i,
    input  logic memoryPortReady_i,
    input  word_t memoryReadData_i,
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
    output logic isStore_o,
    output word_t address_o,
    output word_t storeData_o,
    output mem_access_t memoryAccess_o,
    output lsq_tag_t lsqTag_o,

    input  logic completionReady_i
);

    word_t address;
    logic completionValid;
    rob_tag_t completionRobTag;
    logic writebackValid;
    phys_reg_addr_t writebackPhys;
    word_t writebackData;
    logic completionSlotReady;
    logic selectedIsLoad;
    logic selectedIsStore;
    logic addressMisaligned;
    logic completionException;
    logic [5:0] completionCause;
    word_t completionValue;

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

    // A forwarded load does not consume the external memory port, so it may
    // execute in the same cycle that an older store commits to memory.
    assign issueReady_o = completionSlotReady && orderingReady_i &&
                          (!selectedIsLoad || forwardValid_i || memoryPortReady_i);
    assign executeValid_o = issueValid_i && issueReady_o && !addressMisaligned &&
                            (selectedIsLoad || selectedIsStore);
    assign loadReadValid_o = executeValid_o && selectedIsLoad && !forwardValid_i;
    assign isStore_o = selectedIsStore;
    assign address_o = address;
    assign storeData_o = sourceB_i;
    assign memoryAccess_o = issueUop_i.memCtr;
    assign lsqTag_o = issueUop_i.lsqTag;

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
            writebackValid <= 1'b0;
            writebackPhys <= '0;
            writebackData <= '0;
            completionException <= 1'b0;
            completionCause <= '0;
            completionValue <= '0;
        end else if (flush_i) begin
            completionValid <= 1'b0;
            writebackValid <= 1'b0;
            completionException <= 1'b0;
        end else if (completionSlotReady) begin
            completionValid <= executeValid_o;
            completionRobTag <= issueUop_i.robTag;
            completionException <= issueUop_i.decodeException || addressMisaligned;
            completionCause <= issueUop_i.decodeException ?
                issueUop_i.decodeExceptionCause :
                (selectedIsStore ? EXC_STORE_ADDR_MISALIGNED : EXC_LOAD_ADDR_MISALIGNED);
            completionValue <= issueUop_i.decodeException ?
                issueUop_i.exceptionValue : address;
            writebackValid <= executeValid_o && selectedIsLoad &&
                              issueUop_i.registerWriteEnable &&
                              (issueUop_i.destPhys != '0);
            writebackPhys <= issueUop_i.destPhys;
            writebackData <= forwardValid_i ? forwardData_i : memoryReadData_i;
        end
    end

endmodule
