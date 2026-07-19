`timescale 1ns/1ps

module tage_update_queue_tb;
    import TypesPkg::*;

    localparam int DEPTH = 4;
    localparam int COUNT_WIDTH = $clog2(DEPTH + 1);
    localparam int SCOREBOARD_DEPTH = 32;

    logic clk = 1'b0;
    logic rst = 1'b0;

    logic enqValid;
    logic enqReady;
    tage_update_t enqData;
    logic deqValid;
    logic deqReady;
    tage_update_t deqData;
    logic [COUNT_WIDTH-1:0] count;
    logic full;

    tage_update_t expected [SCOREBOARD_DEPTH];
    int expectedRead;
    int expectedWrite;
    int expectedCount;

    always #5 clk = ~clk;

    TageUpdateQueue #(
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .enqValid_i(enqValid),
        .enqReady_o(enqReady),
        .enqData_i(enqData),
        .deqValid_o(deqValid),
        .deqReady_i(deqReady),
        .deqData_o(deqData),
        .count_o(count),
        .full_o(full)
    );

    function automatic tage_update_t make_record(input int unsigned id);
        tage_update_t value;
        value = '0;
        value.isConditional = 1'b1;
        value.pc = instruction_addr_t'(32'h0000_1000 + (id << 2));
        value.taken = id[0];
        value.meta.history = tage_history_t'(
            64'h0123_4567_89ab_c000 + tage_history_t'(id)
        );
        value.meta.pathHistory = tage_path_history_t'(16'h5200) +
                                 tage_path_history_t'(id);
        value.meta.providerValid = id[1];
        value.meta.provider = tage_provider_t'(id % TAGE_TABLE_NUM);
        value.meta.providerPrediction = id[0];
        value.meta.alternatePrediction = id[1];
        value.meta.finalPrediction = id[0] ^ id[1];
        value.meta.providerWeak = id[2];
        return value;
    endfunction

    task automatic check_model(input string phase);
        logic expectedValid;
        logic expectedReady;
        logic expectedFull;
        logic [COUNT_WIDTH-1:0] expectedCountBits;
        begin
            expectedValid = expectedCount != 0;
            expectedReady = (expectedCount < DEPTH) ||
                            (expectedValid && deqReady);
            expectedFull = expectedCount == DEPTH;
            expectedCountBits = COUNT_WIDTH'(expectedCount);

            if (deqValid !== expectedValid)
                $fatal(1, "%s: deqValid=%0b expected=%0b",
                       phase, deqValid, expectedValid);
            if (enqReady !== expectedReady)
                $fatal(1, "%s: enqReady=%0b expected=%0b",
                       phase, enqReady, expectedReady);
            if (full !== expectedFull)
                $fatal(1, "%s: full=%0b expected=%0b",
                       phase, full, expectedFull);
            if (count !== expectedCountBits)
                $fatal(1, "%s: count=%0d expected=%0d",
                       phase, count, expectedCount);
            if (expectedValid && (deqData !== expected[expectedRead]))
                $fatal(1,
                       "%s: FIFO head mismatch pc=%08x expected=%08x",
                       phase, deqData.pc, expected[expectedRead].pc);
        end
    endtask

    task automatic apply_cycle(
        input logic enqValidValue,
        input tage_update_t enqDataValue,
        input logic deqReadyValue,
        input string phase
    );
        logic enqueueFire;
        logic dequeueFire;
        begin
            enqValid = enqValidValue;
            enqData = enqDataValue;
            deqReady = deqReadyValue;
            #1;
            check_model({phase, " before edge"});

            enqueueFire = enqValid && enqReady;
            dequeueFire = deqValid && deqReady;
            if (dequeueFire && (deqData !== expected[expectedRead]))
                $fatal(1, "%s: dequeued record out of FIFO order", phase);

            @(posedge clk);
            if (dequeueFire) begin
                expectedRead = expectedRead + 1;
                expectedCount = expectedCount - 1;
            end
            if (enqueueFire) begin
                if (expectedWrite >= SCOREBOARD_DEPTH)
                    $fatal(1, "%s: testbench scoreboard overflow", phase);
                expected[expectedWrite] = enqDataValue;
                expectedWrite = expectedWrite + 1;
                expectedCount = expectedCount + 1;
            end
            #1;
            check_model({phase, " after edge"});
        end
    endtask

    initial begin
        enqValid = 1'b0;
        enqData = '0;
        deqReady = 1'b0;
        expectedRead = 0;
        expectedWrite = 0;
        expectedCount = 0;

        // Active-low reset must expose an empty, non-full, enqueue-ready FIFO.
        repeat (2) @(posedge clk);
        #1;
        check_model("reset");
        rst = 1'b1;

        // Four consecutive enqueues fill the queue.
        apply_cycle(1'b1, make_record(1), 1'b0, "enqueue 1");
        apply_cycle(1'b1, make_record(2), 1'b0, "enqueue 2");
        apply_cycle(1'b1, make_record(3), 1'b0, "enqueue 3");
        apply_cycle(1'b1, make_record(4), 1'b0, "enqueue 4/full");

        // A full FIFO without a dequeue must lower ready and reject the input.
        apply_cycle(1'b1, make_record(99), 1'b0,
                    "full blocks enqueue");

        // When full, a simultaneous dequeue makes enqueue ready.  Count/full
        // stay asserted and record 5 occupies the slot vacated by record 1.
        apply_cycle(1'b1, make_record(5), 1'b1,
                    "full dequeue plus enqueue");

        // Move the head close to the physical end while preserving records 4/5.
        apply_cycle(1'b0, '0, 1'b1, "dequeue 2");
        apply_cycle(1'b0, '0, 1'b1, "dequeue 3");

        // These writes cross the wrapped tail.  The logical FIFO is now
        // 4, 5, 6, 7 even though it spans the end and start of the array.
        apply_cycle(1'b1, make_record(6), 1'b0, "wrapped enqueue 6");
        apply_cycle(1'b1, make_record(7), 1'b0,
                    "wrapped enqueue 7/full");

        apply_cycle(1'b0, '0, 1'b1, "wrapped dequeue 4");
        apply_cycle(1'b0, '0, 1'b1, "wrapped dequeue 5");
        apply_cycle(1'b0, '0, 1'b1, "wrapped dequeue 6");
        apply_cycle(1'b0, '0, 1'b1, "wrapped dequeue 7/empty");

        // Ready remains high and no dequeue fires while empty.
        apply_cycle(1'b0, '0, 1'b1, "empty dequeue attempt");

        // Also exercise simultaneous dequeue/enqueue away from full.
        apply_cycle(1'b1, make_record(8), 1'b0, "enqueue 8");
        apply_cycle(1'b1, make_record(9), 1'b1,
                    "non-full dequeue plus enqueue");
        apply_cycle(1'b0, '0, 1'b1, "dequeue 9/empty");

        enqValid = 1'b0;
        deqReady = 1'b0;
        #1;
        check_model("final empty");
        if ((expectedRead != expectedWrite) || (expectedCount != 0))
            $fatal(1, "scoreboard did not drain completely");

        $display("TageUpdateQueue DEPTH=4 smoke tests passed");
        $finish;
    end

endmodule
