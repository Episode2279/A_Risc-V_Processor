interface InstructionPacketIf;
    import TypesPkg::*;

    // Minimal IF-to-ID packet: the fetched instruction and the PC that fetched it.
    // Keeping these together prevents PC/instruction mismatches at stage boundaries.
    instruction_t      insn;
    instruction_addr_t pc;

    // Producer side used by IF and IF/ID outputs.
    modport source(
        output insn,
        output pc
    );

    // Consumer side used by IF/ID inputs and decode.
    modport sink(
        input insn,
        input pc
    );
endinterface
