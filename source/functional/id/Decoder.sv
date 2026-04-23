module Decoder
    import TypesPkg::*;
#(
    // Decode widths are kept configurable, but the default package values map
    // directly to RV32I instruction and register encodings.
    parameter int INSN_W = INS_SIZE,
    parameter int REG_ADDR_W = REG_ADDR,
    parameter int IMM_W = WORD_SIZE
)
(
    // Raw fetched instruction from IF/ID.
    input  logic [INSN_W-1:0]      insn,
    // Architectural side effects and writeback-source selection.
    output logic                   registerWriteEnable,
    output logic                   dataWriteEnable,
    output wb_select_t             wbSelect,
    // CSR controls are active only for SYSTEM CSR instructions.
    output csr_op_t                csrOp,
    output csr_addr_t              csrAddr,
    output logic                   csrUseImm,
    output logic [IMM_W-1:0]       csrImm,
    // Execute, memory, and source-operand controls.
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
        // RV32I instruction field map:
        //   opcode = insn[6:0]
        //     Primary instruction class. This selects the broad format such as
        //     R-type ALU, I-type ALU/load/JALR/CSR, S-type store, B-type branch,
        //     U-type LUI/AUIPC, or J-type JAL.
        //   rd     = insn[11:7]
        //     Destination register for instructions that write an integer reg.
        //   funct3 = insn[14:12]
        //     Secondary operation selector. It distinguishes ADDI/SLTI/ORI,
        //     LB/LH/LW/LBU/LHU, SB/SH/SW, branch condition, and CSR operation.
        //   rs1    = insn[19:15]
        //     First source register, or zimm[4:0] for immediate CSR forms.
        //   rs2    = insn[24:20]
        //     Second source register for R/S/B formats, or shamt for shifts.
        //   funct7 = insn[31:25]
        //     Tertiary selector used mainly by R-type and shift-immediate ops
        //     to distinguish ADD/SUB and SRL/SRA.
        //
        // Fields are extracted unconditionally. For formats that do not use a
        // field, the downstream useRs1/useRs2/write-enable controls prevent it
        // from creating false hazards or architectural side effects.
        opcode = insn[6:0];
        funct3 = insn[14:12];
        funct7 = insn[31:25];

        rs1 = insn[19:15];
        rs2 = insn[24:20];
        rd = insn[11:7];
        immediate = '0;

        // Safe defaults describe a bubble/NOP-like instruction. Each opcode
        // enables only the side effects it really needs.
        registerWriteEnable = 1'b0;
        dataWriteEnable = 1'b0;
        wbSelect = WB_ALU;
        csrOp = CSR_NONE;
        csrAddr = insn[31:20];
        csrUseImm = 1'b0;
        csrImm = {{(IMM_W-5){1'b0}}, insn[19:15]};
        branchCtr = BR_NONE;
        aluCtr = ALU_ADD;
        memCtr = MEM_WORD;
        aluSrcASelect = 1'b0;
        aluSrcBSelect = 1'b0;
        useRs1 = 1'b0;
        useRs2 = 1'b0;

        unique case (opcode)
            7'b0110011: begin
                // opcode 0110011: R-type integer register-register operations.
                // Format:
                //   [31:25] funct7, [24:20] rs2, [19:15] rs1,
                //   [14:12] funct3, [11:7] rd, [6:0] opcode
                // Meaning:
                //   rd = rs1 OP rs2
                // funct3 selects the ALU family and funct7 refines variants:
                //   funct3=000, funct7=0000000 -> ADD
                //   funct3=000, funct7=0100000 -> SUB
                //   funct3=101, funct7=0000000 -> SRL
                //   funct3=101, funct7=0100000 -> SRA
                // Other R-type ops use funct7=0000000 in RV32I.
                registerWriteEnable = 1'b1;
                wbSelect = WB_ALU;
                useRs1 = 1'b1;
                useRs2 = 1'b1;

                unique case ({funct7, funct3})
                    10'b0000000_000: aluCtr = ALU_ADD;  // ADD
                    10'b0100000_000: aluCtr = ALU_SUB;  // SUB
                    10'b0000000_001: aluCtr = ALU_SLL;  // SLL
                    10'b0000000_010: aluCtr = ALU_SLT;  // SLT, signed compare
                    10'b0000000_011: aluCtr = ALU_SLTU; // SLTU, unsigned compare
                    10'b0000000_100: aluCtr = ALU_XOR;  // XOR
                    10'b0000000_101: aluCtr = ALU_SRL;  // SRL, logical right shift
                    10'b0100000_101: aluCtr = ALU_SRA;  // SRA, arithmetic right shift
                    10'b0000000_110: aluCtr = ALU_OR;   // OR
                    10'b0000000_111: aluCtr = ALU_AND;  // AND
                    default: registerWriteEnable = 1'b0;
                endcase
            end

            7'b0010011: begin
                // opcode 0010011: I-type integer immediate operations.
                // Format:
                //   [31:20] imm[11:0], [19:15] rs1, [14:12] funct3,
                //   [11:7] rd, [6:0] opcode
                // Meaning:
                //   rd = rs1 OP sign_extend(imm)
                // funct3 selects ADDI/SLTI/SLTIU/XORI/ORI/ANDI. For shift
                // immediates, rs2 field bits [24:20] become shamt[4:0], and
                // funct7 distinguishes SRLI from SRAI.
                registerWriteEnable = 1'b1;
                wbSelect = WB_ALU;
                aluSrcBSelect = 1'b1;
                useRs1 = 1'b1;
                immediate = {{20{insn[31]}}, insn[31:20]};

                unique case (funct3)
                    3'b000: aluCtr = ALU_ADD;  // ADDI
                    3'b010: aluCtr = ALU_SLT;  // SLTI
                    3'b011: aluCtr = ALU_SLTU; // SLTIU
                    3'b100: aluCtr = ALU_XOR;  // XORI
                    3'b110: aluCtr = ALU_OR;   // ORI
                    3'b111: aluCtr = ALU_AND;  // ANDI
                    3'b001: begin
                        // SLLI: funct7 must be 0000000 in RV32I.
                        if (funct7 == 7'b0000000) begin
                            aluCtr = ALU_SLL;
                            immediate = {27'd0, insn[24:20]};
                        end else begin
                            registerWriteEnable = 1'b0;
                        end
                    end
                    3'b101: begin
                        // SRLI/SRAI share funct3=101. funct7 selects logical
                        // versus arithmetic right shift.
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
                // opcode 0000011: I-type loads.
                // Format:
                //   [31:20] imm[11:0], [19:15] rs1, [14:12] funct3,
                //   [11:7] rd, [6:0] opcode
                // Meaning:
                //   rd = memory[rs1 + sign_extend(imm)]
                // funct3 selects size and signed/unsigned extension:
                //   000 LB, 001 LH, 010 LW, 100 LBU, 101 LHU.
                registerWriteEnable = 1'b1;
                wbSelect = WB_MEM;
                aluCtr = ALU_ADD;
                aluSrcBSelect = 1'b1;
                useRs1 = 1'b1;
                immediate = {{20{insn[31]}}, insn[31:20]};

                unique case (funct3)
                    3'b000: memCtr = MEM_BYTE;   // LB, sign-extend byte
                    3'b001: memCtr = MEM_HALF;   // LH, sign-extend halfword
                    3'b010: memCtr = MEM_WORD;   // LW
                    3'b100: memCtr = MEM_BYTE_U; // LBU, zero-extend byte
                    3'b101: memCtr = MEM_HALF_U; // LHU, zero-extend halfword
                    default: registerWriteEnable = 1'b0;
                endcase
            end

            7'b0100011: begin
                // opcode 0100011: S-type stores.
                // Format:
                //   [31:25] imm[11:5], [24:20] rs2, [19:15] rs1,
                //   [14:12] funct3, [11:7] imm[4:0], [6:0] opcode
                // Meaning:
                //   memory[rs1 + sign_extend(imm)] = rs2 selected byte lanes
                // funct3 selects store width:
                //   000 SB, 001 SH, 010 SW.
                dataWriteEnable = 1'b1;
                aluCtr = ALU_ADD;
                aluSrcBSelect = 1'b1;
                useRs1 = 1'b1;
                useRs2 = 1'b1;
                immediate = {{20{insn[31]}}, insn[31:25], insn[11:7]};

                unique case (funct3)
                    3'b000: memCtr = MEM_BYTE; // SB
                    3'b001: memCtr = MEM_HALF; // SH
                    3'b010: memCtr = MEM_WORD; // SW
                    default: dataWriteEnable = 1'b0;
                endcase
            end

            7'b1100011: begin
                // opcode 1100011: B-type conditional branches.
                // Format:
                //   [31] imm[12], [30:25] imm[10:5], [24:20] rs2,
                //   [19:15] rs1, [14:12] funct3, [11:8] imm[4:1],
                //   [7] imm[11], [6:0] opcode
                // Meaning:
                //   if branch_condition(rs1, rs2) pc = pc + sign_extend(imm)
                // funct3 selects the comparison:
                //   000 BEQ, 001 BNE, 100 BLT, 101 BGE, 110 BLTU, 111 BGEU.
                // The low immediate bit is hardwired to 0 because branch
                // targets are 2-byte aligned by the ISA encoding.
                aluCtr = ALU_ADD;
                aluSrcASelect = 1'b1;
                aluSrcBSelect = 1'b1;
                useRs1 = 1'b1;
                useRs2 = 1'b1;
                immediate = {{19{insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};

                unique case (funct3)
                    3'b000: branchCtr = BR_BEQ;  // Equal
                    3'b001: branchCtr = BR_BNE;  // Not equal
                    3'b100: branchCtr = BR_BLT;  // Signed less-than
                    3'b101: branchCtr = BR_BGE;  // Signed greater/equal
                    3'b110: branchCtr = BR_BLTU; // Unsigned less-than
                    3'b111: branchCtr = BR_BGEU; // Unsigned greater/equal
                    default: branchCtr = BR_NONE;
                endcase
            end

            7'b1101111: begin
                // opcode 1101111: J-type JAL.
                // Format:
                //   [31] imm[20], [30:21] imm[10:1], [20] imm[11],
                //   [19:12] imm[19:12], [11:7] rd, [6:0] opcode
                // Meaning:
                //   rd = pc + 4; pc = pc + sign_extend(imm)
                // The encoded immediate is shifted left by one through the
                // appended 1'b0 bit, matching the ISA's 2-byte target alignment.
                registerWriteEnable = 1'b1;
                wbSelect = WB_PC4;
                branchCtr = BR_JAL;
                aluCtr = ALU_ADD;
                aluSrcASelect = 1'b1;
                aluSrcBSelect = 1'b1;
                immediate = {{11{insn[31]}}, insn[31], insn[19:12], insn[20], insn[30:21], 1'b0};
            end

            7'b1100111: begin
                // opcode 1100111: I-type JALR.
                // Format:
                //   [31:20] imm[11:0], [19:15] rs1, [14:12] funct3=000,
                //   [11:7] rd, [6:0] opcode
                // Meaning:
                //   rd = pc + 4; pc = (rs1 + sign_extend(imm)) & ~1
                // funct3 must be 000 for valid RV32I JALR.
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
                // opcode 0110111: U-type LUI.
                // Format:
                //   [31:12] imm[31:12], [11:7] rd, [6:0] opcode
                // Meaning:
                //   rd = imm[31:12] << 12
                // No source registers are read.
                registerWriteEnable = 1'b1;
                wbSelect = WB_IMM;
                immediate = {insn[31:12], 12'b0};
            end

            7'b0010111: begin
                // opcode 0010111: U-type AUIPC.
                // Format:
                //   [31:12] imm[31:12], [11:7] rd, [6:0] opcode
                // Meaning:
                //   rd = pc + (imm[31:12] << 12)
                // The ALU uses PC as source A and the U-immediate as source B.
                registerWriteEnable = 1'b1;
                wbSelect = WB_ALU;
                aluCtr = ALU_ADD;
                aluSrcASelect = 1'b1;
                aluSrcBSelect = 1'b1;
                immediate = {insn[31:12], 12'b0};
            end

            7'b1110011: begin
                // opcode 1110011: SYSTEM/CSR instructions.
                // This decoder implements the Zicsr CSR forms used by tests:
                //   [31:20] csr, [19:15] rs1 or zimm, [14:12] funct3,
                //   [11:7] rd, [6:0] opcode
                // Meaning:
                //   rd gets the old CSR value when rd != x0. The CSR may be
                //   overwritten, bit-set, or bit-cleared based on funct3.
                // funct3 selects:
                //   001 CSRRW, 010 CSRRS, 011 CSRRC,
                //   101 CSRRWI, 110 CSRRSI, 111 CSRRCI.
                wbSelect = WB_CSR;
                registerWriteEnable = (rd != '0);
                immediate = '0;

                unique case (funct3)
                    3'b001: begin
                        // CSRRW: always write rs1 value to CSR.
                        csrOp = CSR_RW;
                        useRs1 = 1'b1;
                    end
                    3'b010: begin
                        // CSRRS with rs1=x0 is a pure CSR read.
                        csrOp = (rs1 == '0) ? CSR_NONE : CSR_RS;
                        useRs1 = (rs1 != '0);
                    end
                    3'b011: begin
                        // CSRRC with rs1=x0 is a pure CSR read.
                        csrOp = (rs1 == '0) ? CSR_NONE : CSR_RC;
                        useRs1 = (rs1 != '0);
                    end
                    3'b101: begin
                        // CSRRWI writes the zero-extended zimm field.
                        csrOp = CSR_RW;
                        csrUseImm = 1'b1;
                    end
                    3'b110: begin
                        // CSRRSI with zimm=0 is a pure CSR read.
                        csrOp = (insn[19:15] == 5'd0) ? CSR_NONE : CSR_RS;
                        csrUseImm = 1'b1;
                    end
                    3'b111: begin
                        // CSRRCI with zimm=0 is a pure CSR read.
                        csrOp = (insn[19:15] == 5'd0) ? CSR_NONE : CSR_RC;
                        csrUseImm = 1'b1;
                    end
                    default: begin
                        registerWriteEnable = 1'b0;
                        wbSelect = WB_ALU;
                        csrOp = CSR_NONE;
                    end
                endcase
            end

            default: begin
            end
        endcase
    end
endmodule
