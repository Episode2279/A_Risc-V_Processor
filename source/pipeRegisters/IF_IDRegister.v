`include "Types.v"

module IF_IDRegister(
    input logic clk,
    input logic rst,

    input `instruction instruction_i,
    input `instructionAddrPath pc_i,
    input logic stall,

    input `instruction instruction_o,
    input `instructionAddrPath pc_o
);

    always*(posedge clk or negedge rst)begin
        if(~rst)begin
            instruction_o<=RESET_VECTOR;
            pc_o<=RESET_VECTOR;
        end
        else begin
            if(~stall)begin
                instruction_o<=instruction_i;
                pc_o<=pc_i;
            end
        end
    end

endmodule