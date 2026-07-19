module PhysicalFreeList
    import TypesPkg::*;
#(
    parameter int ARCH_REGS = REG_NUM,
    parameter int PHYS_REGS = PHYS_REG_NUM,
    parameter int ALLOC_WIDTH = 2,
    parameter int FREE_WIDTH = 2
)
(
    input  logic clk,
    input  logic rst,
    input  logic restore_i,
    input  logic [PHYS_REGS-1:0] restoreFreeMask_i,
    input  logic [ALLOC_WIDTH-1:0] checkpointValid_i,
    input  rob_tag_t checkpointTag_i [ALLOC_WIDTH],
    input  logic recoverValid_i,
    input  rob_tag_t recoverTag_i,

    input  logic [ALLOC_WIDTH-1:0] allocRequest_i,
    output logic [ALLOC_WIDTH-1:0] allocReady_o,
    output phys_reg_addr_t allocPhys_o [ALLOC_WIDTH],

    input  logic [FREE_WIDTH-1:0] freeValid_i,
    input  phys_reg_addr_t freePhys_i [FREE_WIDTH],
    output logic [$clog2(PHYS_REGS+1)-1:0] freeCount_o
);

    logic [PHYS_REGS-1:0] freeMask;
    logic [PHYS_REGS-1:0] availableMask;
    logic [PHYS_REGS-1:0] checkpointFreeMask [ROB_ENTRY_NUM];
    integer combLane;
    integer combPhysIndex;
    integer seqLane;
    integer seqPhysIndex;
    integer freeCount;
    logic found;

    always_comb begin
        availableMask = freeMask;
        for (combLane = 0; combLane < ALLOC_WIDTH; combLane = combLane + 1) begin
            allocReady_o[combLane] = 1'b0;
            allocPhys_o[combLane] = '0;
            found = 1'b0;
            // Any physical register not present in the current committed or
            // speculative mappings is reusable. Registers p1..p31 therefore
            // become allocatable after their initial architectural mappings
            // are replaced and retired.
            for (combPhysIndex = 1; combPhysIndex < PHYS_REGS; combPhysIndex = combPhysIndex + 1) begin
                if (!found && availableMask[combPhysIndex]) begin
                    allocReady_o[combLane] = 1'b1;
                    allocPhys_o[combLane] = phys_reg_addr_t'(combPhysIndex);
                    found = 1'b1;
                end
            end
            if (allocRequest_i[combLane] && allocReady_o[combLane]) begin
                availableMask[allocPhys_o[combLane]] = 1'b0;
            end
        end

        freeCount = 0;
        for (combPhysIndex = 0; combPhysIndex < PHYS_REGS; combPhysIndex = combPhysIndex + 1) begin
            if (freeMask[combPhysIndex]) freeCount = freeCount + 1;
        end
        freeCount_o = freeCount[$clog2(PHYS_REGS+1)-1:0];
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            for (seqPhysIndex = 0; seqPhysIndex < PHYS_REGS; seqPhysIndex = seqPhysIndex + 1) begin
                freeMask[seqPhysIndex] <= (seqPhysIndex >= ARCH_REGS);
            end
            for (seqLane = 0; seqLane < ROB_ENTRY_NUM; seqLane = seqLane + 1)
                checkpointFreeMask[seqLane] <=
                    {{(PHYS_REGS-ARCH_REGS){1'b1}}, {ARCH_REGS{1'b0}}};
        end else if (restore_i) begin
            freeMask <= restoreFreeMask_i;
            freeMask[0] <= 1'b0;
        end else if (recoverValid_i) begin
            freeMask <= checkpointFreeMask[recoverTag_i];
            for (seqLane = 0; seqLane < FREE_WIDTH; seqLane = seqLane + 1) begin
                if (freeValid_i[seqLane] && (freePhys_i[seqLane] != '0))
                    freeMask[freePhys_i[seqLane]] <= 1'b1;
            end
            freeMask[0] <= 1'b0;
        end else begin
            for (seqLane = 0; seqLane < FREE_WIDTH; seqLane = seqLane + 1) begin
                if (freeValid_i[seqLane] && (freePhys_i[seqLane] != '0)) begin
                    freeMask[freePhys_i[seqLane]] <= 1'b1;
                end
            end
            for (seqLane = 0; seqLane < ALLOC_WIDTH; seqLane = seqLane + 1) begin
                if (allocRequest_i[seqLane] && allocReady_o[seqLane]) begin
                    freeMask[allocPhys_o[seqLane]] <= 1'b0;
                end
            end
            freeMask[0] <= 1'b0;
        end

        if (rst) begin
            for (seqLane = 0; seqLane < ROB_ENTRY_NUM; seqLane = seqLane + 1) begin
                for (seqPhysIndex = 0; seqPhysIndex < FREE_WIDTH;
                     seqPhysIndex = seqPhysIndex + 1) begin
                    if (freeValid_i[seqPhysIndex] &&
                        (freePhys_i[seqPhysIndex] != '0)) begin
                        checkpointFreeMask[seqLane][freePhys_i[seqPhysIndex]] <= 1'b1;
                    end
                end
            end
            for (seqLane = 0; seqLane < ALLOC_WIDTH; seqLane = seqLane + 1) begin
                if (checkpointValid_i[seqLane]) begin
                    checkpointFreeMask[checkpointTag_i[seqLane]] <= freeMask;
                    for (seqPhysIndex = 0; seqPhysIndex <= seqLane;
                         seqPhysIndex = seqPhysIndex + 1) begin
                        if (allocRequest_i[seqPhysIndex] && allocReady_o[seqPhysIndex])
                            checkpointFreeMask[checkpointTag_i[seqLane]]
                                              [allocPhys_o[seqPhysIndex]] <= 1'b0;
                    end
                    for (seqPhysIndex = 0; seqPhysIndex < FREE_WIDTH;
                         seqPhysIndex = seqPhysIndex + 1) begin
                        if (freeValid_i[seqPhysIndex] &&
                            (freePhys_i[seqPhysIndex] != '0)) begin
                            checkpointFreeMask[checkpointTag_i[seqLane]]
                                              [freePhys_i[seqPhysIndex]] <= 1'b1;
                        end
                    end
                end
            end
        end
    end

endmodule
