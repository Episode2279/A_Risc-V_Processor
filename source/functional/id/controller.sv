module controller
    import TypesPkg::*;
#(
    // Register address width and zero-register encoding are parameterized so
    // the hazard unit stays aligned with RegisterFile configuration.
    parameter int REG_ADDR_W = REG_ADDR,
    parameter logic [REG_ADDR_W-1:0] ZERO_REG = '0
)
(
    // decode_bus is the instruction currently in ID; exe_bus is the instruction
    // directly ahead of it in EX.
    IdExeBusIf.sink decode_bus,
    IdExeBusIf.sink exe_bus,
    // wrEnable freezes PC and IF/ID when a one-cycle load-use hazard appears.
    output logic    wrEnable,
    output logic    stall
);

    always_comb begin
        // Forwarding handles ALU-to-ALU dependencies, but a load value is not
        // available until MEM. If ID consumes the EX load destination, insert
        // one bubble by stalling fetch/decode and clearing ID/EX.
        stall = exe_bus.registerWriteEnable &&
                (exe_bus.wbSelect == WB_MEM) &&
                (exe_bus.rd != ZERO_REG) &&
                ((decode_bus.useRs1 && (decode_bus.regA == exe_bus.rd)) ||
                 (decode_bus.useRs2 && (decode_bus.regB == exe_bus.rd)));

        // The fetch stage and IF/ID register advance only when no bubble is
        // needed for the load-use dependency.
        wrEnable = ~stall;
    end

endmodule
