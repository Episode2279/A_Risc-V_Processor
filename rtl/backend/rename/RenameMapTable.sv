module RenameMapTable
    import TypesPkg::*;
#(
    parameter int ARCH_REGS = REG_NUM,
    parameter int PHYS_REGS = PHYS_REG_NUM,
    parameter int RENAME_WIDTH = 2,
    parameter int COMMIT_WIDTH = 2
)
(
    input  logic clk,
    input  logic rst,
    input  logic restoreCommitted_i,
    input  logic [RENAME_WIDTH-1:0] checkpointValid_i,
    input  rob_tag_t checkpointTag_i [RENAME_WIDTH],
    input  logic recoverValid_i,
    input  rob_tag_t recoverTag_i,

    input  reg_addr_t sourceA_i [RENAME_WIDTH],
    input  reg_addr_t sourceB_i [RENAME_WIDTH],
    output phys_reg_addr_t sourceAPhys_o [RENAME_WIDTH],
    output phys_reg_addr_t sourceBPhys_o [RENAME_WIDTH],

    input  logic [RENAME_WIDTH-1:0] renameValid_i,
    input  reg_addr_t renameArchRd_i [RENAME_WIDTH],
    input  phys_reg_addr_t renameNewPhys_i [RENAME_WIDTH],
    output phys_reg_addr_t renameOldPhys_o [RENAME_WIDTH],

    input  logic [COMMIT_WIDTH-1:0] commitValid_i,
    input  reg_addr_t commitArchRd_i [COMMIT_WIDTH],
    input  phys_reg_addr_t commitNewPhys_i [COMMIT_WIDTH],
    output logic [PHYS_REGS-1:0] committedFreeMask_o
);

    phys_reg_addr_t speculativeMap [ARCH_REGS];
    phys_reg_addr_t committedMap [ARCH_REGS];
    phys_reg_addr_t checkpointMap [ROB_ENTRY_NUM][ARCH_REGS];

    integer combLane;
    integer combOlderLane;
    integer seqLane;
    integer seqArchIndex;
    integer checkpointOlderLane;
    integer maskArchIndex;

    always_comb begin
        committedFreeMask_o = '1;
        for (maskArchIndex = 0; maskArchIndex < ARCH_REGS; maskArchIndex = maskArchIndex + 1) begin
            committedFreeMask_o[committedMap[maskArchIndex]] = 1'b0;
        end
        committedFreeMask_o[0] = 1'b0;
    end

    always_comb begin
        for (combLane = 0; combLane < RENAME_WIDTH; combLane = combLane + 1) begin
            sourceAPhys_o[combLane] = speculativeMap[sourceA_i[combLane]];
            sourceBPhys_o[combLane] = speculativeMap[sourceB_i[combLane]];
            renameOldPhys_o[combLane] = speculativeMap[renameArchRd_i[combLane]];

            // Within one rename group, a younger lane observes all mappings
            // produced by older lanes in that same cycle.
            for (combOlderLane = 0; combOlderLane < RENAME_WIDTH; combOlderLane = combOlderLane + 1) begin
                if ((combOlderLane < combLane) && renameValid_i[combOlderLane] &&
                    (renameArchRd_i[combOlderLane] != '0)) begin
                    if (sourceA_i[combLane] == renameArchRd_i[combOlderLane]) begin
                        sourceAPhys_o[combLane] = renameNewPhys_i[combOlderLane];
                    end
                    if (sourceB_i[combLane] == renameArchRd_i[combOlderLane]) begin
                        sourceBPhys_o[combLane] = renameNewPhys_i[combOlderLane];
                    end
                    if (renameArchRd_i[combLane] == renameArchRd_i[combOlderLane]) begin
                        renameOldPhys_o[combLane] = renameNewPhys_i[combOlderLane];
                    end
                end
            end

            if (sourceA_i[combLane] == '0) sourceAPhys_o[combLane] = '0;
            if (sourceB_i[combLane] == '0) sourceBPhys_o[combLane] = '0;
            if (renameArchRd_i[combLane] == '0) renameOldPhys_o[combLane] = '0;
        end
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            for (seqArchIndex = 0; seqArchIndex < ARCH_REGS; seqArchIndex = seqArchIndex + 1) begin
                speculativeMap[seqArchIndex] <= phys_reg_addr_t'(seqArchIndex);
                committedMap[seqArchIndex] <= phys_reg_addr_t'(seqArchIndex);
                for (seqLane = 0; seqLane < ROB_ENTRY_NUM; seqLane = seqLane + 1)
                    checkpointMap[seqLane][seqArchIndex] <=
                        phys_reg_addr_t'(seqArchIndex);
            end
        end else begin
            for (seqLane = 0; seqLane < COMMIT_WIDTH; seqLane = seqLane + 1) begin
                if (commitValid_i[seqLane] && (commitArchRd_i[seqLane] != '0)) begin
                    committedMap[commitArchRd_i[seqLane]] <= commitNewPhys_i[seqLane];
                end
            end

            if (restoreCommitted_i) begin
                for (seqArchIndex = 0; seqArchIndex < ARCH_REGS; seqArchIndex = seqArchIndex + 1) begin
                    speculativeMap[seqArchIndex] <= committedMap[seqArchIndex];
                end
            end else if (recoverValid_i) begin
                for (seqArchIndex = 0; seqArchIndex < ARCH_REGS;
                     seqArchIndex = seqArchIndex + 1) begin
                    speculativeMap[seqArchIndex] <=
                        checkpointMap[recoverTag_i][seqArchIndex];
                end
            end else begin
                for (seqLane = 0; seqLane < RENAME_WIDTH; seqLane = seqLane + 1) begin
                    if (renameValid_i[seqLane] && (renameArchRd_i[seqLane] != '0)) begin
                        speculativeMap[renameArchRd_i[seqLane]] <= renameNewPhys_i[seqLane];
                    end
                end
            end

            for (seqLane = 0; seqLane < RENAME_WIDTH; seqLane = seqLane + 1) begin
                if (checkpointValid_i[seqLane]) begin
                    for (seqArchIndex = 0; seqArchIndex < ARCH_REGS;
                         seqArchIndex = seqArchIndex + 1) begin
                        checkpointMap[checkpointTag_i[seqLane]][seqArchIndex] <=
                            speculativeMap[seqArchIndex];
                    end
                    // Recovery keeps the branch itself, including a JAL/JALR
                    // link-register rename and any older lane in its group.
                    for (checkpointOlderLane = 0; checkpointOlderLane <= seqLane;
                         checkpointOlderLane = checkpointOlderLane + 1) begin
                        if (renameValid_i[checkpointOlderLane] &&
                            (renameArchRd_i[checkpointOlderLane] != '0))
                            checkpointMap[checkpointTag_i[seqLane]]
                                         [renameArchRd_i[checkpointOlderLane]] <=
                                renameNewPhys_i[checkpointOlderLane];
                    end
                end
            end
        end
    end

endmodule
