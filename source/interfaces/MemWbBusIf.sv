interface MemWbBusIf;
    import TypesPkg::*;

    // Memory-to-writeback bus. By this point all possible writeback sources are
    // available, so WB only needs to select one and drive the register file.
    logic              valid;
    instruction_addr_t pc;
    logic              registerWriteEnable;
    wb_select_t        wbSelect;
    // Result candidates for the WB mux.
    instruction_addr_t immediate;
    word_t             aluSrc;
    word_t             rdData;
    word_t             csrData;
    reg_addr_t         rd;

    // Input side of the MEM/WB pipeline register.
    modport register_in(
        input valid,
        input pc,
        input registerWriteEnable,
        input wbSelect,
        input immediate,
        input aluSrc,
        input rdData,
        input csrData,
        input rd
    );

    // Output side of the MEM/WB pipeline register.
    modport register_out(
        output valid,
        output pc,
        output registerWriteEnable,
        output wbSelect,
        output immediate,
        output aluSrc,
        output rdData,
        output csrData,
        output rd
    );

    // Read-only view used by WB and forwarding logic.
    modport sink(
        input valid,
        input pc,
        input registerWriteEnable,
        input wbSelect,
        input immediate,
        input aluSrc,
        input rdData,
        input csrData,
        input rd
    );
endinterface
