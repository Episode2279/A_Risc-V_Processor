`include "Types.v"

module register(
    input logic clk,
    input logic rst,

    input logic wrEnable,

    input logic[`WORD_SIZE-1:0] regIn,

    output logic[`WORD_SIZE-1:0] regOut
);

always@(posedge clk or negedge rst) begin
    if(~rst) regOut<=0;
    else if(wrEnable)regOut<=regIn;
end

endmodule