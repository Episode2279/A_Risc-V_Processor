module FetchQueue
    import TypesPkg::*;
#(
    parameter int DEPTH = 8,
    parameter int PTR_W = $clog2(DEPTH)
)(
    input  logic clk,
    input  logic rst,
    input  logic flush_i,

    InstructionPacketIf.sink fetch0_i,
    InstructionPacketIf.sink fetch1_i,
    output logic fetchReady_o,

    input  logic issue0_i,
    input  logic issue1_i,
    InstructionPacketIf.source packet0_o,
    InstructionPacketIf.source packet1_o,

    output logic [$clog2(DEPTH+1)-1:0] count_o
);

    fetch_packet_t entries [DEPTH];
    logic [PTR_W-1:0] headPtr;
    logic [PTR_W-1:0] tailPtr;
    integer entryCount;
    integer incomingCount;
    integer dequeueCount;
    integer effectiveFree;
    integer seqIndex;

    function automatic logic [PTR_W-1:0] addPtr(
        input logic [PTR_W-1:0] base,
        input integer increment
    );
        integer sum;
        begin
            sum = integer'(base) + increment;
            while (sum >= DEPTH) sum = sum - DEPTH;
            addPtr = sum[PTR_W-1:0];
        end
    endfunction

    always_comb begin
        incomingCount = 0;
        if (fetch0_i.insn != '0) begin
            incomingCount = 1;
            if (fetch1_i.insn != '0)
                incomingCount = 2;
        end

        dequeueCount = integer'(issue0_i) + integer'(issue1_i);
        if (dequeueCount > entryCount)
            dequeueCount = entryCount;
        effectiveFree = DEPTH - entryCount + dequeueCount;
        fetchReady_o = effectiveFree >= incomingCount;
        count_o = entryCount[$clog2(DEPTH+1)-1:0];

        packet0_o.insn = '0;
        packet0_o.pc = RESET_VECTOR;
        packet0_o.predictedTaken = 1'b0;
        packet0_o.predictedTarget = '0;
        packet0_o.predictorIndex = '0;
        packet0_o.historySnapshot = '0;
        packet0_o.tageMeta = '0;
        packet0_o.predictedBtbHit = 1'b0;
        packet0_o.predictedRasUsed = 1'b0;
        packet1_o.insn = '0;
        packet1_o.pc = RESET_VECTOR;
        packet1_o.predictedTaken = 1'b0;
        packet1_o.predictedTarget = '0;
        packet1_o.predictorIndex = '0;
        packet1_o.historySnapshot = '0;
        packet1_o.tageMeta = '0;
        packet1_o.predictedBtbHit = 1'b0;
        packet1_o.predictedRasUsed = 1'b0;
        if (entryCount > 0) begin
            packet0_o.insn = entries[headPtr].insn;
            packet0_o.pc = entries[headPtr].pc;
            packet0_o.predictedTaken = entries[headPtr].predictedTaken;
            packet0_o.predictedTarget = entries[headPtr].predictedTarget;
            packet0_o.predictorIndex = entries[headPtr].predictorIndex;
            packet0_o.historySnapshot = entries[headPtr].historySnapshot;
            packet0_o.tageMeta = entries[headPtr].tageMeta;
            packet0_o.predictedBtbHit = entries[headPtr].predictedBtbHit;
            packet0_o.predictedRasUsed = entries[headPtr].predictedRasUsed;
        end
        if (entryCount > 1) begin
            packet1_o.insn = entries[addPtr(headPtr, 1)].insn;
            packet1_o.pc = entries[addPtr(headPtr, 1)].pc;
            packet1_o.predictedTaken = entries[addPtr(headPtr, 1)].predictedTaken;
            packet1_o.predictedTarget = entries[addPtr(headPtr, 1)].predictedTarget;
            packet1_o.predictorIndex = entries[addPtr(headPtr, 1)].predictorIndex;
            packet1_o.historySnapshot = entries[addPtr(headPtr, 1)].historySnapshot;
            packet1_o.tageMeta = entries[addPtr(headPtr, 1)].tageMeta;
            packet1_o.predictedBtbHit = entries[addPtr(headPtr, 1)].predictedBtbHit;
            packet1_o.predictedRasUsed = entries[addPtr(headPtr, 1)].predictedRasUsed;
        end
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            headPtr <= '0;
            tailPtr <= '0;
            entryCount <= 0;
            for (seqIndex = 0; seqIndex < DEPTH; seqIndex = seqIndex + 1)
                entries[seqIndex] <= '0;
        end else if (flush_i) begin
            headPtr <= '0;
            tailPtr <= '0;
            entryCount <= 0;
        end else begin
            if ((incomingCount > 0) && fetchReady_o) begin
                entries[tailPtr].insn <= fetch0_i.insn;
                entries[tailPtr].pc <= fetch0_i.pc;
                entries[tailPtr].predictedTaken <= fetch0_i.predictedTaken;
                entries[tailPtr].predictedTarget <= fetch0_i.predictedTarget;
                entries[tailPtr].predictorIndex <= fetch0_i.predictorIndex;
                entries[tailPtr].historySnapshot <= fetch0_i.historySnapshot;
                entries[tailPtr].tageMeta <= fetch0_i.tageMeta;
                entries[tailPtr].predictedBtbHit <= fetch0_i.predictedBtbHit;
                entries[tailPtr].predictedRasUsed <= fetch0_i.predictedRasUsed;
                if (incomingCount == 2) begin
                    entries[addPtr(tailPtr, 1)].insn <= fetch1_i.insn;
                    entries[addPtr(tailPtr, 1)].pc <= fetch1_i.pc;
                    entries[addPtr(tailPtr, 1)].predictedTaken <= fetch1_i.predictedTaken;
                    entries[addPtr(tailPtr, 1)].predictedTarget <= fetch1_i.predictedTarget;
                    entries[addPtr(tailPtr, 1)].predictorIndex <= fetch1_i.predictorIndex;
                    entries[addPtr(tailPtr, 1)].historySnapshot <= fetch1_i.historySnapshot;
                    entries[addPtr(tailPtr, 1)].tageMeta <= fetch1_i.tageMeta;
                    entries[addPtr(tailPtr, 1)].predictedBtbHit <= fetch1_i.predictedBtbHit;
                    entries[addPtr(tailPtr, 1)].predictedRasUsed <= fetch1_i.predictedRasUsed;
                end
            end

            headPtr <= addPtr(headPtr, dequeueCount);
            if ((incomingCount > 0) && fetchReady_o)
                tailPtr <= addPtr(tailPtr, incomingCount);
            entryCount <= entryCount - dequeueCount +
                (((incomingCount > 0) && fetchReady_o) ? incomingCount : 0);
        end
    end

    initial begin
        if ((DEPTH < 2) || ((DEPTH & (DEPTH - 1)) != 0))
            $error("FetchQueue DEPTH must be a power of two and at least two");
    end

endmodule
