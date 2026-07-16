module BackendExecuteStage import TypesPkg::*; (
 input logic clk,rst,flush_i,recoverValid_i, input logic [ROB_ENTRY_NUM-1:0] recoverYoungerMask_i,
 input logic [1:0] issueValid_i,
 input renamed_uop_t issueUop_i[2], input word_t sourceA_i[2],sourceB_i[2], input word_t csrReadData_i,
 input logic integerOrderingReady_i,lsqIssueReady_i,lsqForwardValid_i, input word_t lsqForwardData_i,
 input logic memoryPortReady_i, input word_t memoryReadData_i, output logic [1:0] issueReady_o,
 output logic [1:0] completionValid_o, output rob_tag_t completionTag_o[2], output logic [1:0] completionException_o,
 output logic [5:0] completionCause_o[2], output word_t completionValue_o[2], output logic [1:0] writebackValid_o,
 output phys_reg_addr_t writebackPhys_o[2], output word_t writebackData_o[2], output logic branchResolved_o,
 output instruction_addr_t branchPc_o, output logic branchIsConditional_o,branchIsCall_o,branchIsReturn_o, output bpu_index_t branchPredictorIndex_o,
 output logic branchTaken_o, output instruction_addr_t branchTarget_o, output logic branchMispredicted_o,
 output instruction_addr_t branchRedirect_o, output rob_tag_t branchRobTag_o, output logic branchLane_o, output logic csrValid_o, output csr_op_t csrOp_o,
 output csr_addr_t csrAddr_o, output word_t csrWriteData_o, output logic lsuExecuteValid_o,lsuLoadReadValid_o,lsuIsStore_o,
 output word_t lsuAddress_o,lsuStoreData_o, output mem_access_t lsuMemoryAccess_o, output lsq_tag_t lsuTag_o);
 logic pReady,sReady,mReady,pCV,sCV,mCV,pWV,sWV,mWV,pEx,sEx,mEx;
 logic recoveryFilterValid,pAllowed,sAllowed,mAllowed;
 logic [ROB_ENTRY_NUM-1:0] recoveryFilterMask;
 rob_tag_t pTag,sTag,mTag; logic [5:0] pCause,sCause,mCause; word_t pValue,sValue,mValue,pWD,sWD,mWD;
 phys_reg_addr_t pWP,sWP,mWP;
 logic pBrResolved,sBrResolved,pBrConditional,sBrConditional,pBrCall,sBrCall,pBrReturn,sBrReturn;
 logic pBrTaken,sBrTaken,pBrMispredict,sBrMispredict;
 instruction_addr_t pBrPc,sBrPc,pBrTarget,sBrTarget,pBrRedirect,sBrRedirect;
 bpu_index_t pBrIndex,sBrIndex;
 assign pAllowed=!recoveryFilterValid||!recoveryFilterMask[pTag];
 assign sAllowed=!recoveryFilterValid||!recoveryFilterMask[sTag];
 assign mAllowed=!recoveryFilterValid||!recoveryFilterMask[mTag];
 always_ff @(posedge clk or negedge rst) begin
  if(!rst) begin recoveryFilterValid<=1'b0; recoveryFilterMask<='0; end
  else if(flush_i) begin recoveryFilterValid<=1'b0; recoveryFilterMask<='0; end
  else begin recoveryFilterValid<=recoverValid_i; recoveryFilterMask<=recoverYoungerMask_i; end
 end
 always_comb begin
  issueReady_o[0]=(issueUop_i[0].fuClass==FU_MEMORY)?mReady:pReady; issueReady_o[1]=sReady;
  completionValid_o[0]=(pCV&&pAllowed)||(mCV&&mAllowed); completionValid_o[1]=sCV&&sAllowed;
  completionTag_o[0]=(mCV&&mAllowed)?mTag:pTag; completionTag_o[1]=sTag;
  completionException_o[0]=(mCV&&mAllowed)?mEx:pEx; completionException_o[1]=sEx;
  completionCause_o[0]=(mCV&&mAllowed)?mCause:pCause; completionCause_o[1]=sCause;
  completionValue_o[0]=(mCV&&mAllowed)?mValue:pValue; completionValue_o[1]=sValue;
  writebackValid_o[0]=(pWV&&pAllowed)||(mWV&&mAllowed); writebackValid_o[1]=sWV&&sAllowed;
  writebackPhys_o[0]=(mWV&&mAllowed)?mWP:pWP; writebackPhys_o[1]=sWP;
  writebackData_o[0]=(mWV&&mAllowed)?mWD:pWD; writebackData_o[1]=sWD;
  branchResolved_o=pBrResolved||sBrResolved;
  branchPc_o=sBrResolved?sBrPc:pBrPc;
  branchIsConditional_o=sBrResolved?sBrConditional:pBrConditional;
  branchIsCall_o=sBrResolved?sBrCall:pBrCall;
  branchIsReturn_o=sBrResolved?sBrReturn:pBrReturn;
  branchPredictorIndex_o=sBrResolved?sBrIndex:pBrIndex;
  branchTaken_o=sBrResolved?sBrTaken:pBrTaken;
  branchTarget_o=sBrResolved?sBrTarget:pBrTarget;
  branchMispredicted_o=sBrResolved?sBrMispredict:pBrMispredict;
  branchRedirect_o=sBrResolved?sBrRedirect:pBrRedirect;
  branchRobTag_o=sBrResolved?issueUop_i[1].robTag:issueUop_i[0].robTag;
  branchLane_o=sBrResolved;
 end
 OoOExecutionUnit primary(.clk(clk),.rst(rst),.flush_i(flush_i),.issueValid_i(issueValid_i[0]&&(issueUop_i[0].fuClass!=FU_MEMORY)),.issueUop_i(issueUop_i[0]),.sourceA_i(sourceA_i[0]),.sourceB_i(sourceB_i[0]),.csrReadData_i(csrReadData_i),.orderingReady_i(integerOrderingReady_i),.issueReady_o(pReady),.completionValid_o(pCV),.completionRobTag_o(pTag),.completionException_o(pEx),.completionCause_o(pCause),.completionValue_o(pValue),.writebackValid_o(pWV),.writebackPhys_o(pWP),.writebackData_o(pWD),.branchResolved_o(pBrResolved),.branchPc_o(pBrPc),.branchIsConditional_o(pBrConditional),.branchIsCall_o(pBrCall),.branchIsReturn_o(pBrReturn),.branchPredictorIndex_o(pBrIndex),.branchTaken_o(pBrTaken),.branchTarget_o(pBrTarget),.branchMispredicted_o(pBrMispredict),.branchRedirect_o(pBrRedirect),.csrValid_o(csrValid_o),.csrOp_o(csrOp_o),.csrAddr_o(csrAddr_o),.csrWriteData_o(csrWriteData_o),.completionReady_i(1'b1));
 OoOExecutionUnit secondary(.clk(clk),.rst(rst),.flush_i(flush_i),.issueValid_i(issueValid_i[1]),.issueUop_i(issueUop_i[1]),.sourceA_i(sourceA_i[1]),.sourceB_i(sourceB_i[1]),.csrReadData_i('0),.orderingReady_i(integerOrderingReady_i),.issueReady_o(sReady),.completionValid_o(sCV),.completionRobTag_o(sTag),.completionException_o(sEx),.completionCause_o(sCause),.completionValue_o(sValue),.writebackValid_o(sWV),.writebackPhys_o(sWP),.writebackData_o(sWD),.branchResolved_o(sBrResolved),.branchPc_o(sBrPc),.branchIsConditional_o(sBrConditional),.branchIsCall_o(sBrCall),.branchIsReturn_o(sBrReturn),.branchPredictorIndex_o(sBrIndex),.branchTaken_o(sBrTaken),.branchTarget_o(sBrTarget),.branchMispredicted_o(sBrMispredict),.branchRedirect_o(sBrRedirect),.csrValid_o(),.csrOp_o(),.csrAddr_o(),.csrWriteData_o(),.completionReady_i(1'b1));
 LoadStoreExecutionUnit memory(.clk(clk),.rst(rst),.flush_i(flush_i),.issueValid_i(issueValid_i[0]&&(issueUop_i[0].fuClass==FU_MEMORY)),.issueUop_i(issueUop_i[0]),.sourceA_i(sourceA_i[0]),.sourceB_i(sourceB_i[0]),.orderingReady_i(lsqIssueReady_i),.forwardValid_i(lsqForwardValid_i),.forwardData_i(lsqForwardData_i),.memoryPortReady_i(memoryPortReady_i),.memoryReadData_i(memoryReadData_i),.issueReady_o(mReady),.completionValid_o(mCV),.completionRobTag_o(mTag),.completionException_o(mEx),.completionCause_o(mCause),.completionValue_o(mValue),.writebackValid_o(mWV),.writebackPhys_o(mWP),.writebackData_o(mWD),.executeValid_o(lsuExecuteValid_o),.loadReadValid_o(lsuLoadReadValid_o),.isStore_o(lsuIsStore_o),.address_o(lsuAddress_o),.storeData_o(lsuStoreData_o),.memoryAccess_o(lsuMemoryAccess_o),.lsqTag_o(lsuTag_o),.completionReady_i(1'b1));
endmodule
