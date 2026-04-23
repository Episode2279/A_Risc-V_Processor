module topCPU
    import TypesPkg::*;
#(
    // Datapath and storage sizing. These default to the shared package values,
    // but can be overridden to retarget the core configuration.
    parameter int DATA_W = WORD_SIZE,
    parameter int INSN_W = INS_SIZE,
    parameter int ADDR_W = WORD_SIZE,
    parameter int REG_ADDR_W = REG_ADDR,
    parameter int REG_COUNT = REG_NUM,
    parameter int INSN_MEM_ADDR_W = INS_ADDR,
    parameter int INSN_MEM_BYTES = INS_ADDR_SIZE,
    parameter int DATA_MEM_ADDR_W = DATA_ADDR,
    parameter int DATA_MEM_BYTES = DATA_ADDR_SIZE,
    // Reset and MMIO defaults used by the integrated memories/peripherals.
    parameter logic [DATA_W-1:0] STATE_RESET_VALUE = '0,
    parameter logic [ADDR_W-1:0] RESET_PC = RESET_VECTOR,
    parameter logic [ADDR_W-1:0] PC_INCREMENT = 32'd4,
    parameter logic [DATA_W-1:0] UART_TX_MMIO_ADDR = UART_TX_ADDR,
    parameter logic [DATA_W-1:0] FROMHOST_MMIO_ADDR = FROMHOST_ADDR,
    parameter logic [DATA_W-1:0] TOHOST_MMIO_ADDR = TOHOST_ADDR
)
(
    // Core clock/reset. rst is active-low throughout this project.
    input  logic              clk,
    input  logic              rst,
    // Host-side MMIO input and completion/UART outputs used by testbenches.
    input  logic [DATA_W-1:0] fromHost_i,
    output logic [DATA_W-1:0] toHost_o,
    output logic              uartValid_o,
    output logic [7:0]        uartData_o,
    output logic [INSN_W-1:0] check,
    output logic [ADDR_W-1:0] checkPC,
    output logic [DATA_W-1:0] checkData

`ifdef VERILATOR
    ,
    // Simulation debug ports mirror the Vivado testbench pipeline dump schema.
    // They keep the Verilator harness independent from generated hierarchy names.
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
    output logic [DATA_W-1:0] dbg_wb1_dataWb
`endif
);

    // Branch target produced in EX and consumed by IF on the next PC update.
    logic [ADDR_W-1:0] pc_br;
    logic [ADDR_W-1:0] pc_step;

    // Register-file read data is generated in ID. Forwarded versions are used
    // by EX so the core can run dependent ALU instructions without stalling.
    logic [DATA_W-1:0] regDataA_id, regDataB_id;
    logic [DATA_W-1:0] regDataA1_id, regDataB1_id;
    logic [DATA_W-1:0] forwardA_exe, forwardB_exe;
    logic [DATA_W-1:0] forwardA1_exe, forwardB1_exe;
    // Main execute, CSR, memory, and writeback data signals.
    logic [DATA_W-1:0] aluOut_exe;
    logic [DATA_W-1:0] aluOut1_exe;
    logic [DATA_W-1:0] csrData_exe;
    logic [DATA_W-1:0] csrWriteData_exe;
    logic [DATA_W-1:0] rdData_mem;
    logic [DATA_W-1:0] rdData1_mem;
    logic [DATA_W-1:0] data_wb;
    logic [DATA_W-1:0] data1_wb;
    logic [DATA_W-1:0] result_mem;
    logic [DATA_W-1:0] result1_mem;

    // Branch comparator outputs and hazard/redirect controls.
    logic equal;
    logic lessThan;
    logic lessThanUnsigned;
    logic equal1;
    logic lessThan1;
    logic lessThanUnsigned1;
    logic jumpEnable;
    logic wrEnable;
    logic stall;
    logic issue0;
    logic issue1;
    logic flush;
    logic csrValid_exe;
    logic [1:0] retireCount;
    logic memToHostHit;
    logic memUartHit;
    logic memFromHostHit;

    // Strongly typed pipeline interfaces. The *_in_bus forms are combinational
    // inputs to a pipeline register; the non-suffixed forms are registered
    // outputs from that boundary.
    InstructionPacketIf if_fetch_bus();
    InstructionPacketIf if_fetch_bus1();
    InstructionPacketIf if_decode_bus();
    InstructionPacketIf if_decode_bus1();
    IdExeBusIf          id_exe_in_bus();
    IdExeBusIf          id_exe1_in_bus();
    IdExeBusIf          id_exe_bus();
    IdExeBusIf          id_exe1_bus();
    ExeMemBusIf         exe_mem_in_bus();
    ExeMemBusIf         exe_mem1_in_bus();
    ExeMemBusIf         exe_mem_bus();
    ExeMemBusIf         exe_mem1_bus();
    MemWbBusIf          mem_wb_in_bus();
    MemWbBusIf          mem_wb1_in_bus();
    MemWbBusIf          mem_wb_bus();
    MemWbBusIf          mem_wb1_bus();

    // Lightweight architectural visibility for tests and Verilator harness.
    assign check = if_fetch_bus.insn;
    assign checkPC = if_fetch_bus.pc;
    assign checkData = data_wb;
    assign flush = jumpEnable;
    assign id_exe_in_bus.dataA = regDataA_id;
    assign id_exe_in_bus.dataB = regDataB_id;
    assign id_exe1_in_bus.dataA = regDataA1_id;
    assign id_exe1_in_bus.dataB = regDataB1_id;
    assign csrWriteData_exe = id_exe_bus.csrUseImm ? id_exe_bus.csrImm : forwardA_exe;
    // CSR writes are performed in EX for CSR instructions that reached ID/EX.
    assign csrValid_exe = id_exe_bus.valid && (id_exe_bus.wbSelect == WB_CSR);
    assign retireCount = {1'b0, mem_wb_bus.valid} + {1'b0, mem_wb1_bus.valid};
    assign rdData1_mem = '0;

`ifdef VERILATOR
    // Flattened debug mirrors are Verilator-only so generated C++ can dump the
    // pipeline without depending on private hierarchy names or interface layout.
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
    assign dbg_mem1_pc = exe_mem1_bus.pc;
    assign dbg_mem1_rd = exe_mem1_bus.rd;
    assign dbg_mem1_regWrite = exe_mem1_bus.registerWriteEnable;
    assign dbg_mem1_memWrite = exe_mem1_bus.dataWriteEnable;
    assign dbg_mem1_memCtr = exe_mem1_bus.memCtr;
    assign dbg_mem1_aluOut = exe_mem1_bus.aluOut;
    assign dbg_mem1_dataB = exe_mem1_bus.dataB;
    assign dbg_mem1_rdData = rdData1_mem;
    assign dbg_wb_pc = mem_wb_bus.pc;
    assign dbg_wb_rd = mem_wb_bus.rd;
    assign dbg_wb_regWrite = mem_wb_bus.registerWriteEnable;
    assign dbg_wb_wbSelect = mem_wb_bus.wbSelect;
    assign dbg_wb_aluSrc = mem_wb_bus.aluSrc;
    assign dbg_wb_rdData = mem_wb_bus.rdData;
    assign dbg_wb_dataWb = data_wb;
    assign dbg_wb1_pc = mem_wb1_bus.pc;
    assign dbg_wb1_rd = mem_wb1_bus.rd;
    assign dbg_wb1_regWrite = mem_wb1_bus.registerWriteEnable;
    assign dbg_wb1_wbSelect = mem_wb1_bus.wbSelect;
    assign dbg_wb1_aluSrc = mem_wb1_bus.aluSrc;
    assign dbg_wb1_rdData = mem_wb1_bus.rdData;
    assign dbg_wb1_dataWb = data1_wb;
`endif

    // Register file is written from WB and read by ID in the same cycle. Its
    // internal write-first bypass handles WB-to-ID same-cycle dependencies.
    RegisterFile #(
        .DATA_W(DATA_W),
        .REG_COUNT(REG_COUNT),
        .REG_ADDR_W(REG_ADDR_W),
        .RESET_VALUE(STATE_RESET_VALUE)
    ) regFile(
        .clk(clk),
        .rst(rst),
        .writeEnable(mem_wb_bus.registerWriteEnable),
        .data_i(data_wb),
        .wrAddr(mem_wb_bus.rd),
        .writeEnableB(mem_wb1_bus.registerWriteEnable),
        .dataB_i(data1_wb),
        .wrAddrB(mem_wb1_bus.rd),
        .rdAddrA(id_exe_in_bus.regA),
        .rdAddrB(id_exe_in_bus.regB),
        .rdAddrC(id_exe1_in_bus.regA),
        .rdAddrD(id_exe1_in_bus.regB),
        .rdA(regDataA_id),
        .rdB(regDataB_id),
        .rdC(regDataA1_id),
        .rdD(regDataB1_id)
    );

    // IF owns PC update and two-word instruction memory lookup.
    DualIfStages #(
        .ADDR_W(ADDR_W),
        .INSN_W(INSN_W),
        .MEM_ADDR_W(INSN_MEM_ADDR_W),
        .MEM_BYTES(INSN_MEM_BYTES),
        .RESET_PC(RESET_PC),
        .PC_INCREMENT(PC_INCREMENT)
    ) ifStage(
        .clk(clk),
        .rst(rst),
        .jump_address(pc_br),
        .jump_enable(jumpEnable),
        .pc_step_i(pc_step),
        .fetch_packet0(if_fetch_bus),
        .fetch_packet1(if_fetch_bus1)
    );

    // IF/ID is a two-entry fetch window. On single-issue cycles, slot1 slides
    // into slot0 so the younger fetched instruction is not lost.
    DualIF_IDRegister #(
        .RESET_PC(RESET_PC)
    ) if_id(
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

    // Decode maps the instruction word into typed control signals and register
    // address metadata. Register data is attached by topCPU below.
    IdStages #(
        .INSN_W(INSN_W),
        .REG_ADDR_W(REG_ADDR_W),
        .IMM_W(ADDR_W)
    ) idStage(
        .id_packet(if_decode_bus),
        .id_bus(id_exe_in_bus)
    );

    IdStages #(
        .INSN_W(INSN_W),
        .REG_ADDR_W(REG_ADDR_W),
        .IMM_W(ADDR_W)
    ) idStage1(
        .id_packet(if_decode_bus1),
        .id_bus(id_exe1_in_bus)
    );

    // Conservative in-order issue. slot0 always owns memory/control/CSR; slot1
    // issues only for independent simple integer instructions.
    DualIssueUnit #(
        .ADDR_W(ADDR_W),
        .REG_ADDR_W(REG_ADDR_W),
        .ZERO_REG('0),
        .SINGLE_STEP(PC_INCREMENT),
        .DUAL_STEP(PC_INCREMENT + PC_INCREMENT)
    ) issueUnit(
        .decode0_bus(id_exe_in_bus),
        .decode1_bus(id_exe1_in_bus),
        .exe0_bus(id_exe_bus),
        .stall(stall),
        .issue0(issue0),
        .issue1(issue1),
        .pc_step_o(pc_step)
    );

    assign wrEnable = !stall;

    // ID/EX injects a bubble on stalls/flushes so side effects are suppressed
    // while the front of the pipe is held or redirected.
    ID_EXERegister #(
        .RESET_PC(RESET_PC),
        .ZERO_REG('0)
    ) id_exe(
        .clk(clk),
        .rst(rst),
        .stall(stall),
        .flush(flush),
        .issueEnable(issue0),
        .id_bus_i(id_exe_in_bus),
        .exe_bus_o(id_exe_bus)
    );

    ID_EXERegister #(
        .RESET_PC(RESET_PC),
        .ZERO_REG('0)
    ) id_exe1(
        .clk(clk),
        .rst(rst),
        .stall(stall),
        .flush(flush),
        .issueEnable(issue1),
        .id_bus_i(id_exe1_in_bus),
        .exe_bus_o(id_exe1_bus)
    );

    // Keep result selection and bypass policy local to dedicated helpers so the
    // top level focuses on stage connectivity rather than datapath decisions.
    WritebackMux #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .PC_INCREMENT(PC_INCREMENT)
    ) exeResultMux(
        .wbSelect(exe_mem_bus.wbSelect),
        .pc(exe_mem_bus.pc),
        .aluData(exe_mem_bus.aluOut),
        .memData(rdData_mem),
        .immediate(exe_mem_bus.immediate),
        .csrData(exe_mem_bus.csrData),
        .result_o(result_mem)
    );

    WritebackMux #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .PC_INCREMENT(PC_INCREMENT)
    ) exeResultMux1(
        .wbSelect(exe_mem1_bus.wbSelect),
        .pc(exe_mem1_bus.pc),
        .aluData(exe_mem1_bus.aluOut),
        .memData(rdData1_mem),
        .immediate(exe_mem1_bus.immediate),
        .csrData(exe_mem1_bus.csrData),
        .result_o(result1_mem)
    );

    DualForwardingUnit #(
        .DATA_W(DATA_W),
        .REG_ADDR_W(REG_ADDR_W),
        .ZERO_REG('0)
    ) forwardingUnit0(
        .exe_bus(id_exe_bus),
        .mem0_bus(exe_mem_bus),
        .mem1_bus(exe_mem1_bus),
        .wb0_bus(mem_wb_bus),
        .wb1_bus(mem_wb1_bus),
        .mem0_result_i(result_mem),
        .mem1_result_i(result1_mem),
        .wb0_result_i(data_wb),
        .wb1_result_i(data1_wb),
        .dataA_o(forwardA_exe),
        .dataB_o(forwardB_exe)
    );

    DualForwardingUnit #(
        .DATA_W(DATA_W),
        .REG_ADDR_W(REG_ADDR_W),
        .ZERO_REG('0)
    ) forwardingUnit1(
        .exe_bus(id_exe1_bus),
        .mem0_bus(exe_mem_bus),
        .mem1_bus(exe_mem1_bus),
        .wb0_bus(mem_wb_bus),
        .wb1_bus(mem_wb1_bus),
        .mem0_result_i(result_mem),
        .mem1_result_i(result1_mem),
        .wb0_result_i(data_wb),
        .wb1_result_i(data1_wb),
        .dataA_o(forwardA1_exe),
        .dataB_o(forwardB1_exe)
    );

    // These adapters translate stage outputs into the next pipeline register's
    // bus shape, which keeps field packing out of the top-level wiring.
    ExeMemPrep exeMemPrep(
        .exe_bus(id_exe_bus),
        .storeData_i(forwardB_exe),
        .aluOut_i(aluOut_exe),
        .csrData_i(csrData_exe),
        .exe_mem_o(exe_mem_in_bus)
    );

    ExeMemPrep exeMemPrep1(
        .exe_bus(id_exe1_bus),
        .storeData_i(forwardB1_exe),
        .aluOut_i(aluOut1_exe),
        .csrData_i('0),
        .exe_mem_o(exe_mem1_in_bus)
    );

    MemWbPrep memWbPrep(
        .mem_bus(exe_mem_bus),
        .rdData_i(rdData_mem),
        .mem_wb_o(mem_wb_in_bus)
    );

    MemWbPrep memWbPrep1(
        .mem_bus(exe_mem1_bus),
        .rdData_i(rdData1_mem),
        .mem_wb_o(mem_wb1_in_bus)
    );

    ExeStages #(
        .DATA_W(DATA_W)
    ) exeStage(
        .exe_bus(id_exe_bus),
        .dataA(forwardA_exe),
        .dataB(forwardB_exe),
        .aluOut(aluOut_exe),
        .equal(equal),
        .lessThan(lessThan),
        .lessThanUnsigned(lessThanUnsigned)
    );

    ExeStages #(
        .DATA_W(DATA_W)
    ) exeStage1(
        .exe_bus(id_exe1_bus),
        .dataA(forwardA1_exe),
        .dataB(forwardB1_exe),
        .aluOut(aluOut1_exe),
        .equal(equal1),
        .lessThan(lessThan1),
        .lessThanUnsigned(lessThanUnsigned1)
    );

    // CSR file sits in EX so CSR read-modify-write instructions can read the
    // old CSR value and compute the new one in the same pipeline stage.
    CSRFile #(
        .RESET_VALUE(STATE_RESET_VALUE),
        .HART_ID('0)
    ) csrFile(
        .clk(clk),
        .rst(rst),
        .retireCount_i(retireCount),
        .csrValid_i(csrValid_exe),
        .csrOp_i(id_exe_bus.csrOp),
        .csrAddr_i(id_exe_bus.csrAddr),
        .csrWriteData_i(csrWriteData_exe),
        .csrReadData_o(csrData_exe)
    );

    // Branch/jump decision happens in EX. A taken redirect flushes IF/ID and
    // ID/EX through the shared flush signal.
    BranchCtr #(
        .ADDR_W(ADDR_W),
        .PC_INCREMENT(PC_INCREMENT)
    ) brCtr(
        .exe_bus(id_exe_bus),
        .equal(equal),
        .lessThan(lessThan),
        .lessThanUnsigned(lessThanUnsigned),
        .aluOut(aluOut_exe),
        .jumpEnable(jumpEnable),
        .pc_o(pc_br)
    );

    // Register the execute results before data memory.
    EXE_MEMRegister #(
        .RESET_PC(RESET_PC),
        .ZERO_REG('0)
    ) exe_mem(
        .clk(clk),
        .rst(rst),
        .exe_mem_i(exe_mem_in_bus),
        .exe_mem_o(exe_mem_bus)
    );

    EXE_MEMRegister #(
        .RESET_PC(RESET_PC),
        .ZERO_REG('0)
    ) exe_mem1(
        .clk(clk),
        .rst(rst),
        .exe_mem_i(exe_mem1_in_bus),
        .exe_mem_o(exe_mem1_bus)
    );

    // Data memory also implements the simple UART/fromhost/tohost MMIO region
    // used by CoreMark and riscv-tests.
    MEMStages #(
        .DATA_W(DATA_W),
        .LOGIC_ADDR_W(DATA_MEM_ADDR_W),
        .MEM_BYTES(DATA_MEM_BYTES),
        .UART_TX_MMIO_ADDR(UART_TX_MMIO_ADDR),
        .FROMHOST_MMIO_ADDR(FROMHOST_MMIO_ADDR),
        .TOHOST_MMIO_ADDR(TOHOST_MMIO_ADDR)
    ) memStage(
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

    // Register memory-stage values before final writeback selection.
    MEM_WBRegister #(
        .RESET_PC(RESET_PC),
        .ZERO_REG('0)
    ) mem_wb(
        .clk(clk),
        .rst(rst),
        .mem_wb_i(mem_wb_in_bus),
        .mem_wb_o(mem_wb_bus)
    );

    MEM_WBRegister #(
        .RESET_PC(RESET_PC),
        .ZERO_REG('0)
    ) mem_wb1(
        .clk(clk),
        .rst(rst),
        .mem_wb_i(mem_wb1_in_bus),
        .mem_wb_o(mem_wb1_bus)
    );

    // Select the value that is written to the architectural register file.
    WBStages #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .PC_INCREMENT(PC_INCREMENT)
    ) wbStage(
        .wb_bus(mem_wb_bus),
        .dataWB(data_wb)
    );

    WBStages #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .PC_INCREMENT(PC_INCREMENT)
    ) wbStage1(
        .wb_bus(mem_wb1_bus),
        .dataWB(data1_wb)
    );

endmodule
