module controller
    import TypesPkg::*;
#(
    parameter int REG_ADDR_W = REG_ADDR,
    parameter logic [REG_ADDR_W-1:0] ZERO_REG = '0
)
(
    IdExeBusIf.sink decode_bus,
    IdExeBusIf.sink exe_bus,
    output logic    wrEnable,
    output logic    stall
);

    always_comb begin
        stall = exe_bus.registerWriteEnable &&
                (exe_bus.wbSelect == WB_MEM) &&
                (exe_bus.rd != ZERO_REG) &&
                ((decode_bus.useRs1 && (decode_bus.regA == exe_bus.rd)) ||
                 (decode_bus.useRs2 && (decode_bus.regB == exe_bus.rd)));

        wrEnable = ~stall;
    end

endmodule
