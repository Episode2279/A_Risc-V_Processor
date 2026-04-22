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
);

    logic [ADDR_W-1:0] pc_br;

    logic [DATA_W-1:0] regDataA_id, regDataB_id;
    logic [DATA_W-1:0] forwardA_exe, forwardB_exe;
    logic [DATA_W-1:0] aluOut_exe;
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

    always_comb begin
        unique case (exe_mem_bus.wbSelect)
            WB_ALU: result_mem = exe_mem_bus.aluOut;
            WB_MEM: result_mem = rdData_mem;
            WB_PC4: result_mem = exe_mem_bus.pc + PC_INCREMENT;
            WB_IMM: result_mem = exe_mem_bus.immediate;
            default: result_mem = '0;
        endcase

        forwardA_exe = id_exe_bus.dataA;
        if (exe_mem_bus.registerWriteEnable && (exe_mem_bus.rd != '0) && (exe_mem_bus.rd == id_exe_bus.regA)) begin
            forwardA_exe = result_mem;
        end else if (mem_wb_bus.registerWriteEnable && (mem_wb_bus.rd != '0) && (mem_wb_bus.rd == id_exe_bus.regA)) begin
            forwardA_exe = data_wb;
        end

        forwardB_exe = id_exe_bus.dataB;
        if (exe_mem_bus.registerWriteEnable && (exe_mem_bus.rd != '0) && (exe_mem_bus.rd == id_exe_bus.regB)) begin
            forwardB_exe = result_mem;
        end else if (mem_wb_bus.registerWriteEnable && (mem_wb_bus.rd != '0) && (mem_wb_bus.rd == id_exe_bus.regB)) begin
            forwardB_exe = data_wb;
        end

        exe_mem_in_bus.pc = id_exe_bus.pc;
        exe_mem_in_bus.registerWriteEnable = id_exe_bus.registerWriteEnable;
        exe_mem_in_bus.dataWriteEnable = id_exe_bus.dataWriteEnable;
        exe_mem_in_bus.wbSelect = id_exe_bus.wbSelect;
        exe_mem_in_bus.memCtr = id_exe_bus.memCtr;
        exe_mem_in_bus.dataB = forwardB_exe;
        exe_mem_in_bus.rd = id_exe_bus.rd;
        exe_mem_in_bus.immediate = id_exe_bus.immediate;
        exe_mem_in_bus.aluOut = aluOut_exe;

        mem_wb_in_bus.pc = exe_mem_bus.pc;
        mem_wb_in_bus.registerWriteEnable = exe_mem_bus.registerWriteEnable;
        mem_wb_in_bus.wbSelect = exe_mem_bus.wbSelect;
        mem_wb_in_bus.immediate = exe_mem_bus.immediate;
        mem_wb_in_bus.aluSrc = exe_mem_bus.aluOut;
        mem_wb_in_bus.rdData = rdData_mem;
        mem_wb_in_bus.rd = exe_mem_bus.rd;
    end

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
        .uartData_o(uartData_o)
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
        .PC_INCREMENT(PC_INCREMENT)
    ) wbStage(
        .wb_bus(mem_wb_bus),
        .dataWB(data_wb)
    );

endmodule
