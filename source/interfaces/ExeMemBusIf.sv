interface ExeMemBusIf;
    import TypesPkg::*;

    logic              valid;
    instruction_addr_t pc;
    logic              registerWriteEnable;
    logic              dataWriteEnable;
    wb_select_t        wbSelect;
    mem_access_t       memCtr;
    word_t             dataB;
    reg_addr_t         rd;
    instruction_addr_t immediate;
    word_t             aluOut;
    word_t             csrData;

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
