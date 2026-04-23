module PC
    import TypesPkg::*;
#(
    // Program-counter width, reset address, and sequential increment.
    parameter int ADDR_W = WORD_SIZE,
    parameter logic [ADDR_W-1:0] RESET_PC = RESET_VECTOR,
    parameter logic [ADDR_W-1:0] PC_INCREMENT = 32'd4
)
(
    // Active-low reset matches the rest of the project pipeline registers.
    input  logic              clk,
    input  logic              rst,
    // Branch/jump redirect from the execute stage.
    input  logic              jump_enable,
    // wrEnable is deasserted during load-use stalls to freeze fetch.
    input  logic              wrEnable,
    input  logic [ADDR_W-1:0] jump_address,
    output logic [ADDR_W-1:0] pc_address_out
);

    logic [ADDR_W-1:0] pc;

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            pc <= RESET_PC;
        end else if (wrEnable) begin
            // Redirect has priority over the sequential PC path when a branch
            // or jump resolves in EX.
            if (jump_enable) begin
                pc <= jump_address;
            end else begin
                pc <= pc + PC_INCREMENT;
            end
        end
    end

    // Expose the current fetch address combinationally to instruction memory.
    assign pc_address_out = pc;

endmodule
