interface InstructionPacketIf;
    import TypesPkg::*;

    instruction_t      insn;
    instruction_addr_t pc;

    modport source(
        output insn,
        output pc
    );

    modport sink(
        input insn,
        input pc
    );
endinterface
