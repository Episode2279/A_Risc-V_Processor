module BackendPerformanceCounters import TypesPkg::*; (
 input logic clk,rst, input logic [1:0] issueValid_i,issueReady_i,
 input renamed_uop_t issueUop_i[2], input logic [$clog2(ISSUE_QUEUE_ENTRY_NUM+LSQ_ENTRY_NUM+1)-1:0] issueCount_i,
 input logic robFull_i,iqFull_i,lsqFull_i,prfEmpty_i,branchResolved_i,branchMispredicted_i,jumpSerializing_i,
 input logic branchConditional_i,branchDirectionMispredict_i,branchTargetMispredict_i,
 input logic branchBtbMiss_i,branchJal_i,branchJalr_i,branchRasMiss_i,
 output logic [63:0] dualIssueCycles_o,singleIssueCycles_o,iqNoReadyCycles_o,port0LsuBlockedCycles_o,
 port0BranchBlockedCycles_o,robFullCycles_o,iqFullCycles_o,lsqFullCycles_o,prfEmptyCycles_o,
 branchCount_o,branchMispredictCount_o,jumpSerializationCycles_o,
 conditionalCount_o,conditionalMispredictCount_o,directionMispredictCount_o,targetMispredictCount_o,
 btbMissCount_o,jalMispredictCount_o,jalrMispredictCount_o,rasMissCount_o);
 logic [1:0] accepted;
 always_comb accepted=issueValid_i&issueReady_i;
 always_ff @(posedge clk or negedge rst) begin
  if(!rst) begin
   dualIssueCycles_o<=0; singleIssueCycles_o<=0; iqNoReadyCycles_o<=0; port0LsuBlockedCycles_o<=0;
   port0BranchBlockedCycles_o<=0; robFullCycles_o<=0; iqFullCycles_o<=0; lsqFullCycles_o<=0;
   prfEmptyCycles_o<=0; branchCount_o<=0; branchMispredictCount_o<=0; jumpSerializationCycles_o<=0;
   conditionalCount_o<=0; conditionalMispredictCount_o<=0; directionMispredictCount_o<=0;
   targetMispredictCount_o<=0; btbMissCount_o<=0; jalMispredictCount_o<=0;
   jalrMispredictCount_o<=0; rasMissCount_o<=0;
  end else begin
   dualIssueCycles_o<=dualIssueCycles_o+((&accepted)?64'd1:64'd0); singleIssueCycles_o<=singleIssueCycles_o+((^accepted)?64'd1:64'd0);
   iqNoReadyCycles_o<=iqNoReadyCycles_o+(((issueCount_i!=0)&&!(|issueValid_i))?64'd1:64'd0);
   port0LsuBlockedCycles_o<=port0LsuBlockedCycles_o+((issueValid_i[0]&&!issueReady_i[0]&&(issueUop_i[0].fuClass==FU_MEMORY))?64'd1:64'd0);
   port0BranchBlockedCycles_o<=port0BranchBlockedCycles_o+((issueValid_i[0]&&!issueReady_i[0]&&(issueUop_i[0].fuClass==FU_BRANCH))?64'd1:64'd0);
   robFullCycles_o<=robFullCycles_o+(robFull_i?64'd1:64'd0); iqFullCycles_o<=iqFullCycles_o+(iqFull_i?64'd1:64'd0);
   lsqFullCycles_o<=lsqFullCycles_o+(lsqFull_i?64'd1:64'd0); prfEmptyCycles_o<=prfEmptyCycles_o+(prfEmpty_i?64'd1:64'd0);
   branchCount_o<=branchCount_o+(branchResolved_i?64'd1:64'd0);
   branchMispredictCount_o<=branchMispredictCount_o+((branchResolved_i&&branchMispredicted_i)?64'd1:64'd0);
   jumpSerializationCycles_o<=jumpSerializationCycles_o+(jumpSerializing_i?64'd1:64'd0);
   conditionalCount_o<=conditionalCount_o+((branchResolved_i&&branchConditional_i)?64'd1:64'd0);
   conditionalMispredictCount_o<=conditionalMispredictCount_o+((branchResolved_i&&branchConditional_i&&branchMispredicted_i)?64'd1:64'd0);
   directionMispredictCount_o<=directionMispredictCount_o+((branchResolved_i&&branchDirectionMispredict_i)?64'd1:64'd0);
   targetMispredictCount_o<=targetMispredictCount_o+((branchResolved_i&&branchTargetMispredict_i)?64'd1:64'd0);
   btbMissCount_o<=btbMissCount_o+((branchResolved_i&&branchBtbMiss_i)?64'd1:64'd0);
   jalMispredictCount_o<=jalMispredictCount_o+((branchResolved_i&&branchJal_i&&branchMispredicted_i)?64'd1:64'd0);
   jalrMispredictCount_o<=jalrMispredictCount_o+((branchResolved_i&&branchJalr_i&&branchMispredicted_i)?64'd1:64'd0);
   rasMissCount_o<=rasMissCount_o+((branchResolved_i&&branchRasMiss_i)?64'd1:64'd0);
  end
 end
endmodule
