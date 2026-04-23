module PC
    import TypesPkg::*;
#(
    parameter int ADDR_W = WORD_SIZE,
    parameter logic [ADDR_W-1:0] RESET_PC = RESET_VECTOR,
    parameter logic [ADDR_W-1:0] PC_INCREMENT = 32'd4
)
(
    input  logic              clk,
    input  logic              rst,
    input  logic              jump_enable,
    input  logic              wrEnable,
    input  logic [ADDR_W-1:0] jump_address,
    output logic [ADDR_W-1:0] pc_address_out
);

    logic [ADDR_W-1:0] pc;

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            pc <= RESET_PC;
        end else if (wrEnable) begin
            if (jump_enable) begin
                pc <= jump_address;
            end else begin
                pc <= pc + PC_INCREMENT;
            end
        end
    end

    assign pc_address_out = pc;

endmodule
