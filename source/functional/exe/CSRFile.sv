module CSRFile
    import TypesPkg::*;
#(
    parameter logic [WORD_SIZE-1:0] RESET_VALUE = '0,
    parameter logic [WORD_SIZE-1:0] HART_ID = '0,
    parameter logic [WORD_SIZE-1:0] MISA_VALUE = 32'h4000_0100
)
(
    input  logic      clk,
    input  logic      rst,
    input  logic      retire_i,
    input  logic      csrValid_i,
    input  csr_op_t   csrOp_i,
    input  csr_addr_t csrAddr_i,
    input  word_t     csrWriteData_i,
    output word_t     csrReadData_o
);

    localparam csr_addr_t CSR_CYCLE    = 12'hC00;
    localparam csr_addr_t CSR_TIME     = 12'hC01;
    localparam csr_addr_t CSR_INSTRET  = 12'hC02;
    localparam csr_addr_t CSR_CYCLEH   = 12'hC80;
    localparam csr_addr_t CSR_TIMEH    = 12'hC81;
    localparam csr_addr_t CSR_INSTRETH = 12'hC82;
    localparam csr_addr_t CSR_MSTATUS  = 12'h300;
    localparam csr_addr_t CSR_MISA     = 12'h301;
    localparam csr_addr_t CSR_MIE      = 12'h304;
    localparam csr_addr_t CSR_MTVEC    = 12'h305;
    localparam csr_addr_t CSR_MSCRATCH = 12'h340;
    localparam csr_addr_t CSR_MEPC     = 12'h341;
    localparam csr_addr_t CSR_MCAUSE   = 12'h342;
    localparam csr_addr_t CSR_MTVAL    = 12'h343;
    localparam csr_addr_t CSR_MIP      = 12'h344;
    localparam csr_addr_t CSR_MCYCLE   = 12'hB00;
    localparam csr_addr_t CSR_MINSTRET = 12'hB02;
    localparam csr_addr_t CSR_MCYCLEH  = 12'hB80;
    localparam csr_addr_t CSR_MINSTRETH = 12'hB82;
    localparam csr_addr_t CSR_MVENDORID = 12'hF11;
    localparam csr_addr_t CSR_MARCHID   = 12'hF12;
    localparam csr_addr_t CSR_MIMPID    = 12'hF13;
    localparam csr_addr_t CSR_MHARTID   = 12'hF14;

    word_t mstatus;
    word_t mie;
    word_t mtvec;
    word_t mscratch;
    word_t mepc;
    word_t mcause;
    word_t mtval;
    word_t mip;
    logic [63:0] mcycle;
    logic [63:0] minstret;
    word_t currentValue;
    word_t nextValue;

    always_comb begin
        unique case (csrAddr_i)
            CSR_CYCLE, CSR_TIME, CSR_MCYCLE:       currentValue = mcycle[31:0];
            CSR_CYCLEH, CSR_TIMEH, CSR_MCYCLEH:    currentValue = mcycle[63:32];
            CSR_INSTRET, CSR_MINSTRET:             currentValue = minstret[31:0];
            CSR_INSTRETH, CSR_MINSTRETH:           currentValue = minstret[63:32];
            CSR_MSTATUS:                           currentValue = mstatus;
            CSR_MISA:                              currentValue = MISA_VALUE;
            CSR_MIE:                               currentValue = mie;
            CSR_MTVEC:                             currentValue = mtvec;
            CSR_MSCRATCH:                          currentValue = mscratch;
            CSR_MEPC:                              currentValue = mepc;
            CSR_MCAUSE:                            currentValue = mcause;
            CSR_MTVAL:                             currentValue = mtval;
            CSR_MIP:                               currentValue = mip;
            CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID: currentValue = '0;
            CSR_MHARTID:                           currentValue = HART_ID;
            default:                               currentValue = '0;
        endcase

        unique case (csrOp_i)
            CSR_RW:  nextValue = csrWriteData_i;
            CSR_RS:  nextValue = currentValue | csrWriteData_i;
            CSR_RC:  nextValue = currentValue & ~csrWriteData_i;
            default: nextValue = currentValue;
        endcase
    end

    assign csrReadData_o = currentValue;

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            mstatus <= RESET_VALUE;
            mie <= RESET_VALUE;
            mtvec <= RESET_VALUE;
            mscratch <= RESET_VALUE;
            mepc <= RESET_VALUE;
            mcause <= RESET_VALUE;
            mtval <= RESET_VALUE;
            mip <= RESET_VALUE;
            mcycle <= '0;
            minstret <= '0;
        end else begin
            mcycle <= mcycle + 64'd1;
            if (retire_i) begin
                minstret <= minstret + 64'd1;
            end

            if (csrValid_i && (csrOp_i != CSR_NONE)) begin
                unique case (csrAddr_i)
                    CSR_MSTATUS:  mstatus <= nextValue;
                    CSR_MIE:      mie <= nextValue;
                    CSR_MTVEC:    mtvec <= nextValue;
                    CSR_MSCRATCH: mscratch <= nextValue;
                    CSR_MEPC:     mepc <= nextValue;
                    CSR_MCAUSE:   mcause <= nextValue;
                    CSR_MTVAL:    mtval <= nextValue;
                    CSR_MIP:      mip <= nextValue;
                    CSR_MCYCLE, CSR_CYCLE, CSR_TIME:       mcycle[31:0] <= nextValue;
                    CSR_MCYCLEH, CSR_CYCLEH, CSR_TIMEH:    mcycle[63:32] <= nextValue;
                    CSR_MINSTRET, CSR_INSTRET:             minstret[31:0] <= nextValue;
                    CSR_MINSTRETH, CSR_INSTRETH:           minstret[63:32] <= nextValue;
                    default: begin
                    end
                endcase
            end
        end
    end

endmodule
