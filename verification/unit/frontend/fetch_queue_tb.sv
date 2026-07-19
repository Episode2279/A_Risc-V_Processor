`timescale 1ns/1ps

module fetch_queue_tb;
    import TypesPkg::*;

    logic clk = 1'b0;
    logic rst = 1'b0;
    logic flush;
    logic ready;
    logic issue0;
    logic issue1;
    logic [$clog2(8+1)-1:0] count;
    InstructionPacketIf fetch0();
    InstructionPacketIf fetch1();
    InstructionPacketIf packet0();
    InstructionPacketIf packet1();

    always #5 clk = ~clk;

    FetchQueue #(.DEPTH(8)) dut (
        .clk(clk), .rst(rst), .flush_i(flush),
        .fetch0_i(fetch0), .fetch1_i(fetch1), .fetchReady_o(ready),
        .issue0_i(issue0), .issue1_i(issue1),
        .packet0_o(packet0), .packet1_o(packet1), .count_o(count)
    );

    task automatic clear_fetch;
        begin
            fetch0.insn = '0;
            fetch0.pc = '0;
            fetch0.predictedTaken = 1'b0;
            fetch0.predictedTarget = '0;
            fetch0.predictorIndex = '0;
            fetch0.historySnapshot = '0;
            fetch0.tageMeta = '0;
            fetch0.predictedBtbHit = 1'b0;
            fetch0.predictedRasUsed = 1'b0;
            fetch1.insn = '0;
            fetch1.pc = '0;
            fetch1.predictedTaken = 1'b0;
            fetch1.predictedTarget = '0;
            fetch1.predictorIndex = '0;
            fetch1.historySnapshot = '0;
            fetch1.tageMeta = '0;
            fetch1.predictedBtbHit = 1'b0;
            fetch1.predictedRasUsed = 1'b0;
        end
    endtask

    task automatic set_pair(input word_t pc, input instruction_t a,
                            input instruction_t b);
        begin
            clear_fetch();
            fetch0.pc = pc;
            fetch0.insn = a;
            fetch1.pc = pc + 4;
            fetch1.insn = b;
        end
    endtask

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        flush = 1'b0;
        issue0 = 1'b0;
        issue1 = 1'b0;
        clear_fetch();
        tick();
        rst = 1'b1;

        set_pair(32'h100, 32'h0000_0013, 32'h0010_0093);
        #1;
        if (!ready) $fatal(1, "empty fetch queue was not ready");
        tick();
        clear_fetch();
        if (count != 2 || packet0.pc != 32'h100 || packet1.pc != 32'h104)
            $fatal(1, "dual enqueue failed: count=%0d pc=%h/%h",
                   count, packet0.pc, packet1.pc);

        // Consume one while accepting another pair. The younger resident
        // instruction must remain ahead of both newly fetched instructions.
        issue0 = 1'b1;
        set_pair(32'h108, 32'h0020_0113, 32'h0030_0193);
        tick();
        issue0 = 1'b0;
        clear_fetch();
        if (count != 3 || packet0.pc != 32'h104 || packet1.pc != 32'h108)
            $fatal(1, "simultaneous dequeue/enqueue ordering failed");

        issue0 = 1'b1;
        issue1 = 1'b1;
        tick();
        issue0 = 1'b0;
        issue1 = 1'b0;
        if (count != 1 || packet0.pc != 32'h10c)
            $fatal(1, "dual dequeue failed");

        flush = 1'b1;
        tick();
        flush = 1'b0;
        if (count != 0 || packet0.insn != '0 || packet1.insn != '0)
            $fatal(1, "fetch queue flush failed");

        $display("fetch_queue_tb PASS");
        $finish;
    end
endmodule
