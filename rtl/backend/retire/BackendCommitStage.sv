module BackendCommitStage
    import TypesPkg::*;
#(
    parameter word_t MMIO_BASE_ADDR = UART_TX_ADDR,
    parameter word_t MMIO_LAST_ADDR = TOHOST_ADDR + 32'd7
)
(
    input logic recoveryValid_i,
    input logic branchTrainReady_i,
    input logic storeReady_i,
    input logic mmioStoreReady_i,
    input logic [1:0] robCommitValid_i,
    input rob_entry_t robCommitEntry_i [2],
    input lsq_entry_t lsqHeadEntry_i [2],
    input lsq_tag_t lsqHeadTag_i [2],
    output logic [1:0] robCommitReady_o,
    output logic [1:0] robRetireValid_o,
    output logic [1:0] lsqRetireCount_o,
    output logic storeValid_o,
    output logic storeMmio_o,
    output logic storeBlocked_o,
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
    logic candidatePrefix;
    logic candidateLaneCanCommit;
    integer memoryRetireOffset;
    integer candidateMemoryOffset;
    integer storeCommitCount;
    integer candidateStoreCount;
    integer branchCommitCount;
    integer candidateBranchCount;
    integer lane;
    logic selectedStoreIsMmio;

    function automatic logic addressIsMmio(input word_t address);
        addressIsMmio = (address >= MMIO_BASE_ADDR) &&
                        (address <= MMIO_LAST_ADDR);
    endfunction

    always_comb begin
        robCommitReady_o = '0;
        robRetireValid_o = '0;
        lsqRetireCount_o = '0;
        storeValid_o = 1'b0;
        storeMmio_o = 1'b0;
        storeBlocked_o = 1'b0;
        storeAddress_o = '0;
        storeData_o = '0;
        storeAccess_o = MEM_WORD;
        memoryRetireOffset = 0;
        storeCommitCount = 0;
        branchCommitCount = 0;
        selectedStoreIsMmio = 1'b0;
        retirePrefix = 1'b1;
        trapValid_o = robCommitValid_i[0] && robCommitEntry_i[0].exception;
        trapPc_o = robCommitEntry_i[0].pc;
        trapCause_o = robCommitEntry_i[0].exceptionCause;
        trapValue_o = robCommitEntry_i[0].exceptionValue;
        mretCommit_o = 1'b0;

        // First pass: form the Store Ready/Valid request without consulting
        // either Store destination's Ready.  This avoids a combinational loop
        // through the cache request decoder while still allowing a lane-1
        // Store when lane 0 can retire independently.
        candidatePrefix = 1'b1;
        candidateMemoryOffset = 0;
        candidateStoreCount = 0;
        candidateBranchCount = 0;
        for (lane = 0; lane < 2; lane = lane + 1) begin
            candidateLaneCanCommit = !recoveryValid_i && candidatePrefix &&
                robCommitValid_i[lane] && !robCommitEntry_i[lane].exception;
            if (candidateLaneCanCommit && robCommitEntry_i[lane].isMemory) begin
                candidateLaneCanCommit =
                    lsqHeadEntry_i[candidateMemoryOffset].valid &&
                    (lsqHeadTag_i[candidateMemoryOffset] ==
                     robCommitEntry_i[lane].lsqTag);
                if (candidateLaneCanCommit && robCommitEntry_i[lane].isStore)
                    candidateLaneCanCommit =
                        lsqHeadEntry_i[candidateMemoryOffset].addressReady &&
                        lsqHeadEntry_i[candidateMemoryOffset].dataReady &&
                        (candidateStoreCount == 0);
            end
            if (candidateLaneCanCommit && robCommitEntry_i[lane].isBranch &&
                (candidateBranchCount != 0))
                candidateLaneCanCommit = 1'b0;
            if (candidateLaneCanCommit && robCommitEntry_i[lane].isBranch &&
                !branchTrainReady_i)
                candidateLaneCanCommit = 1'b0;

            if (candidateLaneCanCommit) begin
                if (robCommitEntry_i[lane].isBranch)
                    candidateBranchCount = candidateBranchCount + 1;
                if (robCommitEntry_i[lane].isMemory) begin
                    if (robCommitEntry_i[lane].isStore) begin
                        candidateStoreCount = candidateStoreCount + 1;
                        storeValid_o = 1'b1;
                        storeMmio_o = addressIsMmio(
                            lsqHeadEntry_i[candidateMemoryOffset].address);
                        storeAddress_o =
                            lsqHeadEntry_i[candidateMemoryOffset].address;
                        storeData_o =
                            lsqHeadEntry_i[candidateMemoryOffset].storeData;
                        storeAccess_o =
                            lsqHeadEntry_i[candidateMemoryOffset].memCtr;
                    end
                    candidateMemoryOffset = candidateMemoryOffset + 1;
                end
            end else begin
                candidatePrefix = 1'b0;
            end
        end

        for (lane = 0; lane < 2; lane = lane + 1) begin
            laneCanCommit = !recoveryValid_i && retirePrefix &&
                robCommitValid_i[lane] && !robCommitEntry_i[lane].exception;
            if (laneCanCommit && robCommitEntry_i[lane].isMemory) begin
                laneCanCommit = lsqHeadEntry_i[memoryRetireOffset].valid &&
                    (lsqHeadTag_i[memoryRetireOffset] == robCommitEntry_i[lane].lsqTag);
                if (laneCanCommit && robCommitEntry_i[lane].isStore) begin
                    laneCanCommit = lsqHeadEntry_i[memoryRetireOffset].addressReady &&
                        lsqHeadEntry_i[memoryRetireOffset].dataReady &&
                        (storeCommitCount == 0);
                    if (laneCanCommit) begin
                        selectedStoreIsMmio = addressIsMmio(
                            lsqHeadEntry_i[memoryRetireOffset].address);
                        if (selectedStoreIsMmio) begin
                            if (!mmioStoreReady_i)
                                storeBlocked_o = 1'b1;
                            laneCanCommit = mmioStoreReady_i;
                        end else begin
                            if (!storeReady_i)
                                storeBlocked_o = 1'b1;
                            laneCanCommit = storeReady_i;
                        end
                    end
                end
            end
            if (laneCanCommit && robCommitEntry_i[lane].isBranch &&
                (branchCommitCount != 0))
                laneCanCommit = 1'b0;
            if (laneCanCommit && robCommitEntry_i[lane].isBranch &&
                !branchTrainReady_i)
                laneCanCommit = 1'b0;

            robCommitReady_o[lane] = laneCanCommit;
            if (laneCanCommit) begin
                robRetireValid_o[lane] = 1'b1;
                if (robCommitEntry_i[lane].isBranch)
                    branchCommitCount = branchCommitCount + 1;
                if (robCommitEntry_i[lane].mret) mretCommit_o = 1'b1;
                if (robCommitEntry_i[lane].isMemory) begin
                    if (robCommitEntry_i[lane].isStore) begin
                        storeCommitCount = storeCommitCount + 1;
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
