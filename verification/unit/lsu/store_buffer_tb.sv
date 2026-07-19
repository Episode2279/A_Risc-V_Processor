`timescale 1ns/1ps

module store_buffer_tb;
    import TypesPkg::*;

    localparam int DEPTH = 8;
    localparam int COUNT_W = $clog2(DEPTH + 1);

    logic clk;
    logic rst;

    logic enqueueValid;
    logic enqueueReady;
    word_t enqueueAddress;
    word_t enqueueData;
    mem_access_t enqueueAccess;

    logic drainValid;
    logic drainReady;
    word_t drainAddress;
    word_t drainData;
    mem_access_t drainAccess;

    logic queryValid;
    word_t queryAddress;
    mem_access_t queryAccess;
    logic queryReady;
    logic queryConflict;
    logic queryForwardValid;
    word_t queryForwardData;

    logic empty;
    logic full;
    logic [COUNT_W-1:0] count;

    integer testIndex;

    StoreBuffer #(
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .enqueueValid_i(enqueueValid),
        .enqueueReady_o(enqueueReady),
        .enqueueAddress_i(enqueueAddress),
        .enqueueData_i(enqueueData),
        .enqueueAccess_i(enqueueAccess),
        .drainValid_o(drainValid),
        .drainReady_i(drainReady),
        .drainAddress_o(drainAddress),
        .drainData_o(drainData),
        .drainAccess_o(drainAccess),
        .queryValid_i(queryValid),
        .queryAddress_i(queryAddress),
        .queryAccess_i(queryAccess),
        .queryReady_o(queryReady),
        .queryConflict_o(queryConflict),
        .queryForwardValid_o(queryForwardValid),
        .queryForwardData_o(queryForwardData),
        .empty_o(empty),
        .full_o(full),
        .count_o(count)
    );

    always #5 clk = ~clk;

    task automatic resetDut;
        begin
            @(negedge clk);
            rst = 1'b0;
            enqueueValid = 1'b0;
            drainReady = 1'b0;
            queryValid = 1'b0;
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst = 1'b1;
            #1;
            if (!empty || full || (count != COUNT_W'(0)))
                $fatal(1, "StoreBuffer reset state is incorrect");
        end
    endtask

    task automatic pushStore(
        input word_t address,
        input word_t data,
        input mem_access_t accessMode
    );
        begin
            @(negedge clk);
            enqueueAddress = address;
            enqueueData = data;
            enqueueAccess = accessMode;
            enqueueValid = 1'b1;
            #1;
            if (!enqueueReady)
                $fatal(1, "Unexpected enqueue backpressure at address %08x",
                       address);
            @(posedge clk);
            #1;
            @(negedge clk);
            enqueueValid = 1'b0;
        end
    endtask

    task automatic popStore(
        input word_t expectedAddress,
        input word_t expectedData,
        input mem_access_t expectedAccess
    );
        begin
            @(negedge clk);
            #1;
            if (!drainValid)
                $fatal(1, "Expected a Store to drain");
            if ((drainAddress !== expectedAddress) ||
                (drainData !== expectedData) ||
                (drainAccess !== expectedAccess)) begin
                $fatal(1,
                    "Drain mismatch got addr=%08x data=%08x access=%0d, expected addr=%08x data=%08x access=%0d",
                    drainAddress, drainData, drainAccess,
                    expectedAddress, expectedData, expectedAccess);
            end
            drainReady = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            drainReady = 1'b0;
        end
    endtask

    task automatic expectQuery(
        input word_t address,
        input mem_access_t accessMode,
        input logic expectedReady,
        input logic expectedConflict,
        input logic expectedForwardValid,
        input word_t expectedForwardData
    );
        begin
            @(negedge clk);
            queryAddress = address;
            queryAccess = accessMode;
            queryValid = 1'b1;
            #1;
            if (queryReady !== expectedReady)
                $fatal(1, "Query ready mismatch for %08x: got %0b expected %0b",
                       address, queryReady, expectedReady);
            if (queryConflict !== expectedConflict)
                $fatal(1, "Query conflict mismatch for %08x", address);
            if (queryForwardValid !== expectedForwardValid)
                $fatal(1, "Query forwarding-valid mismatch for %08x", address);
            if (expectedForwardValid &&
                (queryForwardData !== expectedForwardData)) begin
                $fatal(1,
                    "Forward data mismatch for %08x: got %08x expected %08x",
                    address, queryForwardData, expectedForwardData);
            end
            queryValid = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b0;
        enqueueValid = 1'b0;
        enqueueAddress = '0;
        enqueueData = '0;
        enqueueAccess = MEM_WORD;
        drainReady = 1'b0;
        queryValid = 1'b0;
        queryAddress = '0;
        queryAccess = MEM_WORD;

        // FIFO capacity, ordering, pointer wrap, and full pop+push behavior.
        resetDut();
        for (testIndex = 0; testIndex < DEPTH; testIndex = testIndex + 1)
            pushStore(32'h0000_0100 + testIndex * 4,
                      32'hA000_0000 + testIndex, MEM_WORD);
        #1;
        if (!full || empty || (count != COUNT_W'(DEPTH)) || enqueueReady)
            $fatal(1, "StoreBuffer did not report the full state");

        // Replacing the oldest entry in a full FIFO must not change count.
        @(negedge clk);
        enqueueAddress = 32'h0000_0200;
        enqueueData = 32'hDEAD_BEEF;
        enqueueAccess = MEM_WORD;
        enqueueValid = 1'b1;
        drainReady = 1'b1;
        #1;
        if (!drainValid || !enqueueReady ||
            (drainAddress !== 32'h0000_0100))
            $fatal(1, "Full simultaneous pop/push handshake failed");
        @(posedge clk);
        #1;
        if (!full || (count != COUNT_W'(DEPTH)))
            $fatal(1, "Full simultaneous pop/push changed FIFO occupancy");
        @(negedge clk);
        enqueueValid = 1'b0;
        drainReady = 1'b0;

        for (testIndex = 1; testIndex < DEPTH; testIndex = testIndex + 1)
            popStore(32'h0000_0100 + testIndex * 4,
                     32'hA000_0000 + testIndex, MEM_WORD);
        popStore(32'h0000_0200, 32'hDEAD_BEEF, MEM_WORD);
        #1;
        if (!empty || full || drainValid || (count != COUNT_W'(0)))
            $fatal(1, "FIFO did not become empty after ordered drain");

        // A younger partial Store overrides only its own byte; older bytes are
        // still collected to produce a complete forwarded word.
        resetDut();
        pushStore(32'h0000_0100, 32'h1122_3344, MEM_WORD);
        pushStore(32'h0000_0101, 32'h0000_00AA, MEM_BYTE);
        pushStore(32'h0000_0102, 32'h0000_BEEF, MEM_HALF);
        expectQuery(32'h0000_0100, MEM_WORD,
                    1'b1, 1'b1, 1'b1, 32'hBEEF_AA44);
        expectQuery(32'h0000_0101, MEM_BYTE,
                    1'b1, 1'b1, 1'b1, 32'hFFFF_FFAA);
        expectQuery(32'h0000_0101, MEM_BYTE_U,
                    1'b1, 1'b1, 1'b1, 32'h0000_00AA);
        expectQuery(32'h0000_0102, MEM_HALF,
                    1'b1, 1'b1, 1'b1, 32'hFFFF_BEEF);
        expectQuery(32'h0000_0102, MEM_HALF_U,
                    1'b1, 1'b1, 1'b1, 32'h0000_BEEF);

        // Multiple independent byte Stores may jointly cover a wider Load.
        resetDut();
        pushStore(32'h0000_0300, 32'h0000_0011, MEM_BYTE);
        pushStore(32'h0000_0301, 32'h0000_0022, MEM_BYTE);
        pushStore(32'h0000_0302, 32'h0000_0033, MEM_BYTE);
        pushStore(32'h0000_0303, 32'h0000_0044, MEM_BYTE);
        expectQuery(32'h0000_0300, MEM_WORD,
                    1'b1, 1'b1, 1'b1, 32'h4433_2211);

        // A partially covered Load must wait; a disjoint address may proceed.
        resetDut();
        pushStore(32'h0000_0401, 32'h0000_00AA, MEM_BYTE);
        expectQuery(32'h0000_0400, MEM_WORD,
                    1'b0, 1'b1, 1'b0, '0);
        expectQuery(32'h0000_0401, MEM_BYTE_U,
                    1'b1, 1'b1, 1'b1, 32'h0000_00AA);
        expectQuery(32'h0000_0404, MEM_WORD,
                    1'b1, 1'b0, 1'b0, '0);

        $display("store_buffer_tb PASS");
        $finish;
    end

endmodule
