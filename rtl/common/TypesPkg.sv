package TypesPkg;

    // Central package for project-wide data widths, memory sizes, and control types.
    // Modules may override these defaults locally, but these values define the
    // baseline RV32-style configuration used by the current core.

    // Width of the main integer datapath, register file entries, and ALU results.
    parameter int WORD_SIZE = 32;
    // Width of one fetched instruction word.
    parameter int INS_SIZE = 32;
    // Generic small block width used by utility logic that handles byte-like data.
    parameter int BLOCK_SIZE = 8;
    // Total instruction memory capacity in bytes.
    parameter int INS_ADDR_SIZE = 65536;
    // Total data memory capacity in bytes.
    parameter int DATA_ADDR_SIZE = 65536;
    // Number of architectural integer registers in the register file.
    parameter int REG_NUM = 32;
    // Encoded width needed to address one register entry.
    parameter int REG_ADDR = 5;

    // Initial out-of-order configuration.  These sizes are deliberately small
    // enough for simulation and FPGA experiments while the new back end is
    // brought up incrementally.
    parameter int PHYS_REG_NUM = 48;
    parameter int ROB_ENTRY_NUM = 16;
    // The unified scheduler and LSQ are independent storage structures.  A
    // memory uop occupies one entry in each, but changing one capacity must not
    // silently resize the other.
    parameter int UNIFIED_IQ_ENTRY_NUM = 16;
    parameter int LSQ_ENTRY_NUM = 16;
    parameter int STORE_BUFFER_ENTRY_NUM = 8;
    // Index width for the 1K-entry PC-indexed Bimodal base predictor.
    parameter int BPU_BASE_INDEX_WIDTH = 10;
    // Compatibility width for the existing packet/checkpoint ports.  Bimodal
    // drives their history snapshots to zero and owns no GHR.
    parameter int BPU_HISTORY_WIDTH = BPU_BASE_INDEX_WIDTH;
    // TAGE owns the speculative global direction history; the Bimodal base has
    // no history register.
    parameter int TAGE_HISTORY_WIDTH = 192;
    // A compact speculative signature of the recent control-flow path.  It is
    // kept separate from the direction GHR so identical Taken/Not-taken
    // sequences reached through different static branches can hash apart.
    parameter int TAGE_PATH_HISTORY_WIDTH = 16;
    parameter int TAGE_TABLE_NUM = 8;
    parameter int TAGE_TABLE_ENTRIES = 512;
    // Entry generations revalidate a prediction-time Provider after queued
    // retirement training.  Five bits provide 32 distinct versions, exceeding
    // the current ROB/front-end bound on simultaneously live replacements.
    parameter int TAGE_GENERATION_WIDTH = 5;
    parameter int LOOP_TABLE_ENTRIES = 64;
    parameter int LOOP_TAG_WIDTH = 12;
    parameter int LOOP_ITER_WIDTH = 10;
    parameter int LOOP_CONFIDENCE_WIDTH = 3;
    parameter int LOOP_AGE_WIDTH = 2;
    parameter int LOOP_GENERATION_WIDTH = 4;
    parameter int LOOP_ACTION_DEPTH = 32;
    // TAGE-SC-L-style Statistical Corrector geometry.  Global GEHL follows the
    // direction GHR, Local GEHL follows a per-PC history, and IMLI GEHL sees
    // the speculative innermost-loop iteration count.  Dedicated Path GEHL
    // and a second independently indexed Bias table replace correlated
    // Global/IMLI capacity without increasing the signed-counter budget.
    parameter int SC_COUNTER_WIDTH = 6;
    parameter int SC_BIAS_TABLE_NUM = 2;
    parameter int SC_BIAS_TABLE_ENTRIES = 256;
    parameter int SC_GLOBAL_GEHL_TABLE_NUM = 6;
    parameter int SC_GLOBAL_GEHL_TABLE_ENTRIES = 256;
    parameter int SC_LOCAL_HISTORY_ENTRIES = 256;
    parameter int SC_LOCAL_HISTORY_WIDTH = 12;
    parameter int SC_LOCAL_GEHL_TABLE_NUM = 4;
    parameter int SC_LOCAL_GEHL_TABLE_ENTRIES = 512;
    parameter int SC_IMLI_WIDTH = 10;
    parameter int SC_IMLI_GEHL_TABLE_NUM = 3;
    parameter int SC_IMLI_GEHL_TABLE_ENTRIES = 256;
    parameter int SC_PATH_GEHL_TABLE_NUM = 3;
    parameter int SC_PATH_GEHL_TABLE_ENTRIES = 256;
    parameter int SC_THRESHOLD_TABLE_ENTRIES = 32;
    parameter int SC_THRESHOLD_COUNTER_WIDTH = 6;
    parameter int SC_SCORE_WIDTH = 12;
    parameter int SC_FEATURE_FAMILY_NUM = 5;
    // CBP-style logical predictor-state accounting.  This configuration is
    // deliberately bounded by a 16 KiB design point.
    parameter int BPU_CBP_STORAGE_LIMIT_BITS = 16 * 1024 * 8;
    parameter bit BPU_ENFORCE_CBP_STORAGE_LIMIT = 1'b1;
    // The current eight-table tag schedule is 7/8/9/10/11/12/13/14 bits.
    // Derive the
    // logical budget from geometry so another entry-count experiment cannot
    // leave a stale hand-written capacity constant behind.
    parameter int BPU_BIMODAL_STORAGE_BITS =
        (1 << BPU_BASE_INDEX_WIDTH) * 2;
    parameter int BPU_TAGE_TAG_STORAGE_BITS =
        TAGE_TABLE_ENTRIES * (7 + 8 + 9 + 10 + 11 + 12 + 13 + 14);
    parameter int BPU_TAGE_AUX_STORAGE_BITS =
        TAGE_TABLE_NUM * TAGE_TABLE_ENTRIES *
        (1 + 3 + 2 + TAGE_GENERATION_WIDTH);
    parameter int BPU_TAGE_FOLD_STORAGE_BITS =
        TAGE_TABLE_NUM * $clog2(TAGE_TABLE_ENTRIES) +
        (7 + 8 + 9 + 10 + 11 + 12 + 13 + 14) +
        (6 + 7 + 8 + 9 + 10 + 11 + 12 + 13);
    parameter int BPU_TAGE_CONTROL_STORAGE_BITS =
        TAGE_HISTORY_WIDTH + TAGE_PATH_HISTORY_WIDTH +
        BPU_TAGE_FOLD_STORAGE_BITS +
        (8 * 4) + (4 * 2) + 8 + 8 + $clog2(TAGE_TABLE_ENTRIES);
    parameter int BPU_TAGE_BIMODAL_STORAGE_BITS =
        BPU_BIMODAL_STORAGE_BITS + BPU_TAGE_TAG_STORAGE_BITS +
        BPU_TAGE_AUX_STORAGE_BITS + BPU_TAGE_CONTROL_STORAGE_BITS;
    parameter int BPU_LOOP_STORAGE_BITS =
        LOOP_TABLE_ENTRIES *
        (1 + LOOP_TAG_WIDTH + LOOP_ITER_WIDTH + LOOP_ITER_WIDTH +
         LOOP_CONFIDENCE_WIDTH + LOOP_AGE_WIDTH + 1 +
         LOOP_GENERATION_WIDTH);
    parameter int BPU_SC_COUNTER_STORAGE_BITS =
        (SC_BIAS_TABLE_NUM * SC_BIAS_TABLE_ENTRIES * SC_COUNTER_WIDTH) +
        (SC_GLOBAL_GEHL_TABLE_NUM * SC_GLOBAL_GEHL_TABLE_ENTRIES *
         SC_COUNTER_WIDTH) +
        (SC_LOCAL_GEHL_TABLE_NUM * SC_LOCAL_GEHL_TABLE_ENTRIES *
         SC_COUNTER_WIDTH) +
        (SC_IMLI_GEHL_TABLE_NUM * SC_IMLI_GEHL_TABLE_ENTRIES *
         SC_COUNTER_WIDTH) +
        (SC_PATH_GEHL_TABLE_NUM * SC_PATH_GEHL_TABLE_ENTRIES *
         SC_COUNTER_WIDTH);
    parameter int BPU_SC_AUX_STORAGE_BITS =
        (SC_LOCAL_HISTORY_ENTRIES * SC_LOCAL_HISTORY_WIDTH) +
        (SC_THRESHOLD_TABLE_ENTRIES * SC_THRESHOLD_COUNTER_WIDTH) +
        SC_IMLI_WIDTH;
    parameter int BPU_SC_STORAGE_BITS =
        BPU_SC_COUNTER_STORAGE_BITS + BPU_SC_AUX_STORAGE_BITS;
    // Eight 8-bit incrementally maintained global-history folds feed SC.
    parameter int BPU_SC_FOLD_STORAGE_BITS =
        SC_GLOBAL_GEHL_TABLE_NUM *
        $clog2(SC_GLOBAL_GEHL_TABLE_ENTRIES);
    parameter int BPU_TOTAL_STORAGE_BITS =
        BPU_TAGE_BIMODAL_STORAGE_BITS + BPU_SC_STORAGE_BITS +
        BPU_LOOP_STORAGE_BITS +
        BPU_SC_FOLD_STORAGE_BITS;

    // Derived address widths used by memory index signals inside the design.
    localparam int INS_ADDR = $clog2(INS_ADDR_SIZE);
    localparam int DATA_ADDR = $clog2(DATA_ADDR_SIZE);
    localparam int PHYS_REG_ADDR = $clog2(PHYS_REG_NUM);
    localparam int ROB_INDEX = $clog2(ROB_ENTRY_NUM);
    localparam int LSQ_INDEX = $clog2(LSQ_ENTRY_NUM);

    // Common scalar types shared across modules and interfaces.
    typedef logic [WORD_SIZE-1:0] word_t;
    typedef logic [INS_SIZE-1:0] instruction_t;
    typedef logic [BLOCK_SIZE-1:0] block_t;
    typedef logic [DATA_ADDR-1:0] data_addr_t;
    typedef logic [REG_ADDR-1:0] reg_addr_t;
    typedef logic [11:0] csr_addr_t;
    typedef logic [PHYS_REG_ADDR-1:0] phys_reg_addr_t;
    typedef logic [ROB_INDEX-1:0] rob_tag_t;
    typedef logic [LSQ_INDEX-1:0] lsq_tag_t;
    typedef logic [BPU_BASE_INDEX_WIDTH-1:0] bpu_index_t;
    typedef logic [TAGE_HISTORY_WIDTH-1:0] tage_history_t;
    typedef logic [TAGE_PATH_HISTORY_WIDTH-1:0] tage_path_history_t;
    typedef logic [TAGE_GENERATION_WIDTH-1:0] tage_generation_t;
    typedef logic [$clog2(TAGE_TABLE_NUM)-1:0] tage_provider_t;
    typedef logic [$clog2(LOOP_TABLE_ENTRIES)-1:0] loop_index_t;
    typedef logic [LOOP_TAG_WIDTH-1:0] loop_tag_t;
    typedef logic [LOOP_ITER_WIDTH-1:0] loop_iter_t;
    typedef logic [LOOP_GENERATION_WIDTH-1:0] loop_generation_t;
    typedef logic [$clog2(LOOP_ACTION_DEPTH)-1:0] loop_action_ptr_t;
    typedef logic [SC_LOCAL_HISTORY_WIDTH-1:0] sc_local_history_t;
    typedef logic [SC_IMLI_WIDTH-1:0] sc_imli_t;
    typedef logic signed [SC_SCORE_WIDTH-1:0] sc_score_t;
    // Program counter and instruction addresses use full datapath width.
    typedef word_t instruction_addr_t;

    typedef struct packed {
        logic             hit;
        logic             confident;
        logic             prediction;
        logic             used;
        loop_index_t      tableIndex;
        loop_tag_t        tag;
        loop_generation_t generation;
        loop_iter_t       iterationBefore;
        loop_iter_t       tripCount;
        logic             direction;
        loop_action_ptr_t checkpointTail;
    } loop_meta_t;

    // Prediction-time metadata retained until a control-flow instruction retires.
    // Index/tag values are recomputed from pc+history at commit so table
    // geometry remains local to the TAGE implementation.
    typedef struct packed {
        tage_history_t history;
        tage_path_history_t pathHistory;
        logic           providerValid;
        tage_provider_t provider;
        tage_generation_t providerGeneration;
        logic           providerPrediction;
        logic           alternatePrediction;
        // Raw TAGE/UAN direction before the statistical corrector.  TAGE
        // allocation and provider training use this value so an SC correction
        // cannot hide a residual TAGE miss.
        logic           tagePrediction;
        // Direction after the optional Loop Predictor but before SC.  Keeping
        // this separately makes Loop and SC attribution unambiguous.
        logic           preScPrediction;
        logic           finalPrediction;
        logic           providerWeak;
        sc_local_history_t scLocalHistory;
        sc_imli_t       scImli;
        sc_score_t      scScore;
        logic [SC_FEATURE_FAMILY_NUM-1:0] scFamilyTaken;
        logic [SC_FEATURE_FAMILY_NUM-1:0] scFamilyValid;
        logic           scLowConfidence;
        loop_meta_t     loop;
    } tage_meta_t;

    // Stored representation used by the decoupled front-end fetch queue.
    typedef struct packed {
        instruction_t      insn;
        instruction_addr_t pc;
        logic              predictedTaken;
        instruction_addr_t predictedTarget;
        bpu_index_t        predictorIndex;
        logic [BPU_HISTORY_WIDTH-1:0] historySnapshot;
        tage_meta_t        tageMeta;
        logic              predictedBtbHit;
        logic              predictedRasUsed;
    } fetch_packet_t;

    // A retired TAGE training event.  Direction-table writes may be delayed by
    // the banked update path, while committed-history state advances when this
    // record is accepted into the queue.
    typedef struct packed {
        logic              isConditional;
        instruction_addr_t pc;
        logic              taken;
        tage_meta_t        meta;
    } tage_update_t;

    // Reset and MMIO map used by the testbench and software images.
    localparam word_t RESET_VECTOR = '0;
    localparam word_t UART_TX_ADDR = 32'h0000_FFE0;
    localparam word_t FROMHOST_ADDR = 32'h0000_FFF0;
    localparam word_t TOHOST_ADDR = 32'h0000_FFF8;

    localparam logic [5:0] EXC_INSN_ADDR_MISALIGNED = 6'd0;
    localparam logic [5:0] EXC_ILLEGAL_INSN         = 6'd2;
    localparam logic [5:0] EXC_BREAKPOINT           = 6'd3;
    localparam logic [5:0] EXC_LOAD_ADDR_MISALIGNED = 6'd4;
    localparam logic [5:0] EXC_STORE_ADDR_MISALIGNED = 6'd6;
    localparam logic [5:0] EXC_ECALL_MMODE          = 6'd11;

    // ALU control encoding selected by the decoder/controller path.
    typedef enum logic [3:0] {
        ALU_ADD  = 4'd0,
        ALU_SUB  = 4'd1,
        ALU_AND  = 4'd2,
        ALU_OR   = 4'd3,
        ALU_XOR  = 4'd4,
        ALU_SLL  = 4'd5,
        ALU_SRL  = 4'd6,
        ALU_SRA  = 4'd7,
        ALU_SLT  = 4'd8,
        ALU_SLTU = 4'd9,
        ALU_PASS = 4'd10
    } alu_ctr_t;

    // Write-back source selection for the final result sent to the register file.
    typedef enum logic [2:0] {
        WB_ALU = 3'd0,
        WB_MEM = 3'd1,
        WB_PC4 = 3'd2,
        WB_IMM = 3'd3,
        WB_CSR = 3'd4
    } wb_select_t;

    // CSR operation selected by SYSTEM instructions. Immediate CSR variants
    // reuse these operations with a zero-extended zimm source value.
    typedef enum logic [1:0] {
        CSR_NONE = 2'd0,
        CSR_RW   = 2'd1,
        CSR_RS   = 2'd2,
        CSR_RC   = 2'd3
    } csr_op_t;

    // Branch/jump operation selected in decode and resolved in execute.
    typedef enum logic [3:0] {
        BR_NONE = 4'd0,
        BR_BEQ  = 4'd1,
        BR_BNE  = 4'd2,
        BR_BLT  = 4'd3,
        BR_BGE  = 4'd4,
        BR_BLTU = 4'd5,
        BR_BGEU = 4'd6,
        BR_JAL  = 4'd7,
        BR_JALR = 4'd8,
        BR_MRET = 4'd9
    } branch_ctr_t;

    // Load/store access type used by the data memory for sign/zero extension
    // and write masking behavior.
    typedef enum logic [2:0] {
        MEM_BYTE   = 3'b000,
        MEM_HALF   = 3'b001,
        MEM_WORD   = 3'b010,
        MEM_BYTE_U = 3'b100,
        MEM_HALF_U = 3'b101
    } mem_access_t;

    typedef enum logic [2:0] {
        FU_INTEGER = 3'd0,
        FU_BRANCH  = 3'd1,
        FU_MEMORY  = 3'd2,
        FU_CSR     = 3'd3
    } fu_class_t;

    // Micro-op format at the rename/dispatch boundary. Architectural source
    // names have already been translated to physical-register tags here.
    typedef struct packed {
        logic              valid;
        instruction_addr_t pc;
        logic              predictedTaken;
        instruction_addr_t predictedTarget;
        bpu_index_t        predictorIndex;
        logic [BPU_HISTORY_WIDTH-1:0] historySnapshot;
        logic              predictedBtbHit;
        logic              predictedRasUsed;
        logic              isCall;
        logic              isReturn;
        fu_class_t         fuClass;
        logic              registerWriteEnable;
        logic              dataWriteEnable;
        wb_select_t        wbSelect;
        csr_op_t           csrOp;
        csr_addr_t         csrAddr;
        logic              csrUseImm;
        word_t             csrImm;
        branch_ctr_t       branchCtr;
        alu_ctr_t          aluCtr;
        mem_access_t       memCtr;
        logic              aluSrcASelect;
        logic              aluSrcBSelect;
        logic              useRs1;
        logic              useRs2;
        phys_reg_addr_t    src1Phys;
        phys_reg_addr_t    src2Phys;
        logic              src1Ready;
        logic              src2Ready;
        phys_reg_addr_t    destPhys;
        rob_tag_t          robTag;
        lsq_tag_t          lsqTag;
        instruction_addr_t immediate;
        logic              decodeException;
        logic [5:0]        decodeExceptionCause;
        word_t             exceptionValue;
        logic              serialize;
        logic              mret;
    } renamed_uop_t;

    typedef struct packed {
        logic              valid;
        instruction_addr_t pc;
        logic              isConditional;
        logic              isCall;
        logic              isReturn;
        logic              taken;
        instruction_addr_t target;
        logic              mispredicted;
        logic              predictedTaken;
        instruction_addr_t predictedTarget;
        logic              predictedBtbHit;
        logic              predictedRasUsed;
        bpu_index_t        predictorIndex;
        tage_meta_t        tageMeta;
        branch_ctr_t       branchCtr;
    } bpu_train_t;

    // ROB state does not carry ordinary result data: completed integer results
    // live in the PRF. The ROB records ordering and retirement metadata.
    typedef struct packed {
        logic              valid;
        logic              complete;
        instruction_addr_t pc;
        logic              writesRd;
        reg_addr_t         archRd;
        phys_reg_addr_t    newPhys;
        phys_reg_addr_t    oldPhys;
        logic              isMemory;
        lsq_tag_t          lsqTag;
        logic              isStore;
        logic              isBranch;
        branch_ctr_t       branchCtr;
        logic              isCall;
        logic              isReturn;
        logic              predictedTaken;
        instruction_addr_t predictedTarget;
        logic              predictedBtbHit;
        logic              predictedRasUsed;
        bpu_index_t        predictorIndex;
        tage_meta_t        tageMeta;
        logic              branchTaken;
        instruction_addr_t branchTarget;
        logic              branchMispredicted;
        logic              isCsr;
        logic              exception;
        logic [5:0]        exceptionCause;
        word_t             exceptionValue;
        logic              mret;
    } rob_entry_t;

    typedef struct packed {
        logic              valid;
        logic              isLoad;
        logic              isStore;
        rob_tag_t          robTag;
        phys_reg_addr_t    destPhys;
        mem_access_t       memCtr;
        instruction_addr_t pc;
        logic              addressReady;
        word_t             address;
        logic              dataReady;
        phys_reg_addr_t    storeDataPhys;
        word_t             storeData;
    } lsq_entry_t;

endpackage
