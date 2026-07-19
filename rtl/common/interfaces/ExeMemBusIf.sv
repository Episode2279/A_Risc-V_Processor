interface ExeMemBusIf;
    import TypesPkg::*;

    // Execute-to-memory bus. This captures the ALU/CSR results and the store
    // data after forwarding so MEM does not need to know about EX internals.
    logic              valid;
    instruction_addr_t pc;
    // Side-effect controls that must be preserved until writeback/memory.
    logic              registerWriteEnable;
    logic              dataWriteEnable;
    wb_select_t        wbSelect;
    mem_access_t       memCtr;
    // dataB is the forwarded store data for store instructions.
    word_t             dataB;
    reg_addr_t         rd;
    instruction_addr_t immediate;
    // ALU result is also the effective address for memory operations.
    word_t             aluOut;
    // Old CSR value used as the writeback result for CSR instructions.
    word_t             csrData;

    // Input side of the EX/MEM pipeline register.
    modport register_in(
        input valid,
        input pc,
        input registerWriteEnable,
        input dataWriteEnable,
        input wbSelect,
        input memCtr,
        input dataB,
        input rd,
        input immediate,
        input aluOut,
        input csrData
    );

    // Output side of the EX/MEM pipeline register.
    modport register_out(
        output valid,
        output pc,
        output registerWriteEnable,
        output dataWriteEnable,
        output wbSelect,
        output memCtr,
        output dataB,
        output rd,
        output immediate,
        output aluOut,
        output csrData
    );

    // Read-only view for MEM stage, forwarding, and writeback selection.
    modport sink(
        input valid,
        input pc,
        input registerWriteEnable,
        input dataWriteEnable,
        input wbSelect,
        input memCtr,
        input dataB,
        input rd,
        input immediate,
        input aluOut,
        input csrData
    );
endinterface
