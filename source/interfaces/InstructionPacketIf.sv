interface InstructionPacketIf;
    import TypesPkg::*;

    // Minimal IF-to-ID packet: the fetched instruction and the PC that fetched it.
    // Keeping these together prevents PC/instruction mismatches at stage boundaries.
    instruction_t      insn;
    instruction_addr_t pc;
    logic              predictedTaken;
    instruction_addr_t predictedTarget;
    bpu_index_t        predictorIndex;
    logic [BPU_HISTORY_WIDTH-1:0] historySnapshot;
    tage_meta_t        tageMeta;
    logic predictedBtbHit;
    logic predictedRasUsed;

    // Producer side used by IF and IF/ID outputs.
    modport source(
        output insn,
        output pc,
        output predictedTaken,
        output predictedTarget,
        output predictorIndex,
        output historySnapshot,
        output tageMeta
        ,output predictedBtbHit, predictedRasUsed
    );

    // Consumer side used by IF/ID inputs and decode.
    modport sink(
        input insn,
        input pc,
        input predictedTaken,
        input predictedTarget,
        input predictorIndex,
        input historySnapshot,
        input tageMeta
        ,input predictedBtbHit, predictedRasUsed
    );
endinterface
