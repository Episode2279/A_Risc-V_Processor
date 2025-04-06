`include "Types.v"

module IF_IDRegister(
    input logic clk,
    input logic rst,

    input `instruction instruction_if,
    input `instructionAddrPath pc_if,
    input logic stall,

    output `instruction instruction_o,
    output `instructionAddrPath pc_o
);

    always*(posedge clk or negedge rst)begin
        if(~rst)begin
            instruction_o<=`RESET_VECTOR;
            pc_o<=`RESET_VECTOR;
        end
        else begin
            if(~stall)begin
                instruction_o<=instruction_if;
                pc_o<=pc_if;
            end
        end
    end

endmodule