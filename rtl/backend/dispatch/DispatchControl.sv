module DispatchControl
    import TypesPkg::*;
#(
    parameter int WIDTH = 2
)
(
    input  logic [WIDTH-1:0] laneValid_i,
    input  logic [WIDTH-1:0] laneSupported_i,
    input  logic [WIDTH-1:0] laneWritesDestination_i,
    input  logic [WIDTH-1:0] laneIsMemory_i,

    input  logic [$clog2(ROB_ENTRY_NUM+1)-1:0] robCount_i,
    input  logic [$clog2(UNIFIED_IQ_ENTRY_NUM+1)-1:0] issueCount_i,
    input  logic [$clog2(LSQ_ENTRY_NUM+1)-1:0] lsqCount_i,
    input  logic [$clog2(PHYS_REG_NUM+1)-1:0] freePhysCount_i,

    output logic [WIDTH-1:0] accept_o,
    output logic stall_o
);

    integer robFree;
    integer issueFree;
    integer lsqFree;
    integer physFree;
    integer lane;
    logic olderLaneAccepted;
    logic laneHasResources;

    always_comb begin
        robFree = ROB_ENTRY_NUM - integer'(robCount_i);
        issueFree = UNIFIED_IQ_ENTRY_NUM - integer'(issueCount_i);
        lsqFree = LSQ_ENTRY_NUM - integer'(lsqCount_i);
        physFree = integer'(freePhysCount_i);
        accept_o = '0;
        olderLaneAccepted = 1'b1;

        for (lane = 0; lane < WIDTH; lane = lane + 1) begin
            laneHasResources = (robFree > 0) && (issueFree > 0) &&
                (!laneIsMemory_i[lane] || (lsqFree > 0)) &&
                (!laneWritesDestination_i[lane] || (physFree > 0));

            if (olderLaneAccepted && laneValid_i[lane] && laneSupported_i[lane] &&
                laneHasResources) begin
                accept_o[lane] = 1'b1;
                robFree = robFree - 1;
                issueFree = issueFree - 1;
                if (laneIsMemory_i[lane]) begin
                    lsqFree = lsqFree - 1;
                end
                if (laneWritesDestination_i[lane]) physFree = physFree - 1;
            end

            // A bubble does not block the next lane, but a real instruction
            // may never be bypassed by a younger lane at dispatch.
            if (laneValid_i[lane] && !accept_o[lane]) begin
                olderLaneAccepted = 1'b0;
            end
        end

        // The fetch window may slide after accepting lane 0 alone. It only
        // freezes when its oldest valid instruction cannot dispatch.
        stall_o = laneValid_i[0] && !accept_o[0];
    end

endmodule
