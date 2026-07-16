module ReturnAddressStack import TypesPkg::*; #(parameter int DEPTH=8) (
 input logic clk,rst, input logic speculateValid_i,speculateCall_i,speculateReturn_i,
 input instruction_addr_t speculateReturnAddress_i,
 input logic speculateValid1_i,speculateCall1_i,speculateReturn1_i,
 input instruction_addr_t speculateReturnAddress1_i,
 input logic resolveValid_i,resolveCall_i,resolveReturn_i,mispredict_i,
 input instruction_addr_t resolveReturnAddress_i,
 output logic valid_o, output instruction_addr_t target_o,
 output logic valid1_o, output instruction_addr_t target1_o);
 localparam int PTR_W=$clog2(DEPTH+1); localparam int IDX_W=$clog2(DEPTH);
 instruction_addr_t committed[DEPTH], speculative[DEPTH];
 logic [PTR_W-1:0] committedSp,speculativeSp; integer i;
 logic [IDX_W-1:0] speculativeTopIndex;
 assign valid_o=speculativeSp!=0;
 assign speculativeTopIndex = speculativeSp[IDX_W-1:0]-1'b1;
 assign target_o=valid_o?speculative[speculativeTopIndex]:'0;
 always_comb begin
  valid1_o=valid_o; target1_o=target_o;
  if(speculateValid_i&&speculateCall_i) begin valid1_o=1'b1; target1_o=speculateReturnAddress_i; end
  else if(speculateValid_i&&speculateReturn_i) begin
   valid1_o=speculativeSp>1;
   target1_o=(speculativeSp>1)?speculative[speculativeTopIndex-1'b1]:'0;
  end
 end
 always_ff @(posedge clk or negedge rst) begin
  if(!rst) begin committedSp<=0; speculativeSp<=0; for(i=0;i<DEPTH;i=i+1) begin committed[i]<='0; speculative[i]<='0; end end
  else begin
   if(resolveValid_i&&resolveCall_i&&committedSp<PTR_W'(DEPTH)) begin committed[committedSp[IDX_W-1:0]]<=resolveReturnAddress_i; committedSp<=committedSp+1'b1; end
   else if(resolveValid_i&&resolveReturn_i&&committedSp!=0) committedSp<=committedSp-1'b1;
   if(mispredict_i) begin
    for(i=0;i<DEPTH;i=i+1) speculative[i]<=committed[i];
    if(resolveCall_i && committedSp<PTR_W'(DEPTH)) begin
     speculativeSp<=committedSp+1'b1;
     speculative[committedSp[IDX_W-1:0]]<=resolveReturnAddress_i;
    end else if(resolveReturn_i && committedSp!=0) speculativeSp<=committedSp-1'b1;
    else speculativeSp<=committedSp;
   end else if(speculateValid_i&&speculateCall_i&&speculateValid1_i&&speculateCall1_i&&speculativeSp<PTR_W'(DEPTH-1)) begin
    speculative[speculativeSp[IDX_W-1:0]]<=speculateReturnAddress_i;
    speculative[speculativeSp[IDX_W-1:0]+1'b1]<=speculateReturnAddress1_i;
    speculativeSp<=speculativeSp+PTR_W'(2);
   end else if(speculateValid_i&&speculateCall_i&&speculateValid1_i&&speculateReturn1_i) begin
    speculativeSp<=speculativeSp;
   end else if(speculateValid_i&&speculateReturn_i&&speculateValid1_i&&speculateCall1_i) begin
    if(speculativeSp!=0) speculative[speculativeTopIndex]<=speculateReturnAddress1_i;
    else begin speculative[0]<=speculateReturnAddress1_i; speculativeSp<=1; end
   end else if(speculateValid_i&&speculateReturn_i&&speculateValid1_i&&speculateReturn1_i) begin
    if(speculativeSp>1) speculativeSp<=speculativeSp-PTR_W'(2); else speculativeSp<=0;
   end else if(speculateValid_i&&speculateCall_i&&speculativeSp<PTR_W'(DEPTH)) begin
    speculative[speculativeSp[IDX_W-1:0]]<=speculateReturnAddress_i; speculativeSp<=speculativeSp+1'b1;
   end else if(speculateValid_i&&speculateReturn_i&&speculativeSp!=0) speculativeSp<=speculativeSp-1'b1;
   else if(speculateValid1_i&&speculateCall1_i&&speculativeSp<PTR_W'(DEPTH)) begin
    speculative[speculativeSp[IDX_W-1:0]]<=speculateReturnAddress1_i; speculativeSp<=speculativeSp+1'b1;
   end else if(speculateValid1_i&&speculateReturn1_i&&speculativeSp!=0) speculativeSp<=speculativeSp-1'b1;
  end
 end
endmodule
