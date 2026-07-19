module BackendIssueStage
    import TypesPkg::*;
#(
    parameter int DEPTH = ISSUE_QUEUE_ENTRY_NUM + LSQ_ENTRY_NUM
)(
    input logic clk,
    input logic rst,
    input logic flush_i,
    input logic recoverValid_i,
    input rob_tag_t recoverTag_i,
    input logic [ROB_ENTRY_NUM-1:0] recoverYoungerMask_i,
    input renamed_uop_t dispatchUop_i [2],
    output logic [1:0] dispatchReady_o,
    input logic [1:0] wakeupValid_i,
    input phys_reg_addr_t wakeupPhys_i [2],
    output logic [1:0] issueValid_o,
    output renamed_uop_t issueUop_o [2],
    input logic [1:0] issueReady_i,
    output logic fallbackValid_o,
    output renamed_uop_t fallbackUop_o,
    input logic fallbackReady_i,
    output logic empty_o,
    output logic full_o,
    output logic [$clog2(DEPTH+1)-1:0] count_o
);
    IssueQueue #(.DEPTH(DEPTH)) unifiedIssueQueue (
        .clk(clk), .rst(rst), .flush_i(flush_i),
        .recoverValid_i(recoverValid_i), .recoverTag_i(recoverTag_i),
        .recoverYoungerMask_i(recoverYoungerMask_i),
        .dispatchUop_i(dispatchUop_i), .dispatchReady_o(dispatchReady_o),
        .wakeupValid_i(wakeupValid_i), .wakeupPhys_i(wakeupPhys_i),
        .issueValid_o(issueValid_o), .issueUop_o(issueUop_o),
        .issueReady_i(issueReady_i),
        .fallbackValid_o(fallbackValid_o), .fallbackUop_o(fallbackUop_o),
        .fallbackReady_i(fallbackReady_i),
        .empty_o(empty_o), .full_o(full_o),
        .count_o(count_o)
    );
endmodule
