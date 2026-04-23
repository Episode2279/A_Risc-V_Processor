module WritebackMux
    import TypesPkg::*;
#(
    // Widths and PC increment follow the core configuration.
    parameter int DATA_W = WORD_SIZE,
    parameter int ADDR_W = WORD_SIZE,
    parameter logic [ADDR_W-1:0] PC_INCREMENT = 32'd4
)
(
    // Selects which pipeline result becomes the architectural rd value.
    input  wb_select_t         wbSelect,
    input  logic [ADDR_W-1:0]  pc,
    input  logic [DATA_W-1:0]  aluData,
    input  logic [DATA_W-1:0]  memData,
    input  logic [ADDR_W-1:0]  immediate,
    input  logic [DATA_W-1:0]  csrData,
    output logic [DATA_W-1:0]  result_o
);

    always_comb begin
        // This mux is shared by the real WB stage and by the forwarding path
        // when MEM-stage results must be bypassed into EX.
        unique case (wbSelect)
            WB_ALU: result_o = aluData;
            WB_MEM: result_o = memData;
            WB_PC4: result_o = pc + PC_INCREMENT;
            WB_IMM: result_o = immediate;
            WB_CSR: result_o = csrData;
            default: result_o = '0;
        endcase
    end

endmodule
