`timescale 1ns/1ps

module tage_tb;
    import TypesPkg::*;

    localparam int TEST_TABLE_ENTRIES = 8;
    localparam int TEST_INDEX_WIDTH = $clog2(TEST_TABLE_ENTRIES);
    localparam int TEST_TAG_WIDTH = 4;
    localparam int FOLDER_HISTORY_LENGTH = 8;
    localparam int FOLDER_WIDTH = 3;
    localparam int GENERATION_COUNT = 1 << TAGE_GENERATION_WIDTH;
    localparam tage_generation_t GENERATION_MAX = '1;
    localparam instruction_addr_t TAG_PC_A = 32'h0000_0100;
    localparam instruction_addr_t TAG_PC_B = 32'h0000_0800;
    localparam instruction_addr_t RECOVERY_PC = 32'h0000_0220;
    localparam tage_history_t RECOVERY_HISTORY =
        64'h0000_0000_0000_1234;
    localparam tage_path_history_t RECOVERY_PATH = 16'h1357;

    logic clk = 1'b0;
    logic rst = 1'b0;
    logic flush;

    instruction_addr_t queryPc;
    logic fallbackPrediction;
    tage_meta_t queryMeta;
    instruction_addr_t queryPc1;
    logic fallbackPrediction1;
    logic query0Conditional;
    logic query0Control;
    logic query0PathTaken;
    tage_meta_t queryMeta1;

    logic speculateValid;
    logic speculateTaken;
    logic speculateValid1;
    logic speculateTaken1;
    logic speculateControlValid;
    logic speculateControlValid1;

    logic updateValid;
    logic updateIsConditional;
    instruction_addr_t updatePc;
    logic updateTaken;
    tage_meta_t updateMeta;
    logic updateReady;

    logic recoverValid;
    instruction_addr_t recoverPc;
    logic recoverIsConditional;
    logic recoverTaken;
    rob_tag_t recoverRobTag;
    logic [1:0] checkpointAllocValid;
    rob_tag_t checkpointAllocTag [2];
    tage_history_t checkpointAllocHistory [2];
    tage_path_history_t checkpointAllocPathHistory [2];

    // Standalone folded-history checker.
    tage_history_t folderGlobalHistory;
    logic folderQuery0Conditional;
    logic folderQuery0Taken;
    logic [FOLDER_WIDTH-1:0] folderQueryFold;
    logic [FOLDER_WIDTH-1:0] folderQueryFold1;
    logic folderSpeculateValid;
    logic folderSpeculateTaken;
    logic folderSpeculateValid1;
    logic folderSpeculateTaken1;
    logic folderRestoreValid;
    tage_history_t folderRestoreHistory;
    tage_history_t folderReferenceHistory;
    logic [7:0] folderLfsr;
    logic [10:0] folderExpectedWide;
    instruction_addr_t productionHashPc;
    tage_history_t productionHashHistory;
    tage_path_history_t productionHashPathHistory;
    logic [TAGE_TABLE_NUM-1:0] productionHashMatch;
    logic [63:0] hashHistoryLfsr;
    logic [15:0] hashPathLfsr;

    // Standalone Hash + tagged-table checker.
    instruction_addr_t tableQueryPc;
    tage_history_t tableQueryHistory;
    tage_path_history_t tableQueryPathHistory;
    logic [TEST_INDEX_WIDTH-1:0] tableQueryIndexFold;
    logic [TEST_TAG_WIDTH-1:0] tableQueryTagFoldA;
    logic [TEST_TAG_WIDTH-2:0] tableQueryTagFoldB;
    logic [TEST_INDEX_WIDTH-1:0] tableQueryIndex;
    logic [TEST_TAG_WIDTH-1:0] tableQueryTag;
    logic tableQueryHit;
    logic tableQueryPrediction;
    logic [2:0] tableQueryCounter;
    logic [1:0] tableQueryUseful;
    tage_generation_t tableQueryGeneration;
    logic tableQueryBank;

    instruction_addr_t tableQueryPc1;
    tage_history_t tableQueryHistory1;
    tage_path_history_t tableQueryPathHistory1;
    logic [TEST_INDEX_WIDTH-1:0] tableQueryIndexFold1;
    logic [TEST_TAG_WIDTH-1:0] tableQueryTagFoldA1;
    logic [TEST_TAG_WIDTH-2:0] tableQueryTagFoldB1;
    logic [TEST_INDEX_WIDTH-1:0] tableQueryIndex1;
    logic [TEST_TAG_WIDTH-1:0] tableQueryTag1;
    logic tableQueryHit1;
    logic tableQueryPrediction1;
    logic [2:0] tableQueryCounter1;
    logic [1:0] tableQueryUseful1;
    tage_generation_t tableQueryGeneration1;
    logic tableQueryBank1;

    instruction_addr_t tableUpdatePc;
    tage_history_t tableUpdateHistory;
    tage_path_history_t tableUpdatePathHistory;
    logic [TEST_INDEX_WIDTH-1:0] tableUpdateIndex;
    logic [TEST_TAG_WIDTH-1:0] tableUpdateTag;
    logic tableUpdateMatch;
    logic tableUpdateReplaceable;
    logic [1:0] tableUpdateUseful;
    tage_generation_t tableUpdateGeneration;
    logic tableUpdateBank;
    logic tableProviderUpdateValid;
    logic tableUpdateTaken;
    logic tableProviderUsefulIncrement;
    logic tableProviderUsefulDecrement;
    logic tableAllocateValid;
    logic tableReplacementUsefulDecrement;
    logic tableAgeValid;
    logic [TEST_INDEX_WIDTH-1:0] tableAgeIndex;

    logic [10:0] tableQueryFoldWide;
    logic [10:0] tableQueryFoldWide1;
    logic [TEST_INDEX_WIDTH-1:0] allocatedIndex;
    logic [TEST_TAG_WIDTH-1:0] allocatedTag;
    tage_generation_t allocatedGeneration;
    tage_generation_t replacementGeneration;
    tage_generation_t staleGeneration;
    tage_path_history_t aliasPath;
    tage_history_t aliasHistory;
    tage_path_history_t otherBankPath;
    logic [TEST_INDEX_WIDTH-1:0] otherBankIndex;
    logic [TEST_TAG_WIDTH-1:0] otherBankTag;
    tage_generation_t otherBankGeneration;
    logic pathAliasFound;
    logic historyAliasFound;
    logic otherBankFound;
    tage_meta_t savedMeta;
    tage_path_history_t expectedPath;
    tage_history_t committedHistoryReference;
    tage_path_history_t committedPathReference;
    logic [TAGE_TABLE_NUM-1:0] lastAllocationMask;
    logic [TAGE_TABLE_NUM-1:0] lastEligibleMask;
    logic [TAGE_TABLE_NUM-1:0] lastFreeMask;
    logic [TAGE_TABLE_NUM-1:0] lastPressureMask;
    logic [TAGE_TABLE_NUM-1:0] lastMinimumUsefulMask;
    logic [7:0] lastAllocationLfsr;
    logic lastAllocationRequest;
    logic [3:0] alternateGroupBefore;
    logic [3:0] otherAlternateGroupBefore;
    integer searchValue;
    integer randomStep;
    integer previousProvider;

    always #5 clk = ~clk;

    // Hash bit zero is the physical bank selector; the remaining bits select
    // the row within that bank.  Keep the standalone table wired exactly like
    // the production predictor instead of choosing a bank independently.
    assign tableQueryBank = tableQueryIndex[0];
    assign tableQueryBank1 = tableQueryIndex1[0];
    assign tableUpdateBank = tableUpdateIndex[0];

    function automatic logic [10:0] referenceFold(
        input tage_history_t history,
        input integer historyLength,
        input integer foldWidth
    );
        logic [10:0] result;
        integer bitIndex;
        begin
            result = '0;
            for (bitIndex = 0; bitIndex < historyLength;
                 bitIndex = bitIndex + 1)
                result[bitIndex % foldWidth] =
                    result[bitIndex % foldWidth] ^ history[bitIndex];
            referenceFold = result;
        end
    endfunction

    function automatic tage_path_history_t referenceAdvancePath(
        input tage_path_history_t history,
        input instruction_addr_t branchPc,
        input logic pathTaken
    );
        logic pathBit;
        begin
            pathBit = branchPc[2] ^ branchPc[5] ^ branchPc[9] ^
                      branchPc[13] ^ pathTaken;
            referenceAdvancePath = {
                history[TAGE_PATH_HISTORY_WIDTH-2:0], pathBit};
        end
    endfunction

    function automatic integer countTageMask(
        input logic [TAGE_TABLE_NUM-1:0] mask
    );
        integer bitIndex;
        begin
            countTageMask = 0;
            for (bitIndex = 0; bitIndex < TAGE_TABLE_NUM;
                 bitIndex = bitIndex + 1)
                if (mask[bitIndex])
                    countTageMask = countTageMask + 1;
        end
    endfunction

    always_comb begin
        tableQueryFoldWide = referenceFold(
            tableQueryHistory, 4, TEST_INDEX_WIDTH);
        tableQueryIndexFold =
            tableQueryFoldWide[TEST_INDEX_WIDTH-1:0];
        tableQueryFoldWide = referenceFold(
            tableQueryHistory, 4, TEST_TAG_WIDTH);
        tableQueryTagFoldA =
            tableQueryFoldWide[TEST_TAG_WIDTH-1:0];
        tableQueryFoldWide = referenceFold(
            tableQueryHistory, 4, TEST_TAG_WIDTH-1);
        tableQueryTagFoldB =
            tableQueryFoldWide[TEST_TAG_WIDTH-2:0];

        tableQueryFoldWide1 = referenceFold(
            tableQueryHistory1, 4, TEST_INDEX_WIDTH);
        tableQueryIndexFold1 =
            tableQueryFoldWide1[TEST_INDEX_WIDTH-1:0];
        tableQueryFoldWide1 = referenceFold(
            tableQueryHistory1, 4, TEST_TAG_WIDTH);
        tableQueryTagFoldA1 =
            tableQueryFoldWide1[TEST_TAG_WIDTH-1:0];
        tableQueryFoldWide1 = referenceFold(
            tableQueryHistory1, 4, TEST_TAG_WIDTH-1);
        tableQueryTagFoldB1 =
            tableQueryFoldWide1[TEST_TAG_WIDTH-2:0];
    end

    TagePredictor #(
        .TABLE_ENTRIES(TEST_TABLE_ENTRIES),
        .SC_ENABLE(1'b0)
    ) dut (
        .clk(clk), .rst(rst), .flush_i(flush),
        .queryPc_i(queryPc),
        .fallbackPrediction_i(fallbackPrediction),
        .queryMeta_o(queryMeta),
        .queryPc1_i(queryPc1),
        .fallbackPrediction1_i(fallbackPrediction1),
        .query0Conditional_i(query0Conditional),
        .query0Control_i(query0Control),
        .query0PathTaken_i(query0PathTaken),
        .queryMeta1_o(queryMeta1),
        .speculateValid_i(speculateValid),
        .speculateTaken_i(speculateTaken),
        .speculateValid1_i(speculateValid1),
        .speculateTaken1_i(speculateTaken1),
        .speculateControlValid_i(speculateControlValid),
        .speculateControlValid1_i(speculateControlValid1),
        .updateValid_i(updateValid),
        .updateIsConditional_i(updateIsConditional),
        .updatePc_i(updatePc), .updateTaken_i(updateTaken),
        .updateMeta_i(updateMeta),
        .updateReady_o(updateReady),
        .recoverValid_i(recoverValid), .recoverPc_i(recoverPc),
        .recoverIsConditional_i(recoverIsConditional),
        .recoverTaken_i(recoverTaken),
        .recoverRobTag_i(recoverRobTag),
        .checkpointAllocValid_i(checkpointAllocValid),
        .checkpointAllocTag_i(checkpointAllocTag),
        .checkpointAllocHistory_i(checkpointAllocHistory),
        .checkpointAllocPathHistory_i(checkpointAllocPathHistory)
    );

    TageFoldedHistory #(
        .HISTORY_LENGTH(FOLDER_HISTORY_LENGTH),
        .FOLD_WIDTH(FOLDER_WIDTH)
    ) folderDut (
        .clk(clk), .rst(rst),
        .globalHistory_i(folderGlobalHistory),
        .query0Conditional_i(folderQuery0Conditional),
        .query0Taken_i(folderQuery0Taken),
        .queryFold_o(folderQueryFold),
        .queryFold1_o(folderQueryFold1),
        .speculateValid_i(folderSpeculateValid),
        .speculateTaken_i(folderSpeculateTaken),
        .speculateValid1_i(folderSpeculateValid1),
        .speculateTaken1_i(folderSpeculateTaken1),
        .restoreValid_i(folderRestoreValid),
        .restoreHistory_i(folderRestoreHistory)
    );

    TageHash #(
        .ENTRIES(TEST_TABLE_ENTRIES),
        .HISTORY_LENGTH(4),
        .TAG_WIDTH(TEST_TAG_WIDTH),
        .TABLE_ID(0)
    ) tableHashDut (
        .queryPc_i(tableQueryPc),
        .queryIndexFold_i(tableQueryIndexFold),
        .queryTagFoldA_i(tableQueryTagFoldA),
        .queryTagFoldB_i(tableQueryTagFoldB),
        .queryPathHistory_i(tableQueryPathHistory),
        .queryIndex_o(tableQueryIndex), .queryTag_o(tableQueryTag),
        .queryPc1_i(tableQueryPc1),
        .queryIndexFold1_i(tableQueryIndexFold1),
        .queryTagFoldA1_i(tableQueryTagFoldA1),
        .queryTagFoldB1_i(tableQueryTagFoldB1),
        .queryPathHistory1_i(tableQueryPathHistory1),
        .queryIndex1_o(tableQueryIndex1), .queryTag1_o(tableQueryTag1),
        .updatePc_i(tableUpdatePc),
        .updateHistory_i(tableUpdateHistory),
        .updatePathHistory_i(tableUpdatePathHistory),
        .updateIndex_o(tableUpdateIndex), .updateTag_o(tableUpdateTag)
    );

    TageTable #(
        .ENTRIES(TEST_TABLE_ENTRIES),
        .TAG_WIDTH(TEST_TAG_WIDTH)
    ) tagTableDut (
        .clk(clk), .rst(rst),
        .queryIndex_i(tableQueryIndex), .queryTag_i(tableQueryTag),
        .queryBank_i(tableQueryBank),
        .queryHit_o(tableQueryHit),
        .queryPrediction_o(tableQueryPrediction),
        .queryCounter_o(tableQueryCounter),
        .queryUseful_o(tableQueryUseful),
        .queryGeneration_o(tableQueryGeneration),
        .queryIndex1_i(tableQueryIndex1), .queryTag1_i(tableQueryTag1),
        .queryBank1_i(tableQueryBank1),
        .queryHit1_o(tableQueryHit1),
        .queryPrediction1_o(tableQueryPrediction1),
        .queryCounter1_o(tableQueryCounter1),
        .queryUseful1_o(tableQueryUseful1),
        .queryGeneration1_o(tableQueryGeneration1),
        .updateIndex_i(tableUpdateIndex), .updateTag_i(tableUpdateTag),
        .updateBank_i(tableUpdateBank),
        .updateGeneration_i(tableUpdateGeneration),
        .updateMatch_o(tableUpdateMatch),
        .updateReplaceable_o(tableUpdateReplaceable),
        .updateUseful_o(tableUpdateUseful),
        .providerUpdateValid_i(tableProviderUpdateValid),
        .updateTaken_i(tableUpdateTaken),
        .providerUsefulIncrement_i(tableProviderUsefulIncrement),
        .providerUsefulDecrement_i(tableProviderUsefulDecrement),
        .allocateValid_i(tableAllocateValid),
        .replacementUsefulDecrement_i(tableReplacementUsefulDecrement),
        .ageValid_i(tableAgeValid), .ageIndex_i(tableAgeIndex)
    );

    // Exercise every production fold geometry and every production table Hash
    // in parallel with the compact directed smoke instances above.
    generate
        for (genvar productionTable = 0;
             productionTable < TAGE_TABLE_NUM;
             productionTable = productionTable + 1) begin : productionChecks
            localparam int PRODUCTION_HISTORY_LENGTH =
                (productionTable == 0) ? 4 :
                (productionTable == 1) ? 8 :
                (productionTable == 2) ? 16 :
                (productionTable == 3) ? 32 : 64;
            localparam int PRODUCTION_TAG_WIDTH =
                (productionTable == 0) ? 7 :
                (productionTable == 1) ? 8 :
                (productionTable == 2) ? 9 :
                (productionTable == 3) ? 10 : 11;

            TageFoldConfigurationChecker #(
                .HISTORY_LENGTH(PRODUCTION_HISTORY_LENGTH),
                .FOLD_WIDTH(8), .TABLE_ID(productionTable), .FOLD_KIND(0)
            ) indexFoldCheck (
                .clk(clk), .rst(rst),
                .globalHistory_i(folderGlobalHistory),
                .query0Conditional_i(folderQuery0Conditional),
                .query0Taken_i(folderQuery0Taken),
                .speculateValid_i(folderSpeculateValid),
                .speculateTaken_i(folderSpeculateTaken),
                .speculateValid1_i(folderSpeculateValid1),
                .speculateTaken1_i(folderSpeculateTaken1),
                .restoreValid_i(folderRestoreValid),
                .restoreHistory_i(folderRestoreHistory)
            );

            TageFoldConfigurationChecker #(
                .HISTORY_LENGTH(PRODUCTION_HISTORY_LENGTH),
                .FOLD_WIDTH(PRODUCTION_TAG_WIDTH),
                .TABLE_ID(productionTable), .FOLD_KIND(1)
            ) tagFoldACheck (
                .clk(clk), .rst(rst),
                .globalHistory_i(folderGlobalHistory),
                .query0Conditional_i(folderQuery0Conditional),
                .query0Taken_i(folderQuery0Taken),
                .speculateValid_i(folderSpeculateValid),
                .speculateTaken_i(folderSpeculateTaken),
                .speculateValid1_i(folderSpeculateValid1),
                .speculateTaken1_i(folderSpeculateTaken1),
                .restoreValid_i(folderRestoreValid),
                .restoreHistory_i(folderRestoreHistory)
            );

            TageFoldConfigurationChecker #(
                .HISTORY_LENGTH(PRODUCTION_HISTORY_LENGTH),
                .FOLD_WIDTH(PRODUCTION_TAG_WIDTH-1),
                .TABLE_ID(productionTable), .FOLD_KIND(2)
            ) tagFoldBCheck (
                .clk(clk), .rst(rst),
                .globalHistory_i(folderGlobalHistory),
                .query0Conditional_i(folderQuery0Conditional),
                .query0Taken_i(folderQuery0Taken),
                .speculateValid_i(folderSpeculateValid),
                .speculateTaken_i(folderSpeculateTaken),
                .speculateValid1_i(folderSpeculateValid1),
                .speculateTaken1_i(folderSpeculateTaken1),
                .restoreValid_i(folderRestoreValid),
                .restoreHistory_i(folderRestoreHistory)
            );

            TageHashConfigurationChecker #(
                .HISTORY_LENGTH(PRODUCTION_HISTORY_LENGTH),
                .TAG_WIDTH(PRODUCTION_TAG_WIDTH),
                .TABLE_ID(productionTable)
            ) hashCheck (
                .pc_i(productionHashPc),
                .history_i(productionHashHistory),
                .pathHistory_i(productionHashPathHistory),
                .match_o(productionHashMatch[productionTable])
            );
        end
    endgenerate

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    task automatic checkFolderState;
        logic [10:0] expectedFold;
        begin
            expectedFold = referenceFold(
                folderReferenceHistory,
                FOLDER_HISTORY_LENGTH,
                FOLDER_WIDTH);
            if (folderQueryFold !== expectedFold[FOLDER_WIDTH-1:0])
                $fatal(1, "incremental folded history diverged from reference");
        end
    endtask

    task automatic pushFolder(
        input logic valid0,
        input logic taken0,
        input logic valid1,
        input logic taken1
    );
        begin
            folderGlobalHistory = folderReferenceHistory;
            folderSpeculateValid = valid0;
            folderSpeculateTaken = taken0;
            folderSpeculateValid1 = valid1;
            folderSpeculateTaken1 = taken1;
            tick();
            folderSpeculateValid = 1'b0;
            folderSpeculateValid1 = 1'b0;
            if (valid0)
                folderReferenceHistory = {
                    folderReferenceHistory[TAGE_HISTORY_WIDTH-2:0], taken0};
            if (valid1)
                folderReferenceHistory = {
                    folderReferenceHistory[TAGE_HISTORY_WIDTH-2:0], taken1};
            folderGlobalHistory = folderReferenceHistory;
            #1;
            checkFolderState();
        end
    endtask

    task automatic train(
        input instruction_addr_t pc,
        input logic taken,
        input tage_meta_t meta
    );
        begin
            updateValid = 1'b1;
            updateIsConditional = 1'b1;
            updatePc = pc;
            updateTaken = taken;
            updateMeta = meta;
            #1;
            if (!updateReady)
                $fatal(1, "TAGE update queue unexpectedly backpressured train");
            // The retirement event advances committed history immediately and
            // enters the table-update FIFO.  The following cycle exposes it at
            // the queue head for allocation/provider policy and table writes.
            tick();
            updateValid = 1'b0;
            updateIsConditional = 1'b0;
            #1;
            lastAllocationMask = dut.tableAllocate;
            lastEligibleMask = dut.eligibleAllocation;
            lastFreeMask = dut.freeAllocation;
            lastPressureMask = dut.replacementUsefulDecrement;
            lastMinimumUsefulMask = dut.minimumUsefulAllocation;
            lastAllocationLfsr = dut.allocationLfsr;
            lastAllocationRequest = dut.allocationRequest;
            if ((lastAllocationMask & ~lastFreeMask) != '0)
                $fatal(1, "TAGE allocated a non-free candidate");
            if (countTageMask(lastAllocationMask) > 2)
                $fatal(1, "TAGE allocated more than two tables");
            if (countTageMask(lastPressureMask) > 1)
                $fatal(1, "TAGE pressure decremented multiple tables");
            if ((lastPressureMask & ~lastMinimumUsefulMask) != '0)
                $fatal(1, "TAGE pressure did not select minimum usefulness");
            if ((lastPressureMask & lastAllocationMask) != '0)
                $fatal(1, "TAGE allocated and pressure-decremented one table");
            tick();
            committedHistoryReference = {
                committedHistoryReference[TAGE_HISTORY_WIDTH-2:0], taken};
            committedPathReference = referenceAdvancePath(
                committedPathReference, pc, taken);
        end
    endtask

    initial begin
        queryPc = TAG_PC_A;
        flush = 1'b0;
        fallbackPrediction = 1'b0;
        queryPc1 = TAG_PC_B;
        fallbackPrediction1 = 1'b1;
        query0Conditional = 1'b0;
        query0Control = 1'b0;
        query0PathTaken = 1'b0;
        speculateValid = 1'b0;
        speculateTaken = 1'b0;
        speculateValid1 = 1'b0;
        speculateTaken1 = 1'b0;
        speculateControlValid = 1'b0;
        speculateControlValid1 = 1'b0;
        updateValid = 1'b0;
        updateIsConditional = 1'b0;
        updatePc = '0;
        updateTaken = 1'b0;
        updateMeta = '0;
        recoverValid = 1'b0;
        recoverPc = '0;
        recoverIsConditional = 1'b0;
        recoverTaken = 1'b0;
        recoverRobTag = '0;
        checkpointAllocValid = '0;
        checkpointAllocTag[0] = '0;
        checkpointAllocTag[1] = '0;
        checkpointAllocHistory[0] = '0;
        checkpointAllocHistory[1] = '0;
        checkpointAllocPathHistory[0] = '0;
        checkpointAllocPathHistory[1] = '0;

        folderGlobalHistory = '0;
        folderQuery0Conditional = 1'b0;
        folderQuery0Taken = 1'b0;
        folderSpeculateValid = 1'b0;
        folderSpeculateTaken = 1'b0;
        folderSpeculateValid1 = 1'b0;
        folderSpeculateTaken1 = 1'b0;
        folderRestoreValid = 1'b0;
        folderRestoreHistory = '0;
        folderReferenceHistory = '0;
        folderLfsr = 8'h5a;
        productionHashPc = 32'h0000_0140;
        productionHashHistory = 64'h0123_4567_89ab_cdef;
        productionHashPathHistory = 16'h5aa5;
        hashHistoryLfsr = 64'hd134_2543_de82_ef95;
        hashPathLfsr = 16'hb4d3;
        committedHistoryReference = '0;
        committedPathReference = '0;

        tableQueryPc = TAG_PC_A;
        tableQueryHistory = '0;
        tableQueryPathHistory = '0;
        tableQueryPc1 = TAG_PC_A;
        tableQueryHistory1 = '0;
        tableQueryPathHistory1 = '0;
        tableUpdatePc = TAG_PC_A;
        tableUpdateHistory = '0;
        tableUpdatePathHistory = '0;
        tableUpdateGeneration = '0;
        tableProviderUpdateValid = 1'b0;
        tableUpdateTaken = 1'b0;
        tableProviderUsefulIncrement = 1'b0;
        tableProviderUsefulDecrement = 1'b0;
        tableAllocateValid = 1'b0;
        tableReplacementUsefulDecrement = 1'b0;
        tableAgeValid = 1'b0;
        tableAgeIndex = '0;
        pathAliasFound = 1'b0;
        historyAliasFound = 1'b0;
        otherBankFound = 1'b0;

        tick();
        rst = 1'b1;
        #1;

        if (queryMeta.providerValid || queryMeta.finalPrediction != 1'b0 ||
            queryMeta.history != '0 || queryMeta.pathHistory != '0)
            $fatal(1, "TAGE did not use lane 0 fallback after reset");
        if (queryMeta1.providerValid || queryMeta1.finalPrediction != 1'b1 ||
            queryMeta1.history != '0 || queryMeta1.pathHistory != '0)
            $fatal(1, "TAGE did not use lane 1 fallback after reset");

        // Verify the incremental recurrence for enough steps to wrap every
        // position repeatedly, including dual updates and a full restore.
        checkFolderState();
        for (randomStep = 0; randomStep < 130;
             randomStep = randomStep + 1) begin
            pushFolder(1'b1, folderLfsr[0],
                       (randomStep % 3) == 0, folderLfsr[1]);
            folderLfsr = {folderLfsr[6:0],
                folderLfsr[7] ^ folderLfsr[5] ^
                folderLfsr[4] ^ folderLfsr[3]};
        end
        folderRestoreHistory = 64'h5aa5_0f0f_c33c_9669;
        folderRestoreValid = 1'b1;
        tick();
        folderRestoreValid = 1'b0;
        folderReferenceHistory = folderRestoreHistory;
        folderGlobalHistory = folderReferenceHistory;
        #1;
        checkFolderState();
        folderQuery0Conditional = 1'b1;
        folderQuery0Taken = 1'b1;
        #1;
        folderExpectedWide = referenceFold(
            {folderReferenceHistory[TAGE_HISTORY_WIDTH-2:0], 1'b0},
            FOLDER_HISTORY_LENGTH, FOLDER_WIDTH);
        if (folderQueryFold1 !==
            folderExpectedWide[FOLDER_WIDTH-1:0])
            $fatal(1,
                "lane 1 fold did not use the fixed not-taken slot 0 path");
        folderQuery0Conditional = 1'b0;

        // For every production table, compare query-side keys made from
        // precomputed folds with commit-side keys reconstructed from the full
        // prediction-time GHR/PHIST. Use nonzero, changing contexts.
        for (randomStep = 0; randomStep < 100;
             randomStep = randomStep + 1) begin
            productionHashPc = 32'h0000_0100 +
                instruction_addr_t'(randomStep * 32'd4);
            productionHashHistory = hashHistoryLfsr;
            productionHashPathHistory = hashPathLfsr;
            #1;
            if (productionHashMatch !== {TAGE_TABLE_NUM{1'b1}})
                $fatal(1,
                    "production TAGE query/update Hash key mismatch step=%0d",
                    randomStep);
            hashHistoryLfsr = {
                hashHistoryLfsr[62:0],
                hashHistoryLfsr[63] ^ hashHistoryLfsr[62] ^
                hashHistoryLfsr[60] ^ hashHistoryLfsr[59]};
            hashPathLfsr = {
                hashPathLfsr[14:0],
                hashPathLfsr[15] ^ hashPathLfsr[13] ^
                hashPathLfsr[12] ^ hashPathLfsr[10]};
        end

        // Allocate a direct table entry. Both read lanes issue the matching
        // request on the allocation edge, so the registered response must be
        // the forwarded post-write image, including the new Generation.
        tableUpdateTaken = 1'b1;
        tableAllocateValid = 1'b1;
        #1;
        allocatedIndex = tableUpdateIndex;
        allocatedTag = tableUpdateTag;
        tick();
        if (!tableQueryHit || !tableQueryHit1 ||
            !tableQueryPrediction || !tableQueryPrediction1 ||
            tableQueryCounter != 3'b100 ||
            tableQueryCounter1 != 3'b100 ||
            tableQueryUseful != 2'b00 || tableQueryUseful1 != 2'b00 ||
            tableQueryGeneration != tage_generation_t'(1) ||
            tableQueryGeneration1 != tage_generation_t'(1))
            $fatal(1,
                "TAGE allocation did not bypass both synchronous reads");
        allocatedGeneration = tableQueryGeneration;
        tableAllocateValid = 1'b0;
        tableUpdateGeneration = allocatedGeneration;
        #1;
        if (!tableUpdateMatch || !tableUpdateReplaceable ||
            tableUpdateUseful != 2'b00)
            $fatal(1, "TAGE generation-qualified update lookup failed");

        // Dynamically find both a Path and a direction-history context with
        // the same complete Hash Index but a different Tag. This proves Index
        // aliases are not correlated Tag aliases and verifies that a query
        // change is visible only in the response after the next rising edge.
        for (searchValue = 1; searchValue < 4096 && !pathAliasFound;
             searchValue = searchValue + 1) begin
            tableQueryPc = TAG_PC_A;
            tableQueryHistory = '0;
            tableQueryPathHistory = tage_path_history_t'(searchValue);
            #1;
            if ((tableQueryIndex == allocatedIndex) &&
                (tableQueryTag != allocatedTag)) begin
                aliasPath = tage_path_history_t'(searchValue);
                pathAliasFound = 1'b1;
            end
        end
        if (!pathAliasFound)
            $fatal(1, "independent Path Index/Tag hash collision test failed");
        tableQueryPathHistory = '0;
        tick();
        if (!tableQueryHit)
            $fatal(1, "TAGE baseline query failed before latency test");
        tableQueryPathHistory = aliasPath;
        #1;
        if (!tableQueryHit)
            $fatal(1, "TAGE synchronous response changed before clock edge");
        tick();
        if (tableQueryHit)
            $fatal(1, "TAGE Path alias incorrectly hit after one-cycle read");

        tableQueryPathHistory = '0;
        for (searchValue = 1; searchValue < 16 && !historyAliasFound;
             searchValue = searchValue + 1) begin
            tableQueryHistory = tage_history_t'(searchValue);
            #1;
            if ((tableQueryIndex == allocatedIndex) &&
                (tableQueryTag != allocatedTag)) begin
                aliasHistory = tage_history_t'(searchValue);
                historyAliasFound = 1'b1;
            end
        end
        if (!historyAliasFound)
            $fatal(1, "independent direction Index/Tag hash collision test failed");
        tableQueryHistory = '0;
        tick();
        if (!tableQueryHit)
            $fatal(1, "TAGE baseline history query failed");
        tableQueryHistory = aliasHistory;
        #1;
        if (!tableQueryHit)
            $fatal(1, "TAGE history request bypassed the response register");
        tick();
        if (tableQueryHit)
            $fatal(1,
                "TAGE direction-history alias hit after one-cycle read");

        tableQueryPc1 = TAG_PC_A;
        tableQueryHistory1 = '0;
        tableQueryPathHistory1 = '0;
        tick();
        if (!tableQueryHit1 || !tableQueryPrediction1 ||
            tableQueryCounter1 != 3'b100 ||
            tableQueryGeneration1 != allocatedGeneration)
            $fatal(1, "TAGE table second lookup port failed allocated entry");

        // Direction and usefulness counters still saturate under key-based
        // table access. Lane 1 continuously requests the matching entry, so
        // every update edge also checks the registered write-to-read bypass.
        tableProviderUpdateValid = 1'b1;
        tableUpdateTaken = 1'b1;
        tableProviderUsefulIncrement = 1'b1;
        repeat (5) tick();
        tableProviderUpdateValid = 1'b0;
        tableProviderUsefulIncrement = 1'b0;
        #1;
        if (tableQueryCounter1 != 3'b111 || tableQueryUseful1 != 2'b11 ||
            tableUpdateUseful != 2'b11)
            $fatal(1, "TAGE direction/usefulness positive saturation failed");

        tableProviderUpdateValid = 1'b1;
        tableUpdateTaken = 1'b0;
        tableProviderUsefulDecrement = 1'b1;
        repeat (10) tick();
        tableProviderUpdateValid = 1'b0;
        tableProviderUsefulDecrement = 1'b0;
        #1;
        if (tableQueryCounter1 != 3'b000 || tableQueryUseful1 != 2'b00 ||
            tableUpdateUseful != 2'b00)
            $fatal(1, "TAGE direction/usefulness negative saturation failed");

        tableProviderUpdateValid = 1'b1;
        tableProviderUsefulIncrement = 1'b1;
        repeat (3) tick();
        tableProviderUpdateValid = 1'b0;
        tableProviderUsefulIncrement = 1'b0;
        tableAgeIndex = allocatedIndex;
        tableAgeValid = 1'b1;
        tick();
        tableAgeValid = 1'b0;
        #1;
        if (tableQueryUseful1 != 2'b01 || tableUpdateUseful != 2'b01)
            $fatal(1, "TAGE usefulness aging failed");

        // Locate an Index with the same Row but the opposite Hash-selected
        // Bank. The existing entry must remain visible while the corresponding
        // row in the other Bank is first observed empty and then allocated.
        tableUpdatePc = TAG_PC_A;
        tableUpdateHistory = '0;
        for (searchValue = 1; searchValue < 65536 && !otherBankFound;
             searchValue = searchValue + 1) begin
            tableUpdatePathHistory = tage_path_history_t'(searchValue);
            #1;
            if ((tableUpdateIndex[TEST_INDEX_WIDTH-1:1] ==
                 allocatedIndex[TEST_INDEX_WIDTH-1:1]) &&
                (tableUpdateIndex[0] != allocatedIndex[0])) begin
                otherBankPath = tage_path_history_t'(searchValue);
                otherBankIndex = tableUpdateIndex;
                otherBankTag = tableUpdateTag;
                otherBankFound = 1'b1;
            end
        end
        if (!otherBankFound)
            $fatal(1, "failed to find opposite-bank TAGE Hash context");

        tableQueryPc = TAG_PC_A;
        tableQueryHistory = '0;
        tableQueryPathHistory = '0;
        tableQueryPc1 = TAG_PC_A;
        tableQueryHistory1 = '0;
        tableQueryPathHistory1 = otherBankPath;
        tableUpdatePathHistory = otherBankPath;
        #1;
        if ((tableUpdateIndex != otherBankIndex) ||
            (tableUpdateTag != otherBankTag) ||
            (tableUpdateBank == allocatedIndex[0]))
            $fatal(1, "opposite-bank Hash context was not reproducible");
        tick();
        if (!tableQueryHit || tableQueryHit1 ||
            tableQueryCounter != 3'b000 || tableQueryUseful != 2'b01 ||
            tableQueryGeneration != allocatedGeneration)
            $fatal(1, "TAGE Hash-selected Bank isolation failed");

        tableUpdateTaken = 1'b1;
        tableAllocateValid = 1'b1;
        tick();
        if (!tableQueryHit || !tableQueryHit1 ||
            tableQueryCounter != 3'b000 ||
            tableQueryCounter1 != 3'b100 ||
            tableQueryUseful != 2'b01 || tableQueryUseful1 != 2'b00 ||
            tableQueryGeneration != allocatedGeneration ||
            tableQueryGeneration1 != tage_generation_t'(1))
            $fatal(1, "TAGE opposite-Bank allocation interfered");
        otherBankGeneration = tableQueryGeneration1;
        tableAllocateValid = 1'b0;

        // Both replicated read lanes now request the new Bank. Provider,
        // pressure, and aging writes must each forward their post-write image
        // to both registered responses on the same edge.
        tableQueryPathHistory = otherBankPath;
        tableUpdateGeneration = otherBankGeneration;
        tableProviderUpdateValid = 1'b1;
        tableProviderUsefulIncrement = 1'b1;
        tick();
        if (!tableQueryHit || !tableQueryHit1 ||
            tableQueryCounter != 3'b101 ||
            tableQueryCounter1 != 3'b101 ||
            tableQueryUseful != 2'b01 || tableQueryUseful1 != 2'b01)
            $fatal(1, "TAGE Provider write-to-query bypass failed");
        tableProviderUpdateValid = 1'b0;
        tableProviderUsefulIncrement = 1'b0;

        tableReplacementUsefulDecrement = 1'b1;
        tick();
        if (!tableQueryHit || !tableQueryHit1 ||
            tableQueryCounter != 3'b101 ||
            tableQueryCounter1 != 3'b101 ||
            tableQueryUseful != 2'b00 || tableQueryUseful1 != 2'b00)
            $fatal(1, "TAGE pressure write-to-query bypass failed");
        tableReplacementUsefulDecrement = 1'b0;

        tableProviderUpdateValid = 1'b1;
        tableProviderUsefulIncrement = 1'b1;
        repeat (3) tick();
        tableProviderUpdateValid = 1'b0;
        tableProviderUsefulIncrement = 1'b0;
        tableAgeIndex = otherBankIndex;
        tableAgeValid = 1'b1;
        tick();
        tableAgeValid = 1'b0;
        if (tableQueryUseful != 2'b01 || tableQueryUseful1 != 2'b01)
            $fatal(1, "TAGE aging write-to-query bypass failed");

        // Reallocate the original Bank while Lane 1 requests an Index alias
        // with a different Tag. The new Tag/Generation must hit Lane 0 and
        // must not create a false bypass hit in Lane 1.
        tableUpdatePathHistory = '0;
        tableQueryPathHistory = '0;
        tableQueryPathHistory1 = aliasPath;
        tableQueryHistory = '0;
        tableQueryHistory1 = '0;
        staleGeneration = allocatedGeneration;
        tableAllocateValid = 1'b1;
        tableUpdateTaken = 1'b1;
        tick();
        if (!tableQueryHit || tableQueryHit1 ||
            tableQueryCounter != 3'b100 ||
            tableQueryUseful != 2'b00 ||
            tableQueryGeneration != allocatedGeneration +
                                      tage_generation_t'(1))
            $fatal(1, "TAGE allocation Tag/Generation bypass failed");
        replacementGeneration = tableQueryGeneration;
        tableAllocateValid = 1'b0;

        // A Provider snapshot from before replacement must not train the new
        // occupant. Capturing the new response Generation re-enables update.
        tableQueryPathHistory1 = '0;
        tableUpdateGeneration = staleGeneration;
        tableProviderUpdateValid = 1'b1;
        tableProviderUsefulIncrement = 1'b1;
        #1;
        if (tableUpdateMatch)
            $fatal(1, "stale TAGE Generation matched replacement entry");
        tick();
        if (tableQueryCounter != 3'b100 ||
            tableQueryCounter1 != 3'b100 ||
            tableQueryUseful != 2'b00 || tableQueryUseful1 != 2'b00)
            $fatal(1, "stale Provider snapshot modified replacement entry");

        tableUpdateGeneration = replacementGeneration;
        #1;
        if (!tableUpdateMatch)
            $fatal(1, "captured TAGE Generation did not match Provider");
        tick();
        if (tableQueryCounter != 3'b101 ||
            tableQueryCounter1 != 3'b101 ||
            tableQueryUseful != 2'b01 || tableQueryUseful1 != 2'b01)
            $fatal(1, "generation-qualified Provider bypass failed");
        tableProviderUpdateValid = 1'b0;
        tableProviderUsefulIncrement = 1'b0;

        // Allocation Generation is modulo 2^N. Drive the current entry to
        // all ones, wrap it to zero, then prove that only the new zero-valued
        // snapshot can update it.
        tableAllocateValid = 1'b1;
        searchValue = 0;
        while ((tableQueryGeneration != GENERATION_MAX) &&
               (searchValue < GENERATION_COUNT)) begin
            tick();
            searchValue = searchValue + 1;
        end
        tableAllocateValid = 1'b0;
        if (tableQueryGeneration != GENERATION_MAX)
            $fatal(1, "TAGE Generation failed to reach all ones");
        staleGeneration = tableQueryGeneration;

        tableAllocateValid = 1'b1;
        tick();
        tableAllocateValid = 1'b0;
        if (tableQueryGeneration != '0 || tableQueryGeneration1 != '0)
            $fatal(1, "TAGE Generation did not wrap from all ones to zero");
        replacementGeneration = tableQueryGeneration;

        tableUpdateGeneration = staleGeneration;
        tableProviderUpdateValid = 1'b1;
        #1;
        if (tableUpdateMatch)
            $fatal(1, "pre-wrap TAGE Generation matched post-wrap entry");
        tick();
        if (tableQueryCounter != 3'b100)
            $fatal(1, "pre-wrap stale update modified TAGE counter");

        tableUpdateGeneration = replacementGeneration;
        #1;
        if (!tableUpdateMatch)
            $fatal(1, "post-wrap zero Generation did not match entry");
        tick();
        if (tableQueryCounter != 3'b101 ||
            tableQueryCounter1 != 3'b101)
            $fatal(1, "post-wrap Provider update bypass failed");
        tableProviderUpdateValid = 1'b0;

        // Slot 1 is requested only for Slot 0's fall-through path. Both its
        // virtual direction and Path event therefore use fixed Not-Taken;
        // query0PathTaken is the prior response and must not feed this request.
        query0Control = 1'b1;
        query0Conditional = 1'b0;
        query0PathTaken = 1'b1;
        expectedPath = referenceAdvancePath('0, TAG_PC_A, 1'b0);
        tick();
        if (queryMeta1.history != '0 ||
            queryMeta1.pathHistory != expectedPath)
            $fatal(1, "lane 1 did not use Slot-0-NT control path history");
        query0Conditional = 1'b1;
        tick();
        if (queryMeta1.history != '0 ||
            queryMeta1.pathHistory != expectedPath)
            $fatal(1, "lane 1 did not use fixed NT direction snapshot");

        // Consume two conditionals/control events in one cycle.
        speculateValid = 1'b1;
        speculateTaken = 1'b1;
        speculateValid1 = 1'b1;
        speculateTaken1 = 1'b0;
        speculateControlValid = 1'b1;
        speculateControlValid1 = 1'b1;
        tick();
        speculateValid = 1'b0;
        speculateValid1 = 1'b0;
        speculateControlValid = 1'b0;
        speculateControlValid1 = 1'b0;
        query0Conditional = 1'b0;
        query0Control = 1'b0;
        expectedPath = referenceAdvancePath(
            referenceAdvancePath('0, TAG_PC_A, 1'b1), TAG_PC_B, 1'b0);
        #1;
        if (queryMeta.history != tage_history_t'(64'h2) ||
            queryMeta.pathHistory != expectedPath)
            $fatal(1, "TAGE dual speculative state update failed");

        // The fixed nonzero allocation LFSR begins at A5. Its first rotating
        // search starts at T0 and the 1/4 double-allocation gate is open, so a
        // cold fallback miss reproducibly allocates exactly T0 and T1.
        queryPc = TAG_PC_A;
        fallbackPrediction = 1'b0;
        savedMeta = queryMeta;
        if (savedMeta.providerValid || savedMeta.finalPrediction)
            $fatal(1, "unexpected provider before first TAGE allocation");
        train(TAG_PC_A, 1'b1, savedMeta);
        #1;
        if (lastAllocationLfsr != 8'ha5 ||
            lastAllocationMask != 5'b00011 ||
            dut.allocationLfsr != 8'h4a)
            $fatal(1, "TAGE deterministic double allocation failed");
        if (!queryMeta.providerValid ||
            queryMeta.provider != tage_provider_t'(1) ||
            !queryMeta.providerPrediction || !queryMeta.providerWeak ||
            !queryMeta.alternatePrediction || !queryMeta.finalPrediction)
            $fatal(1, "TAGE double-allocation Provider selection failed");

        // A correct Provider update must not allocate or advance the LFSR.
        savedMeta = queryMeta;
        train(TAG_PC_A, 1'b1, savedMeta);
        #1;
        if (lastAllocationMask != '0 || dut.allocationLfsr != 8'h4a ||
            !queryMeta.providerValid ||
            queryMeta.provider != tage_provider_t'(1))
            $fatal(1, "correct TAGE Provider unexpectedly allocated");

        // Continue until the longest table is present. If grouped UAN selects
        // an alternate against a correct new Provider, first train that
        // chooser-only miss; it must not allocate. Then make the Provider
        // itself wrong and require a strictly longer replacement.
        randomStep = 0;
        while (queryMeta.provider !=
               tage_provider_t'(TAGE_TABLE_NUM-1)) begin
            randomStep = randomStep + 1;
            if (randomStep > 8)
                $fatal(1, "TAGE failed to reach its longest Provider");
            savedMeta = queryMeta;
            if (savedMeta.finalPrediction !=
                savedMeta.providerPrediction) begin
                previousProvider = int'(savedMeta.provider);
                train(TAG_PC_A, savedMeta.providerPrediction, savedMeta);
                #1;
                if (lastAllocationRequest || lastAllocationMask != '0 ||
                    queryMeta.provider != tage_provider_t'(previousProvider))
                    $fatal(1,
                        "chooser-only TAGE miss polluted tagged tables");
                savedMeta = queryMeta;
            end
            previousProvider = int'(savedMeta.provider);
            train(TAG_PC_A, !savedMeta.providerPrediction, savedMeta);
            #1;
            if (!queryMeta.providerValid ||
                (queryMeta.provider <= tage_provider_t'(previousProvider)) ||
                (lastAllocationMask == '0) ||
                ((lastAllocationMask & ~lastEligibleMask) != '0))
                $fatal(1, "TAGE did not allocate a longer Provider");
        end

        // Protect the matching row in every table, then issue four allocation
        // misses with no free candidate. The per-history-group two-bit
        // pressure counter must wait until saturation and then decay exactly
        // one randomly selected minimum-u entry.
        savedMeta = queryMeta;
        for (searchValue = 0; searchValue < TAGE_TABLE_NUM;
             searchValue = searchValue + 1) begin
            savedMeta.providerValid = 1'b1;
            savedMeta.provider = tage_provider_t'(searchValue);
            savedMeta.providerPrediction = 1'b1;
            savedMeta.alternatePrediction = 1'b0;
            savedMeta.finalPrediction = 1'b1;
            savedMeta.providerWeak = 1'b0;
            train(TAG_PC_A, 1'b1, savedMeta);
            #1;
            if (dut.tableUpdateUseful[searchValue] != 2'b01)
                $fatal(1, "failed to protect TAGE allocation candidate");
        end
        savedMeta.providerValid = 1'b0;
        savedMeta.provider = '0;
        savedMeta.providerPrediction = 1'b0;
        savedMeta.alternatePrediction = 1'b0;
        savedMeta.finalPrediction = 1'b0;
        savedMeta.providerWeak = 1'b0;
        for (searchValue = 1; searchValue <= 3;
             searchValue = searchValue + 1) begin
            train(TAG_PC_A, 1'b1, savedMeta);
            #1;
            if (lastAllocationMask != '0 || lastPressureMask != '0 ||
                dut.allocationPressure[0] != searchValue[1:0])
                $fatal(1, "TAGE pressure acted before saturation");
        end
        train(TAG_PC_A, 1'b1, savedMeta);
        #1;
        if (lastAllocationMask != '0 ||
            countTageMask(lastPressureMask) != 1 ||
            dut.allocationPressure[0] != 2'b00)
            $fatal(1, "TAGE saturated pressure did not decay one entry");

        // Table entries above were allocated at GHR=2 and at the virtual path
        // after A/T then B/N. Save the pre-B checkpoint, perturb live state,
        // recover B with actual N, and require the longest Provider in the
        // synchronous response launched on the recovery edge. This checks
        // that all restored folds are aligned with the recovered GHR.
        checkpointAllocValid[0] = 1'b1;
        checkpointAllocTag[0] = rob_tag_t'(5);
        checkpointAllocHistory[0] = tage_history_t'(64'h1);
        checkpointAllocPathHistory[0] =
            referenceAdvancePath('0, TAG_PC_A, 1'b1);
        tick();
        checkpointAllocValid = '0;
        speculateValid = 1'b1;
        speculateTaken = 1'b1;
        speculateControlValid = 1'b1;
        tick();
        speculateValid = 1'b0;
        speculateControlValid = 1'b0;
        recoverValid = 1'b1;
        recoverPc = TAG_PC_B;
        recoverIsConditional = 1'b1;
        recoverTaken = 1'b0;
        recoverRobTag = rob_tag_t'(5);
        tick();
        recoverValid = 1'b0;
        #1;
        if (queryMeta.history != tage_history_t'(64'h2) ||
            queryMeta.pathHistory != expectedPath ||
            !queryMeta.providerValid ||
            queryMeta.provider != tage_provider_t'(TAGE_TABLE_NUM-1))
            $fatal(1, "restored production folds did not immediately hit");

        queryPc1 = TAG_PC_A;
        fallbackPrediction1 = 1'b0;
        tick();
        if (!queryMeta.providerValid || !queryMeta1.providerValid ||
            queryMeta.provider != tage_provider_t'(TAGE_TABLE_NUM-1) ||
            queryMeta1.provider != tage_provider_t'(TAGE_TABLE_NUM-1))
            $fatal(1, "TAGE dual provider lookup failed");
        query0Conditional = 1'b1;
        query0Control = 1'b1;
        query0PathTaken = 1'b0;
        tick();
        if (queryMeta1.history != tage_history_t'(64'h4) ||
            queryMeta1.pathHistory !=
                referenceAdvancePath(expectedPath, TAG_PC_A, 1'b0))
            $fatal(1, "lane 1 path-dependent lookup snapshot failed");
        query0Conditional = 1'b0;
        query0Control = 1'b0;

        // Checkpoint state is written at rename.  Conditional recovery
        // restores the pre-branch GHR/PHIST and applies the actual event.
        checkpointAllocValid[0] = 1'b1;
        checkpointAllocTag[0] = rob_tag_t'(3);
        checkpointAllocHistory[0] = RECOVERY_HISTORY;
        checkpointAllocPathHistory[0] = RECOVERY_PATH;
        tick();
        checkpointAllocValid = '0;

        speculateValid = 1'b1;
        speculateTaken = 1'b1;
        speculateValid1 = 1'b1;
        speculateTaken1 = 1'b1;
        speculateControlValid = 1'b1;
        speculateControlValid1 = 1'b1;
        tick();
        speculateValid = 1'b0;
        speculateValid1 = 1'b0;
        speculateControlValid = 1'b0;
        speculateControlValid1 = 1'b0;
        if (queryMeta.history != tage_history_t'(64'hb))
            $fatal(1, "TAGE history did not advance before recovery");

        recoverValid = 1'b1;
        recoverPc = RECOVERY_PC;
        recoverIsConditional = 1'b1;
        recoverTaken = 1'b0;
        recoverRobTag = rob_tag_t'(3);
        tick();
        recoverValid = 1'b0;
        expectedPath = referenceAdvancePath(
            RECOVERY_PATH, RECOVERY_PC, 1'b0);
        #1;
        if (queryMeta.history != tage_history_t'(64'h2468) ||
            queryMeta.pathHistory != expectedPath)
            $fatal(1, "TAGE conditional checkpoint recovery failed");

        // A target-only JAL/JALR recovery must preserve direction history but
        // still repair PHIST and discard younger wrong-path controls.
        checkpointAllocValid[0] = 1'b1;
        checkpointAllocTag[0] = rob_tag_t'(4);
        checkpointAllocHistory[0] = tage_history_t'(64'h55);
        checkpointAllocPathHistory[0] = 16'h2468;
        tick();
        checkpointAllocValid = '0;
        speculateControlValid = 1'b1;
        speculateTaken = 1'b0;
        tick();
        speculateControlValid = 1'b0;
        expectedPath = referenceAdvancePath(
            expectedPath, queryPc, 1'b0);
        #1;
        if (queryMeta.history != tage_history_t'(64'h2468) ||
            queryMeta.pathHistory != expectedPath)
            $fatal(1, "non-conditional speculative Path History failed");
        recoverValid = 1'b1;
        recoverPc = TAG_PC_B;
        recoverIsConditional = 1'b0;
        recoverTaken = 1'b1;
        recoverRobTag = rob_tag_t'(4);
        tick();
        recoverValid = 1'b0;
        expectedPath = referenceAdvancePath(16'h2468, TAG_PC_B, 1'b1);
        #1;
        if (queryMeta.history != tage_history_t'(64'h55) ||
            queryMeta.pathHistory != expectedPath)
            $fatal(1, "TAGE target-only path-history recovery failed");

        // A precise full flush must restore every earlier retired branch in
        // the reference committed GHR and Path History.
        flush = 1'b1;
        tick();
        flush = 1'b0;
        #1;
        if (queryMeta.history != committedHistoryReference ||
            queryMeta.pathHistory != committedPathReference)
            $fatal(1, "TAGE committed-state flush recovery failed");

        // A branch retiring in the same cycle as a precise flush belongs to
        // the restored committed state.
        updateValid = 1'b1;
        updateIsConditional = 1'b0;
        updatePc = TAG_PC_B;
        updateTaken = 1'b1;
        updateMeta = '0;
        flush = 1'b1;
        tick();
        updateValid = 1'b0;
        flush = 1'b0;
        committedPathReference = referenceAdvancePath(
            committedPathReference, TAG_PC_B, 1'b1);
        #1;
        if (queryMeta.history != committedHistoryReference ||
            queryMeta.pathHistory != committedPathReference)
            $fatal(1, "same-cycle commit/full-flush recovery failed");

        // Train two PC classes in the short-history group independently. The
        // first update rewards the alternate in class 1; the second is a
        // chooser-only miss in class 0 and must reward the Provider without
        // allocating or advancing the allocation LFSR.
        alternateGroupBefore = dut.useAlternateOnNew[1];
        otherAlternateGroupBefore = dut.useAlternateOnNew[0];
        savedMeta = '0;
        savedMeta.providerValid = 1'b1;
        savedMeta.provider = tage_provider_t'(0);
        savedMeta.providerWeak = 1'b1;
        savedMeta.providerPrediction = 1'b0;
        savedMeta.alternatePrediction = 1'b1;
        savedMeta.finalPrediction = 1'b1;
        train(TAG_PC_A, 1'b1, savedMeta);
        #1;
        if ((dut.useAlternateOnNew[1] !=
             alternateGroupBefore + 4'd1) ||
            (dut.useAlternateOnNew[0] != otherAlternateGroupBefore))
            $fatal(1, "grouped alternate-on-new classes interfered");

        lastAllocationLfsr = dut.allocationLfsr;
        savedMeta.providerPrediction = 1'b1;
        savedMeta.alternatePrediction = 1'b0;
        savedMeta.finalPrediction = 1'b0;
        train(TAG_PC_A + 32'd16, 1'b1, savedMeta);
        #1;
        if (lastAllocationRequest || lastAllocationMask != '0 ||
            dut.allocationLfsr != lastAllocationLfsr ||
            dut.useAlternateOnNew[1] != alternateGroupBefore + 4'd1 ||
            dut.useAlternateOnNew[0] != otherAlternateGroupBefore - 4'd1)
            $fatal(1, "chooser-only suppression/grouped UAN update failed");

        $display("TAGE folded-history/hash/path-history smoke test: PASS");
        $finish;
    end

endmodule

module TageFoldConfigurationChecker
    import TypesPkg::*;
#(
    parameter int HISTORY_LENGTH = 4,
    parameter int FOLD_WIDTH = 8,
    parameter int TABLE_ID = 0,
    parameter int FOLD_KIND = 0
)
(
    input logic clk,
    input logic rst,
    input tage_history_t globalHistory_i,
    input logic query0Conditional_i,
    input logic query0Taken_i,
    input logic speculateValid_i,
    input logic speculateTaken_i,
    input logic speculateValid1_i,
    input logic speculateTaken1_i,
    input logic restoreValid_i,
    input tage_history_t restoreHistory_i
);

    logic [FOLD_WIDTH-1:0] queryFold;
    logic [FOLD_WIDTH-1:0] queryFold1;
    logic [FOLD_WIDTH-1:0] expectedFold;
    logic [FOLD_WIDTH-1:0] expectedFold1;
    tage_history_t requestHistory;
    tage_history_t lane1History;

    function automatic logic [FOLD_WIDTH-1:0] referenceFold(
        input tage_history_t history
    );
        logic [FOLD_WIDTH-1:0] result;
        integer bitIndex;
        begin
            result = '0;
            for (bitIndex = 0; bitIndex < HISTORY_LENGTH;
                 bitIndex = bitIndex + 1)
                result[bitIndex % FOLD_WIDTH] =
                    result[bitIndex % FOLD_WIDTH] ^ history[bitIndex];
            referenceFold = result;
        end
    endfunction

    always_comb begin
        // The synchronous table request is formed from the post-accept state
        // sampled at this edge.  A restore overrides all younger speculative
        // events.  Slot 1 is pre-hashed only for the surviving Slot-0-not-
        // taken path; a taken Slot 0 kills Slot 1 before acceptance.
        requestHistory = globalHistory_i;
        if (speculateValid_i)
            requestHistory = {
                requestHistory[TAGE_HISTORY_WIDTH-2:0], speculateTaken_i};
        if (speculateValid1_i)
            requestHistory = {
                requestHistory[TAGE_HISTORY_WIDTH-2:0], speculateTaken1_i};
        if (restoreValid_i)
            requestHistory = restoreHistory_i;

        lane1History = requestHistory;
        if (query0Conditional_i)
            lane1History = {
                requestHistory[TAGE_HISTORY_WIDTH-2:0], 1'b0};
        expectedFold = referenceFold(requestHistory);
        expectedFold1 = referenceFold(lane1History);
    end

    TageFoldedHistory #(
        .HISTORY_LENGTH(HISTORY_LENGTH), .FOLD_WIDTH(FOLD_WIDTH)
    ) dut (
        .clk(clk), .rst(rst), .globalHistory_i(globalHistory_i),
        .query0Conditional_i(query0Conditional_i),
        .query0Taken_i(query0Taken_i),
        .queryFold_o(queryFold), .queryFold1_o(queryFold1),
        .speculateValid_i(speculateValid_i),
        .speculateTaken_i(speculateTaken_i),
        .speculateValid1_i(speculateValid1_i),
        .speculateTaken1_i(speculateTaken1_i),
        .restoreValid_i(restoreValid_i),
        .restoreHistory_i(restoreHistory_i)
    );

    always @(negedge clk) begin
        if (rst && ((queryFold !== expectedFold) ||
                    (queryFold1 !== expectedFold1)))
            $fatal(1,
                "production fold mismatch table=%0d kind=%0d H=%0d C=%0d",
                TABLE_ID, FOLD_KIND, HISTORY_LENGTH, FOLD_WIDTH);
    end

endmodule

module TageHashConfigurationChecker
    import TypesPkg::*;
#(
    parameter int HISTORY_LENGTH = 4,
    parameter int TAG_WIDTH = 7,
    parameter int TABLE_ID = 0,
    parameter int INDEX_WIDTH = $clog2(TAGE_TABLE_ENTRIES)
)
(
    input instruction_addr_t pc_i,
    input tage_history_t history_i,
    input tage_path_history_t pathHistory_i,
    output logic match_o
);

    localparam logic [INDEX_WIDTH-1:0] INDEX_POLYNOMIAL =
        (TABLE_ID == 0) ? INDEX_WIDTH'(8'h1d) :
        (TABLE_ID == 1) ? INDEX_WIDTH'(8'h2b) :
        (TABLE_ID == 2) ? INDEX_WIDTH'(8'h4d) :
        (TABLE_ID == 3) ? INDEX_WIDTH'(8'h87) :
                          INDEX_WIDTH'(8'hb9);
    localparam logic [INDEX_WIDTH-1:0] INDEX_SEED =
        (TABLE_ID == 0) ? INDEX_WIDTH'(8'h13) :
        (TABLE_ID == 1) ? INDEX_WIDTH'(8'h35) :
        (TABLE_ID == 2) ? INDEX_WIDTH'(8'h59) :
        (TABLE_ID == 3) ? INDEX_WIDTH'(8'ha7) :
                          INDEX_WIDTH'(8'hc3);
    localparam logic [TAG_WIDTH-1:0] TAG_POLYNOMIAL =
        (TABLE_ID == 0) ? TAG_WIDTH'(16'h005b) :
        (TABLE_ID == 1) ? TAG_WIDTH'(16'h00b7) :
        (TABLE_ID == 2) ? TAG_WIDTH'(16'h016d) :
        (TABLE_ID == 3) ? TAG_WIDTH'(16'h02d5) :
                          TAG_WIDTH'(16'h0539);
    localparam logic [TAG_WIDTH-1:0] TAG_SEED =
        (TABLE_ID == 0) ? TAG_WIDTH'(16'h0025) :
        (TABLE_ID == 1) ? TAG_WIDTH'(16'h0067) :
        (TABLE_ID == 2) ? TAG_WIDTH'(16'h00d3) :
        (TABLE_ID == 3) ? TAG_WIDTH'(16'h01a9) :
                          TAG_WIDTH'(16'h0357);

    logic [INDEX_WIDTH-1:0] indexFold;
    logic [TAG_WIDTH-1:0] tagFoldA;
    logic [TAG_WIDTH-2:0] tagFoldB;
    logic [INDEX_WIDTH-1:0] queryIndex;
    logic [INDEX_WIDTH-1:0] queryIndex1;
    logic [INDEX_WIDTH-1:0] updateIndex;
    logic [TAG_WIDTH-1:0] queryTag;
    logic [TAG_WIDTH-1:0] queryTag1;
    logic [TAG_WIDTH-1:0] updateTag;
    logic [INDEX_WIDTH-1:0] referenceIndex;
    logic [TAG_WIDTH-1:0] referenceTag;

    function automatic logic [INDEX_WIDTH-1:0] rotateIndex(
        input logic [INDEX_WIDTH-1:0] value,
        input integer amount
    );
        integer rotation;
        begin
            rotation = amount % INDEX_WIDTH;
            rotateIndex = (rotation == 0) ? value :
                ((value << rotation) | (value >> (INDEX_WIDTH-rotation)));
        end
    endfunction

    function automatic logic [TAG_WIDTH-1:0] rotateTag(
        input logic [TAG_WIDTH-1:0] value,
        input integer amount
    );
        integer rotation;
        begin
            rotation = amount % TAG_WIDTH;
            rotateTag = (rotation == 0) ? value :
                ((value << rotation) | (value >> (TAG_WIDTH-rotation)));
        end
    endfunction

    function automatic logic [INDEX_WIDTH-1:0] serialIndexHash(
        input instruction_addr_t pc,
        input tage_path_history_t pathHistory
    );
        logic [INDEX_WIDTH-1:0] state;
        logic feedback;
        integer bitIndex;
        integer pathIndex;
        begin
            state = INDEX_SEED;
            for (bitIndex = 2; bitIndex < WORD_SIZE;
                 bitIndex = bitIndex + 1) begin
                feedback = pc[bitIndex] ^ state[INDEX_WIDTH-1];
                state = {state[INDEX_WIDTH-2:0], 1'b0};
                if (feedback)
                    state = state ^ INDEX_POLYNOMIAL;
            end
            for (bitIndex = 0; bitIndex < TAGE_PATH_HISTORY_WIDTH;
                 bitIndex = bitIndex + 1) begin
                pathIndex = ((2*TABLE_ID+1)*bitIndex + TABLE_ID) %
                            TAGE_PATH_HISTORY_WIDTH;
                feedback = pathHistory[pathIndex] ^ state[INDEX_WIDTH-1];
                state = {state[INDEX_WIDTH-2:0], 1'b0};
                if (feedback)
                    state = state ^ INDEX_POLYNOMIAL;
            end
            serialIndexHash = state;
        end
    endfunction

    function automatic logic [TAG_WIDTH-1:0] serialTagHash(
        input instruction_addr_t pc,
        input tage_path_history_t pathHistory
    );
        logic [TAG_WIDTH-1:0] state;
        logic feedback;
        integer bitIndex;
        integer pathIndex;
        begin
            state = TAG_SEED;
            for (bitIndex = WORD_SIZE-1; bitIndex >= 2;
                 bitIndex = bitIndex - 1) begin
                feedback = pc[bitIndex] ^ state[TAG_WIDTH-1];
                state = {state[TAG_WIDTH-2:0], 1'b0};
                if (feedback)
                    state = state ^ TAG_POLYNOMIAL;
            end
            for (bitIndex = 0; bitIndex < TAGE_PATH_HISTORY_WIDTH;
                 bitIndex = bitIndex + 1) begin
                pathIndex = TAGE_PATH_HISTORY_WIDTH-1-
                    (((2*TABLE_ID+1)*bitIndex + TABLE_ID) %
                     TAGE_PATH_HISTORY_WIDTH);
                feedback = pathHistory[pathIndex] ^ state[TAG_WIDTH-1];
                state = {state[TAG_WIDTH-2:0], 1'b0};
                if (feedback)
                    state = state ^ TAG_POLYNOMIAL;
            end
            serialTagHash = state;
        end
    endfunction

    function automatic logic [INDEX_WIDTH-1:0] foldIndex(
        input tage_history_t history
    );
        logic [INDEX_WIDTH-1:0] result;
        integer bitIndex;
        begin
            result = '0;
            for (bitIndex = 0; bitIndex < HISTORY_LENGTH;
                 bitIndex = bitIndex + 1)
                result[bitIndex % INDEX_WIDTH] =
                    result[bitIndex % INDEX_WIDTH] ^ history[bitIndex];
            foldIndex = result;
        end
    endfunction

    function automatic logic [TAG_WIDTH-1:0] foldTagA(
        input tage_history_t history
    );
        logic [TAG_WIDTH-1:0] result;
        integer bitIndex;
        begin
            result = '0;
            for (bitIndex = 0; bitIndex < HISTORY_LENGTH;
                 bitIndex = bitIndex + 1)
                result[bitIndex % TAG_WIDTH] =
                    result[bitIndex % TAG_WIDTH] ^ history[bitIndex];
            foldTagA = result;
        end
    endfunction

    function automatic logic [TAG_WIDTH-2:0] foldTagB(
        input tage_history_t history
    );
        logic [TAG_WIDTH-2:0] result;
        integer bitIndex;
        begin
            result = '0;
            for (bitIndex = 0; bitIndex < HISTORY_LENGTH;
                 bitIndex = bitIndex + 1)
                result[bitIndex % (TAG_WIDTH-1)] =
                    result[bitIndex % (TAG_WIDTH-1)] ^ history[bitIndex];
            foldTagB = result;
        end
    endfunction

    always_comb begin
        indexFold = foldIndex(history_i);
        tagFoldA = foldTagA(history_i);
        tagFoldB = foldTagB(history_i);
    end

    always_comb begin
        referenceIndex = serialIndexHash(pc_i, pathHistory_i) ^
            rotateIndex(indexFold, TABLE_ID+1);
        referenceTag = serialTagHash(pc_i, pathHistory_i) ^
            rotateTag(tagFoldA, TABLE_ID+1) ^
            rotateTag({tagFoldB, 1'b0}, 2*TABLE_ID+1);
        match_o = (queryIndex == updateIndex) &&
                  (queryTag == updateTag) &&
                  (queryIndex1 == updateIndex) &&
                  (queryTag1 == updateTag) &&
                  (queryIndex == referenceIndex) &&
                  (queryTag == referenceTag);
    end

    TageHash #(
        .ENTRIES(TAGE_TABLE_ENTRIES),
        .HISTORY_LENGTH(HISTORY_LENGTH),
        .TAG_WIDTH(TAG_WIDTH), .TABLE_ID(TABLE_ID)
    ) dut (
        .queryPc_i(pc_i), .queryIndexFold_i(indexFold),
        .queryTagFoldA_i(tagFoldA), .queryTagFoldB_i(tagFoldB),
        .queryPathHistory_i(pathHistory_i),
        .queryIndex_o(queryIndex), .queryTag_o(queryTag),
        .queryPc1_i(pc_i), .queryIndexFold1_i(indexFold),
        .queryTagFoldA1_i(tagFoldA), .queryTagFoldB1_i(tagFoldB),
        .queryPathHistory1_i(pathHistory_i),
        .queryIndex1_o(queryIndex1), .queryTag1_o(queryTag1),
        .updatePc_i(pc_i), .updateHistory_i(history_i),
        .updatePathHistory_i(pathHistory_i),
        .updateIndex_o(updateIndex), .updateTag_o(updateTag)
    );

endmodule
