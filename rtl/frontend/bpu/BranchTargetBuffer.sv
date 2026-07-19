module BranchTargetBuffer import TypesPkg::*; #(
 parameter int ENTRIES=128, parameter int WAYS=2,
 parameter int SETS=ENTRIES/WAYS, parameter int INDEX_W=$clog2(SETS),
 parameter int TAG_W=WORD_SIZE-INDEX_W-2)(
 input logic clk,rst, input instruction_addr_t queryPc_i, output logic hit_o,
 output instruction_addr_t target_o, input instruction_addr_t queryPc1_i,
 output logic hit1_o, output instruction_addr_t target1_o,
 input instruction_addr_t hintPc_i,hintPc1_i,
 output logic hintConditional_o,hintControl_o,
 output logic hintConditional1_o,hintControl1_o,
 input logic updateValid_i, input instruction_addr_t updatePc_i,
 input logic updateIsConditional_i,input logic updateTaken_i,
 input instruction_addr_t updateTarget_i);
 logic validTable[SETS][WAYS]; logic [TAG_W-1:0] tagTable[SETS][WAYS];
 logic conditionalTable[SETS][WAYS];
 instruction_addr_t targetTable[SETS][WAYS]; logic replaceWay[SETS];
 logic [INDEX_W-1:0] qSet,qSet1,hSet,hSet1,uSet;
 logic [TAG_W-1:0] qTag,qTag1,hTag,hTag1,uTag;
 logic updateHit0,updateHit1,selectedWay; integer setIndex,combWay,resetWay;
 assign qSet=queryPc_i[INDEX_W+1:2]; assign qSet1=queryPc1_i[INDEX_W+1:2];
 assign uSet=updatePc_i[INDEX_W+1:2];
 assign qTag=queryPc_i[WORD_SIZE-1:INDEX_W+2];
 assign qTag1=queryPc1_i[WORD_SIZE-1:INDEX_W+2];
 assign hSet=hintPc_i[INDEX_W+1:2];
 assign hSet1=hintPc1_i[INDEX_W+1:2];
 assign hTag=hintPc_i[WORD_SIZE-1:INDEX_W+2];
 assign hTag1=hintPc1_i[WORD_SIZE-1:INDEX_W+2];
 assign uTag=updatePc_i[WORD_SIZE-1:INDEX_W+2];
 always_comb begin
  hit_o=1'b0; target_o='0; hit1_o=1'b0; target1_o='0;
  hintConditional_o=1'b0; hintControl_o=1'b0;
  hintConditional1_o=1'b0; hintControl1_o=1'b0;
  for(combWay=0;combWay<WAYS;combWay=combWay+1) begin
   if(validTable[qSet][combWay]&&(tagTable[qSet][combWay]==qTag)) begin hit_o=1'b1; target_o=targetTable[qSet][combWay]; end
   if(validTable[qSet1][combWay]&&(tagTable[qSet1][combWay]==qTag1)) begin hit1_o=1'b1; target1_o=targetTable[qSet1][combWay]; end
   if(validTable[hSet][combWay]&&(tagTable[hSet][combWay]==hTag)) begin
    hintControl_o=1'b1; hintConditional_o=conditionalTable[hSet][combWay];
   end
   if(validTable[hSet1][combWay]&&(tagTable[hSet1][combWay]==hTag1)) begin
    hintControl1_o=1'b1; hintConditional1_o=conditionalTable[hSet1][combWay];
   end
  end
  updateHit0=validTable[uSet][0]&&(tagTable[uSet][0]==uTag);
  updateHit1=validTable[uSet][1]&&(tagTable[uSet][1]==uTag);
  if(updateHit0) selectedWay=1'b0; else if(updateHit1) selectedWay=1'b1;
  else if(!validTable[uSet][0]) selectedWay=1'b0;
  else if(!validTable[uSet][1]) selectedWay=1'b1; else selectedWay=replaceWay[uSet];
 end
 always_ff @(posedge clk or negedge rst) begin
  if(!rst) begin
   for(setIndex=0;setIndex<SETS;setIndex=setIndex+1) begin
    replaceWay[setIndex]=1'b0;
     for(resetWay=0;resetWay<WAYS;resetWay=resetWay+1) begin validTable[setIndex][resetWay]=1'b0; tagTable[setIndex][resetWay]='0; targetTable[setIndex][resetWay]='0; conditionalTable[setIndex][resetWay]=1'b0; end
   end
  end else if(updateValid_i&&updateTaken_i) begin
    validTable[uSet][selectedWay]<=1'b1; tagTable[uSet][selectedWay]<=uTag;
    targetTable[uSet][selectedWay]<=updateTarget_i;
    conditionalTable[uSet][selectedWay]<=updateIsConditional_i;
    replaceWay[uSet]<=~selectedWay;
  end
 end
endmodule
