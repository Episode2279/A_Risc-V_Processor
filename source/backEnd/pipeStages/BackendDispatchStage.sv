module BackendDispatchStage
    import TypesPkg::*;
(
    input logic [1:0] laneValid_i,
    input logic [1:0] laneSupported_i,
    input logic [1:0] laneWritesDestination_i,
    input logic [1:0] laneIsMemory_i,
    input logic [$clog2(ROB_ENTRY_NUM+1)-1:0] robCount_i,
    input logic [$clog2(ISSUE_QUEUE_ENTRY_NUM+LSQ_ENTRY_NUM+1)-1:0] issueCount_i,
    input logic [$clog2(LSQ_ENTRY_NUM+1)-1:0] lsqCount_i,
    input logic [$clog2(PHYS_REG_NUM+1)-1:0] freePhysCount_i,
    output logic [1:0] accept_o,
    output logic stall_o
);
    DispatchControl dispatchControl (
        .laneValid_i(laneValid_i),
        .laneSupported_i(laneSupported_i),
        .laneWritesDestination_i(laneWritesDestination_i),
        .laneIsMemory_i(laneIsMemory_i),
        .robCount_i(robCount_i),
        .issueCount_i(issueCount_i),
        .lsqCount_i(lsqCount_i),
        .freePhysCount_i(freePhysCount_i),
        .accept_o(accept_o),
        .stall_o(stall_o)
    );
endmodule
