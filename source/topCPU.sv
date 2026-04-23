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
    // Simulation debug ports mirror the Vivado testbench pipeline dump schema.
    // They keep the Verilator harness independent from generated hierarchy names.
    output logic              dbg_wrEnable,
    output logic              dbg_stall,
    output logic              dbg_flush,
    output logic              dbg_jumpEnable,
    output logic              dbg_if_valid,
    output logic [ADDR_W-1:0] dbg_if_pc,
    output logic [INSN_W-1:0] dbg_if_insn,
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
    output logic [ADDR_W-1:0] dbg_ex_pc,
    output logic [REG_ADDR_W-1:0] dbg_ex_rd,
    output logic              dbg_ex_regWrite,
    output logic              dbg_ex_memWrite,
    output logic [2:0]        dbg_ex_memCtr,
    output logic [DATA_W-1:0] dbg_ex_aluOut,
    output logic [DATA_W-1:0] dbg_ex_dataA,
    output logic [DATA_W-1:0] dbg_ex_dataB,
    output logic [ADDR_W-1:0] dbg_ex_imm,
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
    output logic [ADDR_W-1:0] dbg_wb_pc,
    output logic [REG_ADDR_W-1:0] dbg_wb_rd,
    output logic              dbg_wb_regWrite,
    output logic [2:0]        dbg_wb_wbSelect,
    output logic [DATA_W-1:0] dbg_wb_aluSrc,
    output logic [DATA_W-1:0] dbg_wb_rdData,
    output logic [DATA_W-1:0] dbg_wb_dataWb
`endif
);

    logic [ADDR_W-1:0] pc_br;

    logic [DATA_W-1:0] regDataA_id, regDataB_id;
    logic [DATA_W-1:0] forwardA_exe, forwardB_exe;
    logic [DATA_W-1:0] aluOut_exe;
    logic [DATA_W-1:0] csrData_exe;
    logic [DATA_W-1:0] csrWriteData_exe;
    logic [DATA_W-1:0] rdData_mem;
    logic [DATA_W-1:0] data_wb;
    logic [DATA_W-1:0] result_mem;

    logic equal;
    logic lessThan;
    logic lessThanUnsigned;
    logic jumpEnable;
    logic wrEnable;
    logic stall;
    logic flush;
    logic csrValid_exe;
    logic memToHostHit;
    logic memUartHit;
    logic memFromHostHit;

    InstructionPacketIf if_fetch_bus();
    InstructionPacketIf if_decode_bus();
    IdExeBusIf          id_exe_in_bus();
    IdExeBusIf          id_exe_bus();
    ExeMemBusIf         exe_mem_in_bus();
    ExeMemBusIf         exe_mem_bus();
    MemWbBusIf          mem_wb_in_bus();
    MemWbBusIf          mem_wb_bus();

    assign check = if_fetch_bus.insn;
    assign checkPC = if_fetch_bus.pc;
    assign checkData = data_wb;
    assign flush = jumpEnable;
    assign id_exe_in_bus.dataA = regDataA_id;
    assign id_exe_in_bus.dataB = regDataB_id;
    assign csrWriteData_exe = id_exe_bus.csrUseImm ? id_exe_bus.csrImm : forwardA_exe;
    assign csrValid_exe = id_exe_bus.valid && (id_exe_bus.wbSelect == WB_CSR);

`ifdef VERILATOR
    assign dbg_wrEnable = wrEnable;
    assign dbg_stall = stall;
    assign dbg_flush = flush;
    assign dbg_jumpEnable = jumpEnable;
    assign dbg_if_valid = (if_fetch_bus.insn != '0);
    assign dbg_if_pc = if_fetch_bus.pc;
    assign dbg_if_insn = if_fetch_bus.insn;
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
    assign dbg_ex_pc = id_exe_bus.pc;
    assign dbg_ex_rd = id_exe_bus.rd;
    assign dbg_ex_regWrite = id_exe_bus.registerWriteEnable;
    assign dbg_ex_memWrite = id_exe_bus.dataWriteEnable;
    assign dbg_ex_memCtr = id_exe_bus.memCtr;
    assign dbg_ex_aluOut = aluOut_exe;
    assign dbg_ex_dataA = forwardA_exe;
    assign dbg_ex_dataB = forwardB_exe;
    assign dbg_ex_imm = id_exe_bus.immediate;
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
    assign dbg_wb_pc = mem_wb_bus.pc;
    assign dbg_wb_rd = mem_wb_bus.rd;
    assign dbg_wb_regWrite = mem_wb_bus.registerWriteEnable;
    assign dbg_wb_wbSelect = mem_wb_bus.wbSelect;
    assign dbg_wb_aluSrc = mem_wb_bus.aluSrc;
    assign dbg_wb_rdData = mem_wb_bus.rdData;
    assign dbg_wb_dataWb = data_wb;
`endif

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
        .rdAddrA(id_exe_in_bus.regA),
        .rdAddrB(id_exe_in_bus.regB),
        .rdA(regDataA_id),
        .rdB(regDataB_id)
    );

    IfStages #(
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
        .wrEnable(wrEnable),
        .fetch_packet(if_fetch_bus)
    );

    IF_IDRegister #(
        .RESET_PC(RESET_PC)
    ) if_id(
        .clk(clk),
        .rst(rst),
        .packet_i(if_fetch_bus),
        .stall(stall),
        .flush(flush),
        .packet_o(if_decode_bus)
    );

    IdStages #(
        .INSN_W(INSN_W),
        .REG_ADDR_W(REG_ADDR_W),
        .IMM_W(ADDR_W)
    ) idStage(
        .id_packet(if_decode_bus),
        .id_bus(id_exe_in_bus)
    );

    controller #(
        .REG_ADDR_W(REG_ADDR_W)
    ) control(
        .decode_bus(id_exe_in_bus),
        .exe_bus(id_exe_bus),
        .wrEnable(wrEnable),
        .stall(stall)
    );

    ID_EXERegister #(
        .RESET_PC(RESET_PC),
        .ZERO_REG('0)
    ) id_exe(
        .clk(clk),
        .rst(rst),
        .stall(stall),
        .flush(flush),
        .id_bus_i(id_exe_in_bus),
        .exe_bus_o(id_exe_bus)
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

    ForwardingUnit #(
        .DATA_W(DATA_W),
        .REG_ADDR_W(REG_ADDR_W),
        .ZERO_REG('0)
    ) forwardingUnit(
        .exe_bus(id_exe_bus),
        .mem_bus(exe_mem_bus),
        .wb_bus(mem_wb_bus),
        .mem_result_i(result_mem),
        .wb_result_i(data_wb),
        .dataA_o(forwardA_exe),
        .dataB_o(forwardB_exe)
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

    MemWbPrep memWbPrep(
        .mem_bus(exe_mem_bus),
        .rdData_i(rdData_mem),
        .mem_wb_o(mem_wb_in_bus)
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

    CSRFile #(
        .RESET_VALUE(STATE_RESET_VALUE),
        .HART_ID('0)
    ) csrFile(
        .clk(clk),
        .rst(rst),
        .retire_i(mem_wb_bus.valid),
        .csrValid_i(csrValid_exe),
        .csrOp_i(id_exe_bus.csrOp),
        .csrAddr_i(id_exe_bus.csrAddr),
        .csrWriteData_i(csrWriteData_exe),
        .csrReadData_o(csrData_exe)
    );

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

    EXE_MEMRegister #(
        .RESET_PC(RESET_PC),
        .ZERO_REG('0)
    ) exe_mem(
        .clk(clk),
        .rst(rst),
        .exe_mem_i(exe_mem_in_bus),
        .exe_mem_o(exe_mem_bus)
    );

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

    MEM_WBRegister #(
        .RESET_PC(RESET_PC),
        .ZERO_REG('0)
    ) mem_wb(
        .clk(clk),
        .rst(rst),
        .mem_wb_i(mem_wb_in_bus),
        .mem_wb_o(mem_wb_bus)
    );

    WBStages #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .PC_INCREMENT(PC_INCREMENT)
    ) wbStage(
        .wb_bus(mem_wb_bus),
        .dataWB(data_wb)
    );

endmodule
