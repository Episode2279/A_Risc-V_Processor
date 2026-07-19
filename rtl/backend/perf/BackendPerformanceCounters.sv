module BackendPerformanceCounters
    import TypesPkg::*;
(
    input logic clk,
    input logic rst,
    input logic [1:0] issueValid_i,
    input logic [1:0] issueReady_i,
    input renamed_uop_t issueUop_i [2],
    input logic fallbackValid_i,
    input logic fallbackReady_i,
    input logic [$clog2(ISSUE_QUEUE_ENTRY_NUM+LSQ_ENTRY_NUM+1)-1:0]
        issueCount_i,
    input logic robFull_i,
    input logic iqFull_i,
    input logic lsqFull_i,
    input logic prfEmpty_i,
    input logic branchResolved_i,
    input logic branchMispredicted_i,
    input logic jumpSerializing_i,
    input logic storeCommitBlocked_i,
    input logic branchConditional_i,
    input logic branchDirectionMispredict_i,
    input logic branchTargetMispredict_i,
    input logic branchBtbMiss_i,
    input logic branchJal_i,
    input logic branchJalr_i,
    input logic branchRasMiss_i,

    input logic lsuBlocked_i,
    input logic lsqOrderBlocked_i,
    input logic storeBufferAliasBlocked_i,
    input logic mmioOrderBlocked_i,
    input logic dcacheRequestBlocked_i,
    input logic lsuInternalBlocked_i,
    input logic lsuFallbackIssued_i,

    output logic [63:0] dualIssueCycles_o,
    output logic [63:0] singleIssueCycles_o,
    output logic [63:0] iqNoReadyCycles_o,
    // Legacy signal name retained at the top-level interface.  It now counts
    // a blocked shared-LSU candidate rather than a physical port-0 event.
    output logic [63:0] port0LsuBlockedCycles_o,
    output logic [63:0] port0BranchBlockedCycles_o,
    output logic [63:0] lsqOrderBlockedCycles_o,
    output logic [63:0] storeBufferAliasBlockedCycles_o,
    output logic [63:0] mmioOrderBlockedCycles_o,
    output logic [63:0] dcacheRequestBlockedCycles_o,
    output logic [63:0] lsuInternalBlockedCycles_o,
    output logic [63:0] lsuFallbackCycles_o,
    output logic [63:0] robFullCycles_o,
    output logic [63:0] iqFullCycles_o,
    output logic [63:0] lsqFullCycles_o,
    output logic [63:0] prfEmptyCycles_o,
    output logic [63:0] branchCount_o,
    output logic [63:0] branchMispredictCount_o,
    output logic [63:0] jumpSerializationCycles_o,
    output logic [63:0] conditionalCount_o,
    output logic [63:0] conditionalMispredictCount_o,
    output logic [63:0] directionMispredictCount_o,
    output logic [63:0] targetMispredictCount_o,
    output logic [63:0] btbMissCount_o,
    output logic [63:0] jalMispredictCount_o,
    output logic [63:0] jalrMispredictCount_o,
    output logic [63:0] rasMissCount_o,
    output logic [63:0] storeCommitStallCycles_o
);

    logic [1:0] acceptedMain;
    logic fallbackAccepted;
    logic [1:0] acceptedCount;
    logic branchCandidateBlocked;

    always_comb begin
        acceptedMain = issueValid_i & issueReady_i;
        fallbackAccepted = fallbackValid_i && fallbackReady_i;
        acceptedCount = {1'b0, acceptedMain[0]} +
                        {1'b0, acceptedMain[1]} +
                        {1'b0, fallbackAccepted};
        branchCandidateBlocked =
            (issueValid_i[0] && !issueReady_i[0] &&
             (issueUop_i[0].fuClass == FU_BRANCH)) ||
            (issueValid_i[1] && !issueReady_i[1] &&
             (issueUop_i[1].fuClass == FU_BRANCH));
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            dualIssueCycles_o <= 0;
            singleIssueCycles_o <= 0;
            iqNoReadyCycles_o <= 0;
            port0LsuBlockedCycles_o <= 0;
            port0BranchBlockedCycles_o <= 0;
            lsqOrderBlockedCycles_o <= 0;
            storeBufferAliasBlockedCycles_o <= 0;
            mmioOrderBlockedCycles_o <= 0;
            dcacheRequestBlockedCycles_o <= 0;
            lsuInternalBlockedCycles_o <= 0;
            lsuFallbackCycles_o <= 0;
            robFullCycles_o <= 0;
            iqFullCycles_o <= 0;
            lsqFullCycles_o <= 0;
            prfEmptyCycles_o <= 0;
            branchCount_o <= 0;
            branchMispredictCount_o <= 0;
            jumpSerializationCycles_o <= 0;
            conditionalCount_o <= 0;
            conditionalMispredictCount_o <= 0;
            directionMispredictCount_o <= 0;
            targetMispredictCount_o <= 0;
            btbMissCount_o <= 0;
            jalMispredictCount_o <= 0;
            jalrMispredictCount_o <= 0;
            rasMissCount_o <= 0;
            storeCommitStallCycles_o <= 0;
        end else begin
            dualIssueCycles_o <= dualIssueCycles_o +
                ((acceptedCount == 2) ? 64'd1 : 64'd0);
            singleIssueCycles_o <= singleIssueCycles_o +
                ((acceptedCount == 1) ? 64'd1 : 64'd0);
            iqNoReadyCycles_o <= iqNoReadyCycles_o +
                (((issueCount_i != 0) && !(|issueValid_i) &&
                  !fallbackValid_i) ? 64'd1 : 64'd0);
            port0LsuBlockedCycles_o <= port0LsuBlockedCycles_o +
                (lsuBlocked_i ? 64'd1 : 64'd0);
            port0BranchBlockedCycles_o <= port0BranchBlockedCycles_o +
                (branchCandidateBlocked ? 64'd1 : 64'd0);
            lsqOrderBlockedCycles_o <= lsqOrderBlockedCycles_o +
                (lsqOrderBlocked_i ? 64'd1 : 64'd0);
            storeBufferAliasBlockedCycles_o <=
                storeBufferAliasBlockedCycles_o +
                (storeBufferAliasBlocked_i ? 64'd1 : 64'd0);
            mmioOrderBlockedCycles_o <= mmioOrderBlockedCycles_o +
                (mmioOrderBlocked_i ? 64'd1 : 64'd0);
            dcacheRequestBlockedCycles_o <= dcacheRequestBlockedCycles_o +
                (dcacheRequestBlocked_i ? 64'd1 : 64'd0);
            lsuInternalBlockedCycles_o <= lsuInternalBlockedCycles_o +
                (lsuInternalBlocked_i ? 64'd1 : 64'd0);
            lsuFallbackCycles_o <= lsuFallbackCycles_o +
                (lsuFallbackIssued_i ? 64'd1 : 64'd0);
            robFullCycles_o <= robFullCycles_o + (robFull_i ? 64'd1 : 64'd0);
            iqFullCycles_o <= iqFullCycles_o + (iqFull_i ? 64'd1 : 64'd0);
            lsqFullCycles_o <= lsqFullCycles_o + (lsqFull_i ? 64'd1 : 64'd0);
            prfEmptyCycles_o <= prfEmptyCycles_o +
                (prfEmpty_i ? 64'd1 : 64'd0);
            branchCount_o <= branchCount_o +
                (branchResolved_i ? 64'd1 : 64'd0);
            branchMispredictCount_o <= branchMispredictCount_o +
                ((branchResolved_i && branchMispredicted_i) ? 64'd1 : 64'd0);
            jumpSerializationCycles_o <= jumpSerializationCycles_o +
                (jumpSerializing_i ? 64'd1 : 64'd0);
            conditionalCount_o <= conditionalCount_o +
                ((branchResolved_i && branchConditional_i) ? 64'd1 : 64'd0);
            conditionalMispredictCount_o <= conditionalMispredictCount_o +
                ((branchResolved_i && branchConditional_i &&
                  branchMispredicted_i) ? 64'd1 : 64'd0);
            directionMispredictCount_o <= directionMispredictCount_o +
                ((branchResolved_i && branchDirectionMispredict_i) ?
                 64'd1 : 64'd0);
            targetMispredictCount_o <= targetMispredictCount_o +
                ((branchResolved_i && branchTargetMispredict_i) ?
                 64'd1 : 64'd0);
            btbMissCount_o <= btbMissCount_o +
                ((branchResolved_i && branchBtbMiss_i) ? 64'd1 : 64'd0);
            jalMispredictCount_o <= jalMispredictCount_o +
                ((branchResolved_i && branchJal_i && branchMispredicted_i) ?
                 64'd1 : 64'd0);
            jalrMispredictCount_o <= jalrMispredictCount_o +
                ((branchResolved_i && branchJalr_i && branchMispredicted_i) ?
                 64'd1 : 64'd0);
            rasMissCount_o <= rasMissCount_o +
                ((branchResolved_i && branchRasMiss_i) ? 64'd1 : 64'd0);
            storeCommitStallCycles_o <= storeCommitStallCycles_o +
                (storeCommitBlocked_i ? 64'd1 : 64'd0);
        end
    end

endmodule
