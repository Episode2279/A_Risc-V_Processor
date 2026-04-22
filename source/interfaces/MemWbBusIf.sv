interface MemWbBusIf;
    import TypesPkg::*;

    instruction_addr_t pc;
    logic              registerWriteEnable;
    wb_select_t        wbSelect;
    instruction_addr_t immediate;
    word_t             aluSrc;
    word_t             rdData;
    reg_addr_t         rd;

    modport register_in(
        input pc,
        input registerWriteEnable,
        input wbSelect,
        input immediate,
        input aluSrc,
        input rdData,
        input rd
    );

    modport register_out(
        output pc,
        output registerWriteEnable,
        output wbSelect,
        output immediate,
        output aluSrc,
        output rdData,
        output rd
    );

    modport sink(
        input pc,
        input registerWriteEnable,
        input wbSelect,
        input immediate,
        input aluSrc,
        input rdData,
        input rd
    );
endinterface
