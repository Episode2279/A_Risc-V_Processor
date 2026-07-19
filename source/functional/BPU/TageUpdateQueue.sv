// Small in-order FIFO between branch retirement and TAGE table writes.  It is
// intentionally not flushed on a redirect: every enqueued record has already
// retired and must still train the predictor.
module TageUpdateQueue
    import TypesPkg::*;
#(
    parameter int DEPTH = 4,
    parameter int PTR_WIDTH = $clog2(DEPTH),
    parameter int COUNT_WIDTH = $clog2(DEPTH + 1)
)
(
    input  logic clk,
    input  logic rst,

    input  logic enqValid_i,
    output logic enqReady_o,
    input  tage_update_t enqData_i,

    output logic deqValid_o,
    input  logic deqReady_i,
    output tage_update_t deqData_o,

    output logic [COUNT_WIDTH-1:0] count_o,
    output logic full_o
);

    tage_update_t entries [DEPTH];
    logic [PTR_WIDTH-1:0] head;
    logic [PTR_WIDTH-1:0] tail;
    logic [COUNT_WIDTH-1:0] count;
    logic enqueue;
    logic dequeue;
    localparam logic [PTR_WIDTH-1:0] LAST_PTR = PTR_WIDTH'(DEPTH - 1);
    localparam logic [COUNT_WIDTH-1:0] DEPTH_COUNT = COUNT_WIDTH'(DEPTH);

    assign deqValid_o = count != '0;
    assign deqData_o = entries[head];
    assign dequeue = deqValid_o && deqReady_i;
    // A simultaneous dequeue frees the head slot for an enqueue even when the
    // queue begins the cycle full.
    assign enqReady_o = (count < DEPTH_COUNT) || dequeue;
    assign enqueue = enqValid_i && enqReady_o;
    assign count_o = count;
    assign full_o = count == DEPTH_COUNT;

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            head <= '0;
            tail <= '0;
            count <= '0;
        end else begin
            if (enqueue) begin
                entries[tail] <= enqData_i;
                if (tail == LAST_PTR)
                    tail <= '0;
                else
                    tail <= tail + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
            end

            if (dequeue) begin
                if (head == LAST_PTR)
                    head <= '0;
                else
                    head <= head + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
            end

            case ({enqueue, dequeue})
                2'b10: count <= count + {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
                2'b01: count <= count - {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
                default: count <= count;
            endcase
        end
    end

endmodule
