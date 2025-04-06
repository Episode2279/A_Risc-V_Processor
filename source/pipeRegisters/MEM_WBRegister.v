`include "Types.v"

module IF_IDRegister(
    input logic clk,
    input logic rst,
);

    always*(posedge clk or negedge rst)begin
        if(~rst)begin
            
        end
        else begin
            if(~stall)begin
                
            end
        end
    end

endmodule