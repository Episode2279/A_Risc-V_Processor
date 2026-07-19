// Incrementally maintains one modulo-XOR fold of the speculative direction
// history.  Normal prediction therefore reads a register instead of folding
// up to 64 GHR bits on every table lookup.  Full recovery may still rebuild
// the fold from the precise GHR checkpoint because recovery is not the common
// fetch path.
module TageFoldedHistory
    import TypesPkg::*;
#(
    parameter int HISTORY_LENGTH = 4,
    parameter int FOLD_WIDTH = 8
)
(
    input  logic clk,
    input  logic rst,

    input  tage_history_t globalHistory_i,
    input  logic query0Conditional_i,
    input  logic query0Taken_i,
    output logic [FOLD_WIDTH-1:0] queryFold_o,
    output logic [FOLD_WIDTH-1:0] queryFold1_o,

    input  logic speculateValid_i,
    input  logic speculateTaken_i,
    input  logic speculateValid1_i,
    input  logic speculateTaken1_i,

    input  logic restoreValid_i,
    input  tage_history_t restoreHistory_i
);

    logic [FOLD_WIDTH-1:0] foldedHistory;
    logic [FOLD_WIDTH-1:0] speculativeFoldNext;
    logic [FOLD_WIDTH-1:0] requestBaseFold;
    tage_history_t speculativeHistoryNext;
    tage_history_t requestBaseHistory;

    function automatic logic [FOLD_WIDTH-1:0] foldHistory(
        input tage_history_t history
    );
        logic [FOLD_WIDTH-1:0] result;
        integer bitIndex;
        begin
            result = '0;
            for (bitIndex = 0; bitIndex < HISTORY_LENGTH;
                 bitIndex = bitIndex + 1)
                result[bitIndex % FOLD_WIDTH] =
                    result[bitIndex % FOLD_WIDTH] ^ history[bitIndex];
            foldHistory = result;
        end
    endfunction

    // GHR bit zero is the newest direction.  Shifting the history moves each
    // old bit to the next fold position; the bit leaving the table's history
    // window is removed at HISTORY_LENGTH modulo FOLD_WIDTH.
    function automatic logic [FOLD_WIDTH-1:0] advanceFold(
        input logic [FOLD_WIDTH-1:0] currentFold,
        input logic outgoingBit,
        input logic incomingBit
    );
        logic [FOLD_WIDTH-1:0] result;
        begin
            result = {currentFold[FOLD_WIDTH-2:0],
                      currentFold[FOLD_WIDTH-1]};
            result[0] = result[0] ^ incomingBit;
            result[HISTORY_LENGTH % FOLD_WIDTH] =
                result[HISTORY_LENGTH % FOLD_WIDTH] ^ outgoingBit;
            advanceFold = result;
        end
    endfunction

    always_comb begin
        // Apply the two accepted fetch events serially.  Updating the working
        // GHR between calls makes the second outgoing bit exact for every
        // history length and avoids a hand-written HISTORY_LENGTH-2 case.
        speculativeFoldNext = foldedHistory;
        speculativeHistoryNext = globalHistory_i;
        if (speculateValid_i) begin
            speculativeFoldNext = advanceFold(
                speculativeFoldNext,
                speculativeHistoryNext[HISTORY_LENGTH-1],
                speculateTaken_i);
            speculativeHistoryNext = {
                speculativeHistoryNext[TAGE_HISTORY_WIDTH-2:0],
                speculateTaken_i};
        end
        if (speculateValid1_i) begin
            speculativeFoldNext = advanceFold(
                speculativeFoldNext,
                speculativeHistoryNext[HISTORY_LENGTH-1],
                speculateTaken1_i);
            speculativeHistoryNext = {
                speculativeHistoryNext[TAGE_HISTORY_WIDTH-2:0],
                speculateTaken1_i};
        end

        // A synchronous table samples the next request at the same edge that
        // commits the current response's speculative history.  Feed its Hash
        // with that post-accept state (or the precise restore state on a
        // redirect), rather than the old registered fold.
        requestBaseFold = speculativeFoldNext;
        requestBaseHistory = speculativeHistoryNext;
        if (restoreValid_i) begin
            requestBaseFold = foldHistory(restoreHistory_i);
            requestBaseHistory = restoreHistory_i;
        end

        queryFold_o = requestBaseFold;
        queryFold1_o = requestBaseFold;
        // Slot 1 is useful only when Slot 0's final fetch action is not taken.
        // Pre-hashing it with an incoming zero is therefore exact; a taken
        // Slot 0 kills the Slot 1 response before it can be accepted.
        if (query0Conditional_i)
            queryFold1_o = advanceFold(
                requestBaseFold,
                requestBaseHistory[HISTORY_LENGTH-1],
                1'b0);
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst)
            foldedHistory <= '0;
        else if (restoreValid_i)
            foldedHistory <= foldHistory(restoreHistory_i);
        else
            foldedHistory <= speculativeFoldNext;
    end

endmodule
