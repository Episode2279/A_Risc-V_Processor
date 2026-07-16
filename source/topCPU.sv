module topCPU
    import TypesPkg::*;
#(
    parameter int DATA_W = WORD_SIZE,
    parameter int INSN_W = INS_SIZE,
    parameter int ADDR_W = WORD_SIZE,
    parameter int REG_ADDR_W = REG_ADDR,
    parameter int REG_COUNT = REG_NUM,
    parameter int INSN_MEM_ADDR_W = INS_ADDR,
    parameter int INSN_MEM_BYTES = INS_ADDR_SIZE,
    parameter int DATA_MEM_ADDR_W = DATA_ADDR,
    parameter int DATA_MEM_BYTES = DATA_ADDR_SIZE,
    parameter logic [DATA_W-1:0] STATE_RESET_VALUE = '0,
    parameter logic [ADDR_W-1:0] RESET_PC = RESET_VECTOR,
    parameter logic [ADDR_W-1:0] PC_INCREMENT = 32'd4,
    parameter logic [DATA_W-1:0] UART_TX_MMIO_ADDR = UART_TX_ADDR,
    parameter logic [DATA_W-1:0] FROMHOST_MMIO_ADDR = FROMHOST_ADDR,
    parameter logic [DATA_W-1:0] TOHOST_MMIO_ADDR = TOHOST_ADDR
)
(
    input  logic              clk,
    input  logic              rst,
    input  logic [DATA_W-1:0] fromHost_i,
    output logic [DATA_W-1:0] toHost_o,
    output logic              uartValid_o,
    output logic [7:0]        uartData_o,
    output logic [INSN_W-1:0] check,
    output logic [ADDR_W-1:0] checkPC,
    output logic [DATA_W-1:0] checkData

`ifdef VERILATOR
    ,
    output logic              dbg_wrEnable,
    output logic              dbg_stall,
    output logic              dbg_flush,
    output logic              dbg_jumpEnable,
    output logic              dbg_issue0,
    output logic              dbg_issue1,
    output logic              dbg_if_valid,
    output logic [ADDR_W-1:0] dbg_if_pc,
    output logic [INSN_W-1:0] dbg_if_insn,
    output logic              dbg_if1_valid,
    output logic [ADDR_W-1:0] dbg_if1_pc,
    output logic [INSN_W-1:0] dbg_if1_insn,
    output logic              dbg_id_valid,
    output logic [ADDR_W-1:0] dbg_id_pc,
    output logic [INSN_W-1:0] dbg_id_insn,
    output logic [REG_ADDR_W-1:0] dbg_id_rd,
    output logic              dbg_id_regWrite,
    output logic              dbg_id_memWrite,
    output logic [3:0]        dbg_id_branchCtr,
    output logic [3:0]        dbg_id_aluCtr,
    output logic [2:0]        dbg_id_memCtr,
    output logic [REG_ADDR_W-1:0] dbg_id_regA,
    output logic [REG_ADDR_W-1:0] dbg_id_regB,
    output logic [ADDR_W-1:0] dbg_id_imm,
    output logic              dbg_id1_valid,
    output logic [ADDR_W-1:0] dbg_id1_pc,
    output logic [INSN_W-1:0] dbg_id1_insn,
    output logic [REG_ADDR_W-1:0] dbg_id1_rd,
    output logic              dbg_id1_regWrite,
    output logic              dbg_id1_memWrite,
    output logic [3:0]        dbg_id1_branchCtr,
    output logic [3:0]        dbg_id1_aluCtr,
    output logic [2:0]        dbg_id1_memCtr,
    output logic [REG_ADDR_W-1:0] dbg_id1_regA,
    output logic [REG_ADDR_W-1:0] dbg_id1_regB,
    output logic [ADDR_W-1:0] dbg_id1_imm,
    output logic [ADDR_W-1:0] dbg_ex_pc,
    output logic [REG_ADDR_W-1:0] dbg_ex_rd,
    output logic              dbg_ex_regWrite,
    output logic              dbg_ex_memWrite,
    output logic [2:0]        dbg_ex_memCtr,
    output logic [DATA_W-1:0] dbg_ex_aluOut,
    output logic [DATA_W-1:0] dbg_ex_dataA,
    output logic [DATA_W-1:0] dbg_ex_dataB,
    output logic [ADDR_W-1:0] dbg_ex_imm,
    output logic [ADDR_W-1:0] dbg_ex1_pc,
    output logic [REG_ADDR_W-1:0] dbg_ex1_rd,
    output logic              dbg_ex1_regWrite,
    output logic              dbg_ex1_memWrite,
    output logic [2:0]        dbg_ex1_memCtr,
    output logic [DATA_W-1:0] dbg_ex1_aluOut,
    output logic [DATA_W-1:0] dbg_ex1_dataA,
    output logic [DATA_W-1:0] dbg_ex1_dataB,
    output logic [ADDR_W-1:0] dbg_ex1_imm,
    output logic [ADDR_W-1:0] dbg_mem_pc,
    output logic [REG_ADDR_W-1:0] dbg_mem_rd,
    output logic              dbg_mem_regWrite,
    output logic              dbg_mem_memWrite,
    output logic [2:0]        dbg_mem_memCtr,
    output logic [DATA_W-1:0] dbg_mem_aluOut,
    output logic [DATA_W-1:0] dbg_mem_dataB,
    output logic [DATA_W-1:0] dbg_mem_rdData,
    output logic              dbg_mem_toHostHit,
    output logic              dbg_mem_uartHit,
    output logic              dbg_mem_fromHostHit,
    output logic [ADDR_W-1:0] dbg_mem1_pc,
    output logic [REG_ADDR_W-1:0] dbg_mem1_rd,
    output logic              dbg_mem1_regWrite,
    output logic              dbg_mem1_memWrite,
    output logic [2:0]        dbg_mem1_memCtr,
    output logic [DATA_W-1:0] dbg_mem1_aluOut,
    output logic [DATA_W-1:0] dbg_mem1_dataB,
    output logic [DATA_W-1:0] dbg_mem1_rdData,
    output logic [ADDR_W-1:0] dbg_wb_pc,
    output logic [REG_ADDR_W-1:0] dbg_wb_rd,
    output logic              dbg_wb_regWrite,
    output logic [2:0]        dbg_wb_wbSelect,
    output logic [DATA_W-1:0] dbg_wb_aluSrc,
    output logic [DATA_W-1:0] dbg_wb_rdData,
    output logic [DATA_W-1:0] dbg_wb_dataWb,
    output logic [ADDR_W-1:0] dbg_wb1_pc,
    output logic [REG_ADDR_W-1:0] dbg_wb1_rd,
    output logic              dbg_wb1_regWrite,
    output logic [2:0]        dbg_wb1_wbSelect,
    output logic [DATA_W-1:0] dbg_wb1_aluSrc,
    output logic [DATA_W-1:0] dbg_wb1_rdData,
    output logic [DATA_W-1:0] dbg_wb1_dataWb,
    output logic [$clog2(ROB_ENTRY_NUM+1)-1:0] dbg_robCount,
    output logic [$clog2(ISSUE_QUEUE_ENTRY_NUM+LSQ_ENTRY_NUM+1)-1:0] dbg_issueCount,
    output logic [$clog2(LSQ_ENTRY_NUM+1)-1:0] dbg_lsqCount,
    output logic [63:0] dbg_perfDualIssueCycles, dbg_perfSingleIssueCycles, dbg_perfIqNoReadyCycles,
    output logic [63:0] dbg_perfPort0LsuBlockedCycles, dbg_perfPort0BranchBlockedCycles,
    output logic [63:0] dbg_perfRobFullCycles, dbg_perfIqFullCycles, dbg_perfLsqFullCycles,
    output logic [63:0] dbg_perfPrfEmptyCycles, dbg_perfBranchCount, dbg_perfBranchMispredictCount,
    output logic [63:0] dbg_perfJumpSerializationCycles
    ,output logic [63:0] dbg_perfConditionalCount,dbg_perfConditionalMispredictCount,
    output logic [63:0] dbg_perfDirectionMispredictCount,dbg_perfTargetMispredictCount,dbg_perfBtbMissCount,
    output logic [63:0] dbg_perfJalMispredictCount,dbg_perfJalrMispredictCount,dbg_perfRasMissCount
`endif
);

    InstructionPacketIf if_fetch_bus();
    InstructionPacketIf if_fetch_bus1();
    InstructionPacketIf if_decode_bus();
    InstructionPacketIf if_decode_bus1();
    IdExeBusIf id_exe_in_bus();
    IdExeBusIf id_exe1_in_bus();

    // Compatibility views retained for existing waveform/testbench tooling.
    IdExeBusIf id_exe_bus();
    IdExeBusIf id_exe1_bus();
    ExeMemBusIf exe_mem_bus();
    ExeMemBusIf exe_mem1_bus();
    MemWbBusIf mem_wb_bus();
    MemWbBusIf mem_wb1_bus();

    logic [1:0] dispatchAccept;
    logic dispatchStall;
    logic [ADDR_W-1:0] pc_step;
    logic refillPredictedPair;
    logic wrEnable;
    logic stall;
    logic issue0;
    logic issue1;
    logic flush;
    logic jumpEnable;

    logic memoryValid;
    logic memoryWrite;
    word_t memoryAddress;
    word_t memoryWriteData;
    mem_access_t memoryAccess;
    word_t rdData_mem;
    word_t rdData1_mem;
    logic memToHostHit;
    logic memUartHit;
    logic memFromHostHit;

    logic csrValid;
    csr_op_t csrOp;
    csr_addr_t csrAddr;
    word_t csrWriteData;
    word_t csrReadData;

    logic branchResolved;
    instruction_addr_t branchPc;
    logic branchIsConditional;
    logic branchIsCall;
    logic branchIsReturn;
    bpu_index_t branchPredictorIndex;
    logic branchTaken;
    instruction_addr_t branchTarget;
    logic branchMispredicted;
    instruction_addr_t branchRedirect;
    rob_tag_t branchRobTag;
    logic [1:0] branchCheckpointValid;
    rob_tag_t branchCheckpointTag [2];
    logic [BPU_HISTORY_WIDTH-1:0] branchCheckpointHistory [2];
    logic trapValid;
    instruction_addr_t trapPc;
    logic [5:0] trapCause;
    word_t trapValue;
    logic mretCommit;
    instruction_addr_t trapVector;
    logic btbPredictTaken;
    instruction_addr_t btbPredictTarget;
    bpu_index_t bpuPredictorIndex;
    logic bpuPredictTaken1;
    instruction_addr_t bpuPredictTarget1;
    bpu_index_t bpuPredictorIndex1;
    logic [BPU_HISTORY_WIDTH-1:0] bpuHistorySnapshot;
    logic [BPU_HISTORY_WIDTH-1:0] bpuHistorySnapshot1;
    logic bpuBtbHit,bpuBtbHit1,bpuRasUsed,bpuRasUsed1;

    logic [1:0] commitValid;
    instruction_addr_t commitPc [2];
    reg_addr_t commitRd [2];
    word_t commitData [2];
    logic [1:0] retireCount;
    logic [1:0] architecturalRetireCount;
    logic [$clog2(ROB_ENTRY_NUM+1)-1:0] robCount;
    logic [$clog2(ISSUE_QUEUE_ENTRY_NUM+LSQ_ENTRY_NUM+1)-1:0] issueCount;
    logic [$clog2(LSQ_ENTRY_NUM+1)-1:0] lsqCount;

    logic [DATA_W-1:0] aluOut_exe;
    logic [DATA_W-1:0] aluOut1_exe;
    logic [DATA_W-1:0] forwardA_exe;
    logic [DATA_W-1:0] forwardB_exe;
    logic [DATA_W-1:0] forwardA1_exe;
    logic [DATA_W-1:0] forwardB1_exe;
    logic [DATA_W-1:0] data_wb;
    logic [DATA_W-1:0] data1_wb;

    assign issue0 = dispatchAccept[0];
    assign issue1 = dispatchAccept[1];
    assign stall = dispatchStall;
    assign wrEnable = !stall;
    assign jumpEnable = trapValid || (branchResolved && branchMispredicted);
    assign flush = jumpEnable;
    assign architecturalRetireCount = retireCount;
    assign refillPredictedPair = issue0 && !id_exe1_in_bus.valid &&
                                 id_exe_in_bus.predictedTaken;
    assign pc_step = (!id_exe_in_bus.valid && !id_exe1_in_bus.valid) ?
                     (PC_INCREMENT + PC_INCREMENT) :
                     issue1 ? (PC_INCREMENT + PC_INCREMENT) :
                     refillPredictedPair ? (PC_INCREMENT + PC_INCREMENT) :
                     issue0 ? PC_INCREMENT : '0;

    assign check = if_fetch_bus.insn;
    assign checkPC = if_fetch_bus.pc;
    assign checkData = commitValid[0] ? commitData[0] :
                       commitValid[1] ? commitData[1] : '0;

    BranchPredictionUnit bpu (
        .clk(clk),
        .rst(rst),
        .queryPc_i(if_fetch_bus.pc),
        .queryInsn_i(if_fetch_bus.insn),
        .predictTaken_o(btbPredictTaken),
        .predictTarget_o(btbPredictTarget),
        .predictorIndex_o(bpuPredictorIndex),
        .queryAdvance_i((pc_step != '0) && !jumpEnable),
        .queryPc1_i(if_fetch_bus1.pc), .queryInsn1_i(if_fetch_bus1.insn),
        .queryAdvance1_i((pc_step == 32'd8) && !btbPredictTaken && !jumpEnable),
        .predictTaken1_o(bpuPredictTaken1), .predictTarget1_o(bpuPredictTarget1),
        .predictorIndex1_o(bpuPredictorIndex1),
        .historySnapshot_o(bpuHistorySnapshot), .historySnapshot1_o(bpuHistorySnapshot1),
        .btbHit_o(bpuBtbHit),.btbHit1_o(bpuBtbHit1),.rasUsed_o(bpuRasUsed),.rasUsed1_o(bpuRasUsed1),
        .updateValid_i(branchResolved),
        .updatePc_i(branchPc),
        .updateIsConditional_i(branchIsConditional),
        .updateTaken_i(branchTaken),
        .updateTarget_i(branchTarget),
        .updatePredictorIndex_i(branchPredictorIndex),
        .updateMispredicted_i(branchMispredicted),
        .updateIsCall_i(branchIsCall), .updateIsReturn_i(branchIsReturn)
        ,.updateRobTag_i(branchRobTag), .checkpointAllocValid_i(branchCheckpointValid),
        .checkpointAllocTag_i(branchCheckpointTag), .checkpointAllocHistory_i(branchCheckpointHistory)
    );

    DualIfStages #(
        .ADDR_W(ADDR_W),
        .INSN_W(INSN_W),
        .MEM_ADDR_W(INSN_MEM_ADDR_W),
        .MEM_BYTES(INSN_MEM_BYTES),
        .RESET_PC(RESET_PC),
        .PC_INCREMENT(PC_INCREMENT)
    ) ifStage (
        .clk(clk),
        .rst(rst),
        .jump_address(trapValid ? trapVector : branchRedirect),
        .jump_enable(jumpEnable),
        .predictTaken_i(btbPredictTaken),
        .predictTarget_i(btbPredictTarget),
        .predictorIndex_i(bpuPredictorIndex),
        .predictTaken1_i(bpuPredictTaken1), .predictTarget1_i(bpuPredictTarget1),
        .predictorIndex1_i(bpuPredictorIndex1),
        .historySnapshot_i(bpuHistorySnapshot), .historySnapshot1_i(bpuHistorySnapshot1),
        .btbHit_i(bpuBtbHit),.btbHit1_i(bpuBtbHit1),.rasUsed_i(bpuRasUsed),.rasUsed1_i(bpuRasUsed1),
        .pc_step_i(pc_step),
        .fetch_packet0(if_fetch_bus),
        .fetch_packet1(if_fetch_bus1)
    );

    DualIF_IDRegister #(
        .RESET_PC(RESET_PC)
    ) if_id (
        .clk(clk),
        .rst(rst),
        .fetch0_i(if_fetch_bus),
        .fetch1_i(if_fetch_bus1),
        .stall(stall),
        .flush(flush),
        .issue0(issue0),
        .issue1(issue1),
        .packet0_o(if_decode_bus),
        .packet1_o(if_decode_bus1)
    );

    IdStages idStage (
        .id_packet(if_decode_bus),
        .id_bus(id_exe_in_bus)
    );

    IdStages idStage1 (
        .id_packet(if_decode_bus1),
        .id_bus(id_exe1_in_bus)
    );

    OoOBackend backend (
        .clk(clk),
        .rst(rst),
        .flush_i(trapValid),
        .decode0_bus(id_exe_in_bus),
        .decode1_bus(id_exe1_in_bus),
        .dispatchAccept_o(dispatchAccept),
        .dispatchStall_o(dispatchStall),
        .memoryReadData_i(rdData_mem),
        .memoryValid_o(memoryValid),
        .memoryWrite_o(memoryWrite),
        .memoryAddress_o(memoryAddress),
        .memoryWriteData_o(memoryWriteData),
        .memoryAccess_o(memoryAccess),
        .csrReadData_i(csrReadData),
        .csrValid_o(csrValid),
        .csrOp_o(csrOp),
        .csrAddr_o(csrAddr),
        .csrWriteData_o(csrWriteData),
        .branchResolved_o(branchResolved),
        .branchPc_o(branchPc),
        .branchIsConditional_o(branchIsConditional),
        .branchIsCall_o(branchIsCall), .branchIsReturn_o(branchIsReturn),
        .branchPredictorIndex_o(branchPredictorIndex),
        .branchTaken_o(branchTaken),
        .branchTarget_o(branchTarget),
        .branchMispredicted_o(branchMispredicted),
        .branchRedirect_o(branchRedirect),
        .branchRobTag_o(branchRobTag), .branchCheckpointValid_o(branchCheckpointValid),
        .branchCheckpointTag_o(branchCheckpointTag), .branchCheckpointHistory_o(branchCheckpointHistory),
        .trapValid_o(trapValid),
        .trapPc_o(trapPc),
        .trapCause_o(trapCause),
        .trapValue_o(trapValue),
        .mretCommit_o(mretCommit),
        .commitValid_o(commitValid),
        .commitPc_o(commitPc),
        .commitArchRd_o(commitRd),
        .commitData_o(commitData),
        .retireCount_o(retireCount),
        .robCount_o(robCount),
        .issueCount_o(issueCount),
        .lsqCount_o(lsqCount),
        .perfDualIssueCycles_o(dbg_perfDualIssueCycles), .perfSingleIssueCycles_o(dbg_perfSingleIssueCycles),
        .perfIqNoReadyCycles_o(dbg_perfIqNoReadyCycles),
        .perfPort0LsuBlockedCycles_o(dbg_perfPort0LsuBlockedCycles),
        .perfPort0BranchBlockedCycles_o(dbg_perfPort0BranchBlockedCycles),
        .perfRobFullCycles_o(dbg_perfRobFullCycles), .perfIqFullCycles_o(dbg_perfIqFullCycles),
        .perfLsqFullCycles_o(dbg_perfLsqFullCycles), .perfPrfEmptyCycles_o(dbg_perfPrfEmptyCycles),
        .perfBranchCount_o(dbg_perfBranchCount), .perfBranchMispredictCount_o(dbg_perfBranchMispredictCount),
        .perfJumpSerializationCycles_o(dbg_perfJumpSerializationCycles)
        ,.perfConditionalCount_o(dbg_perfConditionalCount),
        .perfConditionalMispredictCount_o(dbg_perfConditionalMispredictCount),
        .perfDirectionMispredictCount_o(dbg_perfDirectionMispredictCount),
        .perfTargetMispredictCount_o(dbg_perfTargetMispredictCount),.perfBtbMissCount_o(dbg_perfBtbMissCount),
        .perfJalMispredictCount_o(dbg_perfJalMispredictCount),.perfJalrMispredictCount_o(dbg_perfJalrMispredictCount),
        .perfRasMissCount_o(dbg_perfRasMissCount)
    );

    assign exe_mem_bus.valid = memoryValid;
    assign exe_mem_bus.pc = '0;
    assign exe_mem_bus.registerWriteEnable = memoryValid && !memoryWrite;
    assign exe_mem_bus.dataWriteEnable = memoryValid && memoryWrite;
    assign exe_mem_bus.wbSelect = memoryWrite ? WB_ALU : WB_MEM;
    assign exe_mem_bus.memCtr = memoryAccess;
    assign exe_mem_bus.dataB = memoryWriteData;
    assign exe_mem_bus.rd = '0;
    assign exe_mem_bus.immediate = '0;
    assign exe_mem_bus.aluOut = memoryAddress;
    assign exe_mem_bus.csrData = '0;

    MEMStages #(
        .DATA_W(DATA_W),
        .LOGIC_ADDR_W(DATA_MEM_ADDR_W),
        .MEM_BYTES(DATA_MEM_BYTES),
        .UART_TX_MMIO_ADDR(UART_TX_MMIO_ADDR),
        .FROMHOST_MMIO_ADDR(FROMHOST_MMIO_ADDR),
        .TOHOST_MMIO_ADDR(TOHOST_MMIO_ADDR)
    ) memStage (
        .clk(clk),
        .rst(rst),
        .fromHost_i(fromHost_i),
        .mem_bus(exe_mem_bus),
        .rdData(rdData_mem),
        .toHost_o(toHost_o),
        .uartValid_o(uartValid_o),
        .uartData_o(uartData_o),
        .toHostHit_o(memToHostHit),
        .uartHit_o(memUartHit),
        .fromHostHit_o(memFromHostHit)
    );

    CSRFile csrFile (
        .clk(clk),
        .rst(rst),
        .retireCount_i(architecturalRetireCount),
        .csrValid_i(csrValid),
        .csrOp_i(csrOp),
        .csrAddr_i(csrAddr),
        .csrWriteData_i(csrWriteData),
        .csrReadData_o(csrReadData),
        .trapValid_i(trapValid),
        .trapPc_i(trapPc),
        .trapCause_i(trapCause),
        .trapValue_i(trapValue),
        .mret_i(mretCommit),
        .trapVector_o(trapVector)
    );

    // Compatibility-only views for the existing textual pipeline dumper.
    assign id_exe_bus.pc = id_exe_in_bus.pc;
    assign id_exe_bus.predictedTaken = id_exe_in_bus.predictedTaken;
    assign id_exe_bus.predictedTarget = id_exe_in_bus.predictedTarget;
    assign id_exe_bus.predictorIndex = id_exe_in_bus.predictorIndex;
    assign id_exe_bus.historySnapshot = id_exe_in_bus.historySnapshot;
    assign id_exe_bus.predictedBtbHit = id_exe_in_bus.predictedBtbHit;
    assign id_exe_bus.predictedRasUsed = id_exe_in_bus.predictedRasUsed;
    assign id_exe_bus.rd = id_exe_in_bus.rd;
    assign id_exe_bus.registerWriteEnable = id_exe_in_bus.registerWriteEnable;
    assign id_exe_bus.dataWriteEnable = id_exe_in_bus.dataWriteEnable;
    assign id_exe_bus.memCtr = id_exe_in_bus.memCtr;
    assign id_exe_bus.immediate = id_exe_in_bus.immediate;
    assign id_exe1_bus.pc = id_exe1_in_bus.pc;
    assign id_exe1_bus.predictedTaken = id_exe1_in_bus.predictedTaken;
    assign id_exe1_bus.predictedTarget = id_exe1_in_bus.predictedTarget;
    assign id_exe1_bus.predictorIndex = id_exe1_in_bus.predictorIndex;
    assign id_exe1_bus.historySnapshot = id_exe1_in_bus.historySnapshot;
    assign id_exe1_bus.predictedBtbHit = id_exe1_in_bus.predictedBtbHit;
    assign id_exe1_bus.predictedRasUsed = id_exe1_in_bus.predictedRasUsed;
    assign id_exe1_bus.rd = id_exe1_in_bus.rd;
    assign id_exe1_bus.registerWriteEnable = id_exe1_in_bus.registerWriteEnable;
    assign id_exe1_bus.dataWriteEnable = id_exe1_in_bus.dataWriteEnable;
    assign id_exe1_bus.memCtr = id_exe1_in_bus.memCtr;
    assign id_exe1_bus.immediate = id_exe1_in_bus.immediate;
    assign aluOut_exe = memoryAddress;
    assign aluOut1_exe = '0;
    assign forwardA_exe = '0;
    assign forwardB_exe = memoryWriteData;
    assign forwardA1_exe = '0;
    assign forwardB1_exe = '0;

    assign exe_mem1_bus.valid = 1'b0;
    assign exe_mem1_bus.pc = '0;
    assign exe_mem1_bus.registerWriteEnable = 1'b0;
    assign exe_mem1_bus.dataWriteEnable = 1'b0;
    assign exe_mem1_bus.wbSelect = WB_ALU;
    assign exe_mem1_bus.memCtr = MEM_WORD;
    assign exe_mem1_bus.dataB = '0;
    assign exe_mem1_bus.rd = '0;
    assign exe_mem1_bus.immediate = '0;
    assign exe_mem1_bus.aluOut = '0;
    assign exe_mem1_bus.csrData = '0;
    assign rdData1_mem = '0;

    assign mem_wb_bus.valid = commitValid[0];
    assign mem_wb_bus.pc = commitPc[0];
    assign mem_wb_bus.registerWriteEnable = commitValid[0] && (commitRd[0] != '0);
    assign mem_wb_bus.wbSelect = WB_ALU;
    assign mem_wb_bus.immediate = '0;
    assign mem_wb_bus.aluSrc = commitData[0];
    assign mem_wb_bus.rdData = '0;
    assign mem_wb_bus.csrData = '0;
    assign mem_wb_bus.rd = commitRd[0];
    assign data_wb = commitData[0];
    assign mem_wb1_bus.valid = commitValid[1];
    assign mem_wb1_bus.pc = commitPc[1];
    assign mem_wb1_bus.registerWriteEnable = commitValid[1] && (commitRd[1] != '0);
    assign mem_wb1_bus.wbSelect = WB_ALU;
    assign mem_wb1_bus.immediate = '0;
    assign mem_wb1_bus.aluSrc = commitData[1];
    assign mem_wb1_bus.rdData = '0;
    assign mem_wb1_bus.csrData = '0;
    assign mem_wb1_bus.rd = commitRd[1];
    assign data1_wb = commitData[1];

`ifdef VERILATOR
    assign dbg_wrEnable = wrEnable;
    assign dbg_stall = stall;
    assign dbg_flush = flush;
    assign dbg_jumpEnable = jumpEnable;
    assign dbg_issue0 = issue0;
    assign dbg_issue1 = issue1;
    assign dbg_if_valid = (if_fetch_bus.insn != '0);
    assign dbg_if_pc = if_fetch_bus.pc;
    assign dbg_if_insn = if_fetch_bus.insn;
    assign dbg_if1_valid = (if_fetch_bus1.insn != '0);
    assign dbg_if1_pc = if_fetch_bus1.pc;
    assign dbg_if1_insn = if_fetch_bus1.insn;
    assign dbg_id_valid = id_exe_in_bus.valid;
    assign dbg_id_pc = if_decode_bus.pc;
    assign dbg_id_insn = if_decode_bus.insn;
    assign dbg_id_rd = id_exe_in_bus.rd;
    assign dbg_id_regWrite = id_exe_in_bus.registerWriteEnable;
    assign dbg_id_memWrite = id_exe_in_bus.dataWriteEnable;
    assign dbg_id_branchCtr = id_exe_in_bus.branchCtr;
    assign dbg_id_aluCtr = id_exe_in_bus.aluCtr;
    assign dbg_id_memCtr = id_exe_in_bus.memCtr;
    assign dbg_id_regA = id_exe_in_bus.regA;
    assign dbg_id_regB = id_exe_in_bus.regB;
    assign dbg_id_imm = id_exe_in_bus.immediate;
    assign dbg_id1_valid = id_exe1_in_bus.valid;
    assign dbg_id1_pc = if_decode_bus1.pc;
    assign dbg_id1_insn = if_decode_bus1.insn;
    assign dbg_id1_rd = id_exe1_in_bus.rd;
    assign dbg_id1_regWrite = id_exe1_in_bus.registerWriteEnable;
    assign dbg_id1_memWrite = id_exe1_in_bus.dataWriteEnable;
    assign dbg_id1_branchCtr = id_exe1_in_bus.branchCtr;
    assign dbg_id1_aluCtr = id_exe1_in_bus.aluCtr;
    assign dbg_id1_memCtr = id_exe1_in_bus.memCtr;
    assign dbg_id1_regA = id_exe1_in_bus.regA;
    assign dbg_id1_regB = id_exe1_in_bus.regB;
    assign dbg_id1_imm = id_exe1_in_bus.immediate;
    assign dbg_ex_pc = id_exe_bus.pc;
    assign dbg_ex_rd = id_exe_bus.rd;
    assign dbg_ex_regWrite = id_exe_bus.registerWriteEnable;
    assign dbg_ex_memWrite = id_exe_bus.dataWriteEnable;
    assign dbg_ex_memCtr = id_exe_bus.memCtr;
    assign dbg_ex_aluOut = aluOut_exe;
    assign dbg_ex_dataA = forwardA_exe;
    assign dbg_ex_dataB = forwardB_exe;
    assign dbg_ex_imm = id_exe_bus.immediate;
    assign dbg_ex1_pc = id_exe1_bus.pc;
    assign dbg_ex1_rd = id_exe1_bus.rd;
    assign dbg_ex1_regWrite = id_exe1_bus.registerWriteEnable;
    assign dbg_ex1_memWrite = id_exe1_bus.dataWriteEnable;
    assign dbg_ex1_memCtr = id_exe1_bus.memCtr;
    assign dbg_ex1_aluOut = aluOut1_exe;
    assign dbg_ex1_dataA = forwardA1_exe;
    assign dbg_ex1_dataB = forwardB1_exe;
    assign dbg_ex1_imm = id_exe1_bus.immediate;
    assign dbg_mem_pc = exe_mem_bus.pc;
    assign dbg_mem_rd = exe_mem_bus.rd;
    assign dbg_mem_regWrite = exe_mem_bus.registerWriteEnable;
    assign dbg_mem_memWrite = exe_mem_bus.dataWriteEnable;
    assign dbg_mem_memCtr = exe_mem_bus.memCtr;
    assign dbg_mem_aluOut = exe_mem_bus.aluOut;
    assign dbg_mem_dataB = exe_mem_bus.dataB;
    assign dbg_mem_rdData = rdData_mem;
    assign dbg_mem_toHostHit = memToHostHit;
    assign dbg_mem_uartHit = memUartHit;
    assign dbg_mem_fromHostHit = memFromHostHit;
    assign dbg_mem1_pc = '0;
    assign dbg_mem1_rd = '0;
    assign dbg_mem1_regWrite = 1'b0;
    assign dbg_mem1_memWrite = 1'b0;
    assign dbg_mem1_memCtr = MEM_WORD;
    assign dbg_mem1_aluOut = '0;
    assign dbg_mem1_dataB = '0;
    assign dbg_mem1_rdData = '0;
    assign dbg_wb_pc = commitPc[0];
    assign dbg_wb_rd = commitRd[0];
    assign dbg_wb_regWrite = commitValid[0] && (commitRd[0] != '0);
    assign dbg_wb_wbSelect = WB_ALU;
    assign dbg_wb_aluSrc = commitData[0];
    assign dbg_wb_rdData = '0;
    assign dbg_wb_dataWb = commitData[0];
    assign dbg_wb1_pc = commitPc[1];
    assign dbg_wb1_rd = commitRd[1];
    assign dbg_wb1_regWrite = commitValid[1] && (commitRd[1] != '0);
    assign dbg_wb1_wbSelect = WB_ALU;
    assign dbg_wb1_aluSrc = commitData[1];
    assign dbg_wb1_rdData = '0;
    assign dbg_wb1_dataWb = commitData[1];
    assign dbg_robCount = robCount;
    assign dbg_issueCount = issueCount;
    assign dbg_lsqCount = lsqCount;
`endif

endmodule
