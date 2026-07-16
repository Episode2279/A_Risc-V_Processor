module OoOExecutionUnit
    import TypesPkg::*;
(
    input  logic clk,
    input  logic rst,
    input  logic flush_i,

    input  logic issueValid_i,
    input  renamed_uop_t issueUop_i,
    input  word_t sourceA_i,
    input  word_t sourceB_i,
    input  word_t csrReadData_i,
    input  logic orderingReady_i,
    output logic issueReady_o,

    output logic completionValid_o,
    output rob_tag_t completionRobTag_o,
    output logic completionException_o,
    output logic [5:0] completionCause_o,
    output word_t completionValue_o,
    output logic writebackValid_o,
    output phys_reg_addr_t writebackPhys_o,
    output word_t writebackData_o,

    output logic branchResolved_o,
    output instruction_addr_t branchPc_o,
    output logic branchIsConditional_o,
    output logic branchIsCall_o,
    output logic branchIsReturn_o,
    output bpu_index_t branchPredictorIndex_o,
    output logic branchTaken_o,
    output instruction_addr_t branchTarget_o,
    output logic branchMispredicted_o,
    output instruction_addr_t branchRedirect_o,

    output logic csrValid_o,
    output csr_op_t csrOp_o,
    output csr_addr_t csrAddr_o,
    output word_t csrWriteData_o,
    input  logic completionReady_i
);

    word_t aluInputA;
    word_t aluInputB;
    word_t aluResult;
    word_t selectedResult;
    logic branchTaken;
    instruction_addr_t branchTarget;
    instruction_addr_t branchActualNext;
    logic executeException;
    logic [5:0] executeCause;
    word_t executeValue;

    logic completionValid;
    rob_tag_t completionRobTag;
    logic writebackValid;
    phys_reg_addr_t writebackPhys;
    word_t writebackData;
    logic completionException;
    logic [5:0] completionCause;
    word_t completionValue;

    assign aluInputA = issueUop_i.aluSrcASelect ? issueUop_i.pc : sourceA_i;
    assign aluInputB = issueUop_i.aluSrcBSelect ? issueUop_i.immediate : sourceB_i;
    always_comb begin
        unique case (issueUop_i.wbSelect)
            WB_PC4: selectedResult = issueUop_i.pc + 32'd4;
            WB_IMM: selectedResult = issueUop_i.immediate;
            WB_CSR: selectedResult = csrReadData_i;
            default: selectedResult = aluResult;
        endcase
    end

    always_comb begin
        branchTaken = 1'b0;
        branchTarget = issueUop_i.pc + issueUop_i.immediate;
        unique case (issueUop_i.branchCtr)
            BR_BEQ:  branchTaken = (sourceA_i == sourceB_i);
            BR_BNE:  branchTaken = (sourceA_i != sourceB_i);
            BR_BLT:  branchTaken = ($signed(sourceA_i) < $signed(sourceB_i));
            BR_BGE:  branchTaken = ($signed(sourceA_i) >= $signed(sourceB_i));
            BR_BLTU: branchTaken = (sourceA_i < sourceB_i);
            BR_BGEU: branchTaken = (sourceA_i >= sourceB_i);
            BR_JAL:  branchTaken = 1'b1;
            BR_JALR: begin
                branchTaken = 1'b1;
                branchTarget = (sourceA_i + issueUop_i.immediate) & ~word_t'(1);
            end
            BR_MRET: begin
                branchTaken = 1'b1;
                branchTarget = csrReadData_i;
            end
            default: begin
                branchTaken = 1'b0;
            end
        endcase
    end

    assign issueReady_o = orderingReady_i &&
                          (!completionValid || completionReady_i);
    assign completionValid_o = completionValid;
    assign completionRobTag_o = completionRobTag;
    assign writebackValid_o = writebackValid;
    assign writebackPhys_o = writebackPhys;
    assign writebackData_o = writebackData;

    always_comb begin
        executeException = issueUop_i.decodeException;
        executeCause = issueUop_i.decodeExceptionCause;
        executeValue = issueUop_i.exceptionValue;
        if (!executeException && (issueUop_i.fuClass == FU_BRANCH) &&
            branchTaken && (branchTarget[1:0] != 2'b00)) begin
            executeException = 1'b1;
            executeCause = EXC_INSN_ADDR_MISALIGNED;
            executeValue = branchTarget;
        end
    end
    assign completionException_o = completionException;
    assign completionCause_o = completionCause;
    assign completionValue_o = completionValue;

    assign branchResolved_o = issueValid_i && issueReady_o && !executeException &&
                              (issueUop_i.fuClass == FU_BRANCH);
    assign branchPc_o = issueUop_i.pc;
    assign branchIsConditional_o = (issueUop_i.branchCtr >= BR_BEQ) &&
                                   (issueUop_i.branchCtr <= BR_BGEU);
    assign branchIsCall_o = issueUop_i.isCall;
    assign branchIsReturn_o = issueUop_i.isReturn;
    assign branchPredictorIndex_o = issueUop_i.predictorIndex;
    assign branchTaken_o = branchTaken;
    assign branchTarget_o = branchTarget;
    assign branchActualNext = branchTaken ? branchTarget :
                              (issueUop_i.pc + 32'd4);
    assign branchMispredicted_o = branchResolved_o &&
        ((issueUop_i.predictedTaken != branchTaken) ||
         (branchTaken && issueUop_i.predictedTaken &&
          (issueUop_i.predictedTarget != branchTarget)));
    assign branchRedirect_o = branchActualNext;

    assign csrValid_o = issueValid_i && issueReady_o &&
                        (issueUop_i.fuClass == FU_CSR);
    assign csrOp_o = issueUop_i.csrOp;
    assign csrAddr_o = issueUop_i.csrAddr;
    assign csrWriteData_o = issueUop_i.csrUseImm ? issueUop_i.csrImm : sourceA_i;

    ALU alu (
        .ctr(issueUop_i.aluCtr),
        .dataA(aluInputA),
        .dataB(aluInputB),
        .out(aluResult)
    );

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            completionValid <= 1'b0;
            completionRobTag <= '0;
            writebackValid <= 1'b0;
            writebackPhys <= '0;
            writebackData <= '0;
            completionException <= 1'b0;
            completionCause <= '0;
            completionValue <= '0;
        end else if (flush_i) begin
            completionValid <= 1'b0;
            writebackValid <= 1'b0;
            completionException <= 1'b0;
        end else if (issueReady_o) begin
            completionValid <= issueValid_i;
            completionRobTag <= issueUop_i.robTag;
            completionException <= executeException;
            completionCause <= executeCause;
            completionValue <= executeValue;
            writebackValid <= issueValid_i && !executeException &&
                              issueUop_i.registerWriteEnable &&
                              (issueUop_i.destPhys != '0);
            writebackPhys <= issueUop_i.destPhys;
            writebackData <= selectedResult;
        end
    end

endmodule
