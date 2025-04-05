`include "Types.v"
module PC(
    input logic clk,
    input logic rst,
    
    input logic jump_enable,
    input `instructionAddrPath jump_address,
    
    output `instructionAddrPath pc_address_out
);

    `instructionAddrPath pc;
    always @(posedge clk or negedge rst) begin
        if(~rst) begin
            pc <= `RESET_VECTOR;
        end
        else if(jump_enable) begin
            pc<= jump_address;
        end
        else begin
            pc<=pc+4;
        end
    end

    assign pc_address_out = pc;

endmodule