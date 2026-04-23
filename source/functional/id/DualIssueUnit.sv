module DualIssueUnit
    import TypesPkg::*;
#(
    parameter int ADDR_W = WORD_SIZE,
    parameter int REG_ADDR_W = REG_ADDR,
    parameter logic [REG_ADDR_W-1:0] ZERO_REG = '0,
    parameter logic [ADDR_W-1:0] SINGLE_STEP = 32'd4,
    parameter logic [ADDR_W-1:0] DUAL_STEP = 32'd8
)
(
    // slot0 is the older instruction at PC; slot1 is the younger instruction
    // at PC+4. This first dual-issue policy is intentionally conservative.
    IdExeBusIf.sink decode0_bus,
    IdExeBusIf.sink decode1_bus,
    IdExeBusIf.sink exe0_bus,
    output logic    stall,
    output logic    issue0,
    output logic    issue1,
    output logic [ADDR_W-1:0] pc_step_o
);

    logic loadUseSlot0;
    logic loadUseSlot1;
    logic slot0WritesRd;
    logic slot1DependsOnSlot0;
    logic slot0IsControl;
    logic slot1IsControl;
    logic slot0IsCsr;
    logic slot1IsCsr;
    logic slot1IsMemory;

    always_comb begin
        slot0WritesRd = decode0_bus.valid &&
                        decode0_bus.registerWriteEnable &&
                        (decode0_bus.rd != ZERO_REG);

        loadUseSlot0 = exe0_bus.registerWriteEnable &&
                       (exe0_bus.wbSelect == WB_MEM) &&
                       (exe0_bus.rd != ZERO_REG) &&
                       ((decode0_bus.useRs1 && (decode0_bus.regA == exe0_bus.rd)) ||
                        (decode0_bus.useRs2 && (decode0_bus.regB == exe0_bus.rd)));

        loadUseSlot1 = exe0_bus.registerWriteEnable &&
                       (exe0_bus.wbSelect == WB_MEM) &&
                       (exe0_bus.rd != ZERO_REG) &&
                       ((decode1_bus.regA == exe0_bus.rd) ||
                        (decode1_bus.regB == exe0_bus.rd));

        slot1DependsOnSlot0 = slot0WritesRd &&
                              ((decode1_bus.regA == decode0_bus.rd) ||
                               (decode1_bus.regB == decode0_bus.rd));

        slot0IsControl = (decode0_bus.branchCtr != BR_NONE);
        slot1IsControl = (decode1_bus.branchCtr != BR_NONE);
        slot0IsCsr = (decode0_bus.wbSelect == WB_CSR);
        slot1IsCsr = (decode1_bus.wbSelect == WB_CSR);
        slot1IsMemory = decode1_bus.dataWriteEnable || (decode1_bus.wbSelect == WB_MEM);

        // If the older slot depends on a load currently in EX, the original
        // single-issue load-use stall is still required.
        stall = loadUseSlot0;

        // If the fetch window is empty after reset/flush, do not issue a real
        // instruction; just ask IF to fetch a full two-instruction window.
        issue0 = !stall && decode0_bus.valid;

        // Conservative second slot:
        //   - no memory, branch/jump, or CSR in slot1 yet
        //   - no branch/CSR in slot0, so precise redirect/CSR ordering is easy
        //   - no RAW dependency from slot0 to slot1
        //   - no dependency on an EX-stage load
        issue1 = issue0 &&
                 decode0_bus.valid &&
                 decode1_bus.valid &&
                 !slot0IsControl &&
                 !slot1IsControl &&
                 !slot0IsCsr &&
                 !slot1IsCsr &&
                 !slot1IsMemory &&
                 !slot1DependsOnSlot0 &&
                 !loadUseSlot1;

        if (stall) begin
            pc_step_o = '0;
        end else if (!decode0_bus.valid && !decode1_bus.valid) begin
            pc_step_o = DUAL_STEP;
        end else if (issue1) begin
            pc_step_o = DUAL_STEP;
        end else begin
            pc_step_o = SINGLE_STEP;
        end
    end

endmodule
