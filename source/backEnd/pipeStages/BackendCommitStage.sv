module BackendCommitStage
    import TypesPkg::*;
(
    input logic recoveryValid_i,
    input logic [1:0] robCommitValid_i,
    input rob_entry_t robCommitEntry_i [2],
    input lsq_entry_t lsqHeadEntry_i [2],
    input lsq_tag_t lsqHeadTag_i [2],
    output logic [1:0] robCommitReady_o,
    output logic [1:0] robRetireValid_o,
    output logic [1:0] lsqRetireCount_o,
    output logic storeValid_o,
    output word_t storeAddress_o,
    output word_t storeData_o,
    output mem_access_t storeAccess_o,
    output logic trapValid_o,
    output instruction_addr_t trapPc_o,
    output logic [5:0] trapCause_o,
    output word_t trapValue_o,
    output logic mretCommit_o
);
    logic retirePrefix;
    logic laneCanCommit;
    integer memoryRetireOffset;
    integer storeCommitCount;
    integer lane;

    always_comb begin
        robCommitReady_o = '0;
        robRetireValid_o = '0;
        lsqRetireCount_o = '0;
        storeValid_o = 1'b0;
        storeAddress_o = '0;
        storeData_o = '0;
        storeAccess_o = MEM_WORD;
        memoryRetireOffset = 0;
        storeCommitCount = 0;
        retirePrefix = 1'b1;
        trapValid_o = robCommitValid_i[0] && robCommitEntry_i[0].exception;
        trapPc_o = robCommitEntry_i[0].pc;
        trapCause_o = robCommitEntry_i[0].exceptionCause;
        trapValue_o = robCommitEntry_i[0].exceptionValue;
        mretCommit_o = 1'b0;

        for (lane = 0; lane < 2; lane = lane + 1) begin
            laneCanCommit = !recoveryValid_i && retirePrefix &&
                robCommitValid_i[lane] && !robCommitEntry_i[lane].exception;
            if (laneCanCommit && robCommitEntry_i[lane].isMemory) begin
                laneCanCommit = lsqHeadEntry_i[memoryRetireOffset].valid &&
                    (lsqHeadTag_i[memoryRetireOffset] == robCommitEntry_i[lane].lsqTag);
                if (laneCanCommit && robCommitEntry_i[lane].isStore)
                    laneCanCommit = lsqHeadEntry_i[memoryRetireOffset].addressReady &&
                        lsqHeadEntry_i[memoryRetireOffset].dataReady &&
                        (storeCommitCount == 0);
            end

            robCommitReady_o[lane] = laneCanCommit;
            if (laneCanCommit) begin
                robRetireValid_o[lane] = 1'b1;
                if (robCommitEntry_i[lane].mret) mretCommit_o = 1'b1;
                if (robCommitEntry_i[lane].isMemory) begin
                    if (robCommitEntry_i[lane].isStore) begin
                        storeCommitCount = storeCommitCount + 1;
                        storeValid_o = 1'b1;
                        storeAddress_o = lsqHeadEntry_i[memoryRetireOffset].address;
                        storeData_o = lsqHeadEntry_i[memoryRetireOffset].storeData;
                        storeAccess_o = lsqHeadEntry_i[memoryRetireOffset].memCtr;
                    end
                    memoryRetireOffset = memoryRetireOffset + 1;
                end
            end else begin
                retirePrefix = 1'b0;
            end
        end
        lsqRetireCount_o = memoryRetireOffset[1:0];
    end
endmodule
