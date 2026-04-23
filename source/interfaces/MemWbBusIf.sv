interface MemWbBusIf;
    import TypesPkg::*;

    logic              valid;
    instruction_addr_t pc;
    logic              registerWriteEnable;
    wb_select_t        wbSelect;
    instruction_addr_t immediate;
    word_t             aluSrc;
    word_t             rdData;
    word_t             csrData;
    reg_addr_t         rd;

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
