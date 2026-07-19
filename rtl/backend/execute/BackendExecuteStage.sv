module BackendExecuteStage
    import TypesPkg::*;
(
    input  logic clk,
    input  logic rst,
    input  logic flush_i,
    input  logic recoverValid_i,
    input  logic [ROB_ENTRY_NUM-1:0] recoverYoungerMask_i,

    // Candidate 0 is the oldest memory/CSR candidate when one exists.
    // Candidate 1 is the oldest ALU/branch candidate.  The fallback is the
    // next ordinary integer candidate and is accepted only when candidate 0 is a
    // memory uop which cannot enter the shared LSU this cycle.
    input  logic [1:0] issueValid_i,
    input  renamed_uop_t issueUop_i [2],
    input  word_t sourceA_i [2],
    input  word_t sourceB_i [2],
    input  logic fallbackValid_i,
    input  renamed_uop_t fallbackUop_i,
    input  word_t fallbackSourceA_i,
    input  word_t fallbackSourceB_i,
    input  word_t csrReadData_i,

    input  logic integerOrderingReady_i,
    input  logic lsqIssueReady_i,
    input  logic lsqForwardValid_i,
    input  word_t lsqForwardData_i,
    input  logic memoryRequestReady_i,
    input  logic memoryResponseValid_i,
    input  rob_tag_t memoryResponseId_i,
    input  word_t memoryResponseData_i,
    output logic memoryResponseReady_o,

    output logic [1:0] issueReady_o,
    output logic fallbackReady_o,
    output logic memoryCandidateBlocked_o,
    output logic fallbackIssued_o,
    output logic lsuCandidateValid_o,

    output logic [1:0] completionValid_o,
    output rob_tag_t completionTag_o [2],
    output logic [1:0] completionException_o,
    output logic [5:0] completionCause_o [2],
    output word_t completionValue_o [2],
    output logic [1:0] writebackValid_o,
    output phys_reg_addr_t writebackPhys_o [2],
    output word_t writebackData_o [2],

    output logic branchResolved_o,
    output instruction_addr_t branchPc_o,
    output logic branchIsConditional_o,
    output logic branchIsCall_o,
    output logic branchIsReturn_o,
    output bpu_index_t branchPredictorIndex_o,
    output logic branchTaken_o,
    output instruction_addr_t branchTarget_o,
    output logic branchMispredicted_o,
    output instruction_addr_t branchRedirect_o,
    output rob_tag_t branchRobTag_o,
    output logic branchLane_o,

    output logic csrValid_o,
    output csr_op_t csrOp_o,
    output csr_addr_t csrAddr_o,
    output word_t csrWriteData_o,

    output logic lsuExecuteValid_o,
    output logic lsuLoadReadValid_o,
    output logic lsuIsStore_o,
    output word_t lsuAddress_o,
    output word_t lsuStoreData_o,
    output mem_access_t lsuMemoryAccess_o,
    output lsq_tag_t lsuTag_o,
    output rob_tag_t lsuLoadRequestId_o
);

    logic candidate0IsMemory;
    logic fallbackActive;
    logic cacheFallbackValid;
    rob_tag_t cacheFallbackTag;
    logic memorySourceValid;
    renamed_uop_t memorySourceUop;
    word_t memorySourceA;
    word_t memorySourceB;
    logic primaryIssueValid;
    logic secondaryIssueValid;
    renamed_uop_t primaryIssueUop;
    renamed_uop_t secondaryIssueUop;
    word_t primarySourceA;
    word_t primarySourceB;
    word_t secondarySourceA;
    word_t secondarySourceB;

    logic pReady, sReady, mReady;
    logic pCompletionReady;
    logic pCV, sCV, mCV;
    logic pWV, sWV, mWV;
    logic pEx, sEx, mEx;
    logic recoveryFilterValid;
    logic pAllowed, sAllowed, mAllowed;
    logic [ROB_ENTRY_NUM-1:0] recoveryFilterMask;
    rob_tag_t pTag, sTag, mTag;
    logic [5:0] pCause, sCause, mCause;
    word_t pValue, sValue, mValue;
    word_t pWD, sWD, mWD;
    phys_reg_addr_t pWP, sWP, mWP;
    logic pBrResolved, sBrResolved;
    logic pBrConditional, sBrConditional;
    logic pBrCall, sBrCall;
    logic pBrReturn, sBrReturn;
    logic pBrTaken, sBrTaken;
    logic pBrMispredict, sBrMispredict;
    instruction_addr_t pBrPc, sBrPc;
    instruction_addr_t pBrTarget, sBrTarget;
    instruction_addr_t pBrRedirect, sBrRedirect;
    bpu_index_t pBrIndex, sBrIndex;

    assign candidate0IsMemory = issueValid_i[0] &&
                                (issueUop_i[0].fuClass == FU_MEMORY);

    // A memory candidate owns the shared LSU, but not either integer port.
    // When ordering or the cache request channel blocks that candidate, it
    // remains resident in the IQ and the two integer candidates use both
    // execution ports.  Once the block clears, memory plus one integer uop
    // may issue in the same cycle.  This keeps total IQ acceptance <= 2 and
    // avoids removing a memory uop before the LSU has really accepted it.
    always_comb begin
        primaryIssueValid = issueValid_i[0] && !candidate0IsMemory;
        primaryIssueUop = issueUop_i[0];
        primarySourceA = sourceA_i[0];
        primarySourceB = sourceB_i[0];

        secondaryIssueValid = issueValid_i[1];
        secondaryIssueUop = issueUop_i[1];
        secondarySourceA = sourceA_i[1];
        secondarySourceB = sourceB_i[1];

        if (candidate0IsMemory) begin
            primaryIssueValid = fallbackValid_i && fallbackActive;
            primaryIssueUop = fallbackUop_i;
            primaryIssueUop.fuClass = FU_INTEGER;
            primarySourceA = fallbackSourceA_i;
            primarySourceB = fallbackSourceB_i;

            // Candidate 1 stays on the secondary port in both modes.  In
            // particular, a branch never migrates with LSU Ready.
            secondaryIssueValid = issueValid_i[1];
            secondaryIssueUop = issueUop_i[1];
            secondarySourceA = sourceA_i[1];
            secondarySourceB = sourceB_i[1];
        end
    end

    always_comb begin
        // During integer fallback the memory uop must remain entirely
        // unaccepted: both IQ Ready and LSU Valid are suppressed.  Otherwise
        // a cache Ready transition can launch the request while the IQ keeps
        // the uop, leaving a stale entry after its ROB tag is recycled.
        memorySourceValid = candidate0IsMemory && !fallbackActive;
        memorySourceUop = issueUop_i[0];
        memorySourceA = sourceA_i[0];
        memorySourceB = sourceB_i[0];
    end

    // Stores never require the cache request channel at execute time. Loads
    // forwarded by the LSQ likewise complete without a D-cache request.
    // Restricting the decision to these explicit back-pressure causes avoids
    // feeding completion/recovery Ready back into branch selection.
    assign fallbackActive = candidate0IsMemory &&
        (!lsqIssueReady_i ||
         (cacheFallbackValid &&
          (cacheFallbackTag == issueUop_i[0].robTag) &&
          !issueUop_i[0].dataWriteEnable));

    // Cache Ready depends on the commit/MMIO path, which in turn can depend
    // on same-cycle branch recovery.  Register only this cause of fallback to
    // keep the port-steering logic acyclic.  The ROB tag prevents the state
    // from delaying an unrelated memory candidate.
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            cacheFallbackValid <= 1'b0;
            cacheFallbackTag <= '0;
        end else if (flush_i || recoverValid_i) begin
            cacheFallbackValid <= 1'b0;
        end else if (candidate0IsMemory && lsqIssueReady_i &&
                     !issueUop_i[0].dataWriteEnable &&
                     !lsqForwardValid_i && !memoryRequestReady_i) begin
            cacheFallbackValid <= 1'b1;
            cacheFallbackTag <= issueUop_i[0].robTag;
        end else begin
            cacheFallbackValid <= 1'b0;
        end
    end

    assign issueReady_o[0] = candidate0IsMemory ?
        (!fallbackActive && mReady) : pReady;
    assign issueReady_o[1] = sReady;
    assign fallbackReady_o = candidate0IsMemory && fallbackActive && pReady;
    assign memoryCandidateBlocked_o = candidate0IsMemory && !mReady;
    assign fallbackIssued_o = fallbackValid_i && fallbackReady_o;
    // Ordering/forwarding queries still observe the held candidate even when
    // LSU issue is temporarily gated by fallback.
    assign lsuCandidateValid_o = candidate0IsMemory;

    assign pAllowed = !recoveryFilterValid || !recoveryFilterMask[pTag];
    assign sAllowed = !recoveryFilterValid || !recoveryFilterMask[sTag];
    assign mAllowed = !recoveryFilterValid || !recoveryFilterMask[mTag];
    // An LSU completion normally has lane-0 priority.  A primary completion
    // killed by recovery must nevertheless be consumed immediately; holding
    // it until recoveryFilterValid drops would leak a wrong-path ROB/PRF
    // update one cycle later.  A killed LSU completion likewise need not
    // block a valid primary result.
    assign pCompletionReady = !(mCV && mAllowed) || (pCV && !pAllowed);

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            recoveryFilterValid <= 1'b0;
            recoveryFilterMask <= '0;
        end else if (flush_i) begin
            recoveryFilterValid <= 1'b0;
            recoveryFilterMask <= '0;
        end else begin
            recoveryFilterValid <= recoverValid_i;
            recoveryFilterMask <= recoverYoungerMask_i;
        end
    end

    always_comb begin
        completionValid_o[0] = (mCV && mAllowed) || (pCV && pAllowed);
        completionValid_o[1] = sCV && sAllowed;
        completionTag_o[0] = (mCV && mAllowed) ? mTag : pTag;
        completionTag_o[1] = sTag;
        completionException_o[0] = (mCV && mAllowed) ? mEx : pEx;
        completionException_o[1] = sEx;
        completionCause_o[0] = (mCV && mAllowed) ? mCause : pCause;
        completionCause_o[1] = sCause;
        completionValue_o[0] = (mCV && mAllowed) ? mValue : pValue;
        completionValue_o[1] = sValue;
        writebackValid_o[0] = (mCV && mAllowed) ? mWV : (pWV && pAllowed);
        writebackValid_o[1] = sWV && sAllowed;
        writebackPhys_o[0] = (mCV && mAllowed) ? mWP : pWP;
        writebackPhys_o[1] = sWP;
        writebackData_o[0] = (mCV && mAllowed) ? mWD : pWD;
        writebackData_o[1] = sWD;

        if (candidate0IsMemory) begin
            // During memory arbitration the primary input is an ordinary
            // integer fallback, so all branch state comes from the fixed
            // secondary candidate and is independent of fallbackActive.
            branchResolved_o = sBrResolved;
            branchPc_o = sBrPc;
            branchIsConditional_o = sBrConditional;
            branchIsCall_o = sBrCall;
            branchIsReturn_o = sBrReturn;
            branchPredictorIndex_o = sBrIndex;
            branchTaken_o = sBrTaken;
            branchTarget_o = sBrTarget;
            branchMispredicted_o = sBrMispredict;
            branchRedirect_o = sBrRedirect;
            branchRobTag_o = secondaryIssueUop.robTag;
            branchLane_o = 1'b1;
        end else begin
            branchResolved_o = pBrResolved || sBrResolved;
            branchPc_o = sBrResolved ? sBrPc : pBrPc;
            branchIsConditional_o = sBrResolved ? sBrConditional : pBrConditional;
            branchIsCall_o = sBrResolved ? sBrCall : pBrCall;
            branchIsReturn_o = sBrResolved ? sBrReturn : pBrReturn;
            branchPredictorIndex_o = sBrResolved ? sBrIndex : pBrIndex;
            branchTaken_o = sBrResolved ? sBrTaken : pBrTaken;
            branchTarget_o = sBrResolved ? sBrTarget : pBrTarget;
            branchMispredicted_o = sBrResolved ? sBrMispredict : pBrMispredict;
            branchRedirect_o = sBrResolved ? sBrRedirect : pBrRedirect;
            branchRobTag_o = sBrResolved ? secondaryIssueUop.robTag :
                                          primaryIssueUop.robTag;
            branchLane_o = sBrResolved;
        end
    end

    OoOExecutionUnit primary (
        .clk(clk), .rst(rst), .flush_i(flush_i),
        .issueValid_i(primaryIssueValid), .issueUop_i(primaryIssueUop),
        .sourceA_i(primarySourceA), .sourceB_i(primarySourceB),
        .csrReadData_i(csrReadData_i),
        .orderingReady_i(integerOrderingReady_i), .issueReady_o(pReady),
        .completionValid_o(pCV), .completionRobTag_o(pTag),
        .completionException_o(pEx), .completionCause_o(pCause),
        .completionValue_o(pValue), .writebackValid_o(pWV),
        .writebackPhys_o(pWP), .writebackData_o(pWD),
        .branchResolved_o(pBrResolved), .branchPc_o(pBrPc),
        .branchIsConditional_o(pBrConditional), .branchIsCall_o(pBrCall),
        .branchIsReturn_o(pBrReturn), .branchPredictorIndex_o(pBrIndex),
        .branchTaken_o(pBrTaken), .branchTarget_o(pBrTarget),
        .branchMispredicted_o(pBrMispredict), .branchRedirect_o(pBrRedirect),
        .csrValid_o(csrValid_o), .csrOp_o(csrOp_o), .csrAddr_o(csrAddr_o),
        .csrWriteData_o(csrWriteData_o),
        .completionReady_i(pCompletionReady)
    );

    OoOExecutionUnit secondary (
        .clk(clk), .rst(rst), .flush_i(flush_i),
        .issueValid_i(secondaryIssueValid), .issueUop_i(secondaryIssueUop),
        .sourceA_i(secondarySourceA), .sourceB_i(secondarySourceB),
        .csrReadData_i('0), .orderingReady_i(integerOrderingReady_i),
        .issueReady_o(sReady), .completionValid_o(sCV),
        .completionRobTag_o(sTag), .completionException_o(sEx),
        .completionCause_o(sCause), .completionValue_o(sValue),
        .writebackValid_o(sWV), .writebackPhys_o(sWP),
        .writebackData_o(sWD), .branchResolved_o(sBrResolved),
        .branchPc_o(sBrPc), .branchIsConditional_o(sBrConditional),
        .branchIsCall_o(sBrCall), .branchIsReturn_o(sBrReturn),
        .branchPredictorIndex_o(sBrIndex), .branchTaken_o(sBrTaken),
        .branchTarget_o(sBrTarget), .branchMispredicted_o(sBrMispredict),
        .branchRedirect_o(sBrRedirect), .csrValid_o(), .csrOp_o(),
        .csrAddr_o(), .csrWriteData_o(), .completionReady_i(1'b1)
    );

    LoadStoreExecutionUnit memory (
        .clk(clk), .rst(rst), .flush_i(flush_i),
        .recoverValid_i(recoverValid_i),
        .recoverYoungerMask_i(recoverYoungerMask_i),
        .issueValid_i(memorySourceValid), .issueUop_i(memorySourceUop),
        .sourceA_i(memorySourceA), .sourceB_i(memorySourceB),
        .orderingReady_i(lsqIssueReady_i), .forwardValid_i(lsqForwardValid_i),
        .forwardData_i(lsqForwardData_i),
        .memoryRequestReady_i(memoryRequestReady_i),
        .memoryResponseValid_i(memoryResponseValid_i),
        .memoryResponseId_i(memoryResponseId_i),
        .memoryResponseData_i(memoryResponseData_i),
        .memoryResponseReady_o(memoryResponseReady_o), .busy_o(),
        .issueReady_o(mReady), .completionValid_o(mCV),
        .completionRobTag_o(mTag), .completionException_o(mEx),
        .completionCause_o(mCause), .completionValue_o(mValue),
        .writebackValid_o(mWV), .writebackPhys_o(mWP),
        .writebackData_o(mWD), .executeValid_o(lsuExecuteValid_o),
        .loadReadValid_o(lsuLoadReadValid_o),
        .loadRequestId_o(lsuLoadRequestId_o), .isStore_o(lsuIsStore_o),
        .address_o(lsuAddress_o), .storeData_o(lsuStoreData_o),
        .memoryAccess_o(lsuMemoryAccess_o), .lsqTag_o(lsuTag_o),
        .completionReady_i(1'b1)
    );

endmodule
