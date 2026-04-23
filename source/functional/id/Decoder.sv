module Decoder
    import TypesPkg::*;
#(
    parameter int INSN_W = INS_SIZE,
    parameter int REG_ADDR_W = REG_ADDR,
    parameter int IMM_W = WORD_SIZE
)
(
    input  logic [INSN_W-1:0]      insn,
    output logic                   registerWriteEnable,
    output logic                   dataWriteEnable,
    output wb_select_t             wbSelect,
    output branch_ctr_t            branchCtr,
    output alu_ctr_t               aluCtr,
    output mem_access_t            memCtr,
    output logic                   aluSrcASelect,
    output logic                   aluSrcBSelect,
    output logic                   useRs1,
    output logic                   useRs2,
    output logic [REG_ADDR_W-1:0]  rs1,
    output logic [REG_ADDR_W-1:0]  rs2,
    output logic [REG_ADDR_W-1:0]  rd,
    output logic [IMM_W-1:0]       immediate
);

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    always_comb begin
        opcode = insn[6:0];
        funct3 = insn[14:12];
        funct7 = insn[31:25];

        rs1 = insn[19:15];
        rs2 = insn[24:20];
        rd = insn[11:7];
        immediate = '0;

        registerWriteEnable = 1'b0;
        dataWriteEnable = 1'b0;
        wbSelect = WB_ALU;
        branchCtr = BR_NONE;
        aluCtr = ALU_ADD;
        memCtr = MEM_WORD;
        aluSrcASelect = 1'b0;
        aluSrcBSelect = 1'b0;
        useRs1 = 1'b0;
        useRs2 = 1'b0;

        unique case (opcode)
            7'b0110011: begin
                registerWriteEnable = 1'b1;
                wbSelect = WB_ALU;
                useRs1 = 1'b1;
                useRs2 = 1'b1;

                unique case ({funct7, funct3})
                    10'b0000000_000: aluCtr = ALU_ADD;
                    10'b0100000_000: aluCtr = ALU_SUB;
                    10'b0000000_001: aluCtr = ALU_SLL;
                    10'b0000000_010: aluCtr = ALU_SLT;
                    10'b0000000_011: aluCtr = ALU_SLTU;
                    10'b0000000_100: aluCtr = ALU_XOR;
                    10'b0000000_101: aluCtr = ALU_SRL;
                    10'b0100000_101: aluCtr = ALU_SRA;
                    10'b0000000_110: aluCtr = ALU_OR;
                    10'b0000000_111: aluCtr = ALU_AND;
                    default: registerWriteEnable = 1'b0;
                endcase
            end

            7'b0010011: begin
                registerWriteEnable = 1'b1;
                wbSelect = WB_ALU;
                aluSrcBSelect = 1'b1;
                useRs1 = 1'b1;
                immediate = {{20{insn[31]}}, insn[31:20]};

                unique case (funct3)
                    3'b000: aluCtr = ALU_ADD;
                    3'b010: aluCtr = ALU_SLT;
                    3'b011: aluCtr = ALU_SLTU;
                    3'b100: aluCtr = ALU_XOR;
                    3'b110: aluCtr = ALU_OR;
                    3'b111: aluCtr = ALU_AND;
                    3'b001: begin
                        if (funct7 == 7'b0000000) begin
                            aluCtr = ALU_SLL;
                            immediate = {27'd0, insn[24:20]};
                        end else begin
                            registerWriteEnable = 1'b0;
                        end
                    end
                    3'b101: begin
                        immediate = {27'd0, insn[24:20]};
                        if (funct7 == 7'b0000000) begin
                            aluCtr = ALU_SRL;
                        end else if (funct7 == 7'b0100000) begin
                            aluCtr = ALU_SRA;
                        end else begin
                            registerWriteEnable = 1'b0;
                        end
                    end
                    default: registerWriteEnable = 1'b0;
                endcase
            end

            7'b0000011: begin
                registerWriteEnable = 1'b1;
                wbSelect = WB_MEM;
                aluCtr = ALU_ADD;
                aluSrcBSelect = 1'b1;
                useRs1 = 1'b1;
                immediate = {{20{insn[31]}}, insn[31:20]};

                unique case (funct3)
                    3'b000: memCtr = MEM_BYTE;
                    3'b001: memCtr = MEM_HALF;
                    3'b010: memCtr = MEM_WORD;
                    3'b100: memCtr = MEM_BYTE_U;
                    3'b101: memCtr = MEM_HALF_U;
                    default: registerWriteEnable = 1'b0;
                endcase
            end

            7'b0100011: begin
                dataWriteEnable = 1'b1;
                aluCtr = ALU_ADD;
                aluSrcBSelect = 1'b1;
                useRs1 = 1'b1;
                useRs2 = 1'b1;
                immediate = {{20{insn[31]}}, insn[31:25], insn[11:7]};

                unique case (funct3)
                    3'b000: memCtr = MEM_BYTE;
                    3'b001: memCtr = MEM_HALF;
                    3'b010: memCtr = MEM_WORD;
                    default: dataWriteEnable = 1'b0;
                endcase
            end

            7'b1100011: begin
                aluCtr = ALU_ADD;
                aluSrcASelect = 1'b1;
                aluSrcBSelect = 1'b1;
                useRs1 = 1'b1;
                useRs2 = 1'b1;
                immediate = {{19{insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};

                unique case (funct3)
                    3'b000: branchCtr = BR_BEQ;
                    3'b001: branchCtr = BR_BNE;
                    3'b100: branchCtr = BR_BLT;
                    3'b101: branchCtr = BR_BGE;
                    3'b110: branchCtr = BR_BLTU;
                    3'b111: branchCtr = BR_BGEU;
                    default: branchCtr = BR_NONE;
                endcase
            end

            7'b1101111: begin
                registerWriteEnable = 1'b1;
                wbSelect = WB_PC4;
                branchCtr = BR_JAL;
                aluCtr = ALU_ADD;
                aluSrcASelect = 1'b1;
                aluSrcBSelect = 1'b1;
                immediate = {{11{insn[31]}}, insn[31], insn[19:12], insn[20], insn[30:21], 1'b0};
            end

            7'b1100111: begin
                if (funct3 == 3'b000) begin
                    registerWriteEnable = 1'b1;
                    wbSelect = WB_PC4;
                    branchCtr = BR_JALR;
                    aluCtr = ALU_ADD;
                    aluSrcBSelect = 1'b1;
                    useRs1 = 1'b1;
                    immediate = {{20{insn[31]}}, insn[31:20]};
                end
            end

            7'b0110111: begin
                registerWriteEnable = 1'b1;
                wbSelect = WB_IMM;
                immediate = {insn[31:12], 12'b0};
            end

            7'b0010111: begin
                registerWriteEnable = 1'b1;
                wbSelect = WB_ALU;
                aluCtr = ALU_ADD;
                aluSrcASelect = 1'b1;
                aluSrcBSelect = 1'b1;
                immediate = {insn[31:12], 12'b0};
            end

            default: begin
            end
        endcase
    end
endmodule
