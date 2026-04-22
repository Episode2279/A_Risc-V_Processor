`timescale 1ns / 1ps

module topCPU_tb;
    import TypesPkg::*;

    localparam time CLK_PERIOD = 10ns;
    localparam int  MAX_CYCLES = 40;

    logic              clk;
    logic              rst;
    word_t             fromHost;
    word_t             toHost;
    logic              uartValid;
    logic [7:0]        uartData;
    instruction_t      check;
    instruction_addr_t checkPC;
    word_t             checkData;

    int cycle_count;

    topCPU dut (
        .clk(clk),
        .rst(rst),
        .fromHost_i(fromHost),
        .toHost_o(toHost),
        .uartValid_o(uartValid),
        .uartData_o(uartData),
        .check(check),
        .checkPC(checkPC),
        .checkData(checkData)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    task automatic readmemh_if_exists(
        input string candidate_path,
        input string label
    );
        int fd;
        begin
            fd = $fopen(candidate_path, "r");
            if (fd != 0) begin
                $fclose(fd);
                if (label == "instruction") begin
                    $readmemh(candidate_path, dut.ifStage.insnMem.mem);
                end else begin
                    $readmemh(candidate_path, dut.memStage.dataMem.mem);
                end
                $display("[%0t] Loaded %s memory from %s", $time, label, candidate_path);
            end
        end
    endtask

    task automatic reload_memories;
        begin
            readmemh_if_exists("source/utils/insn.mem", "instruction");
            readmemh_if_exists("../source/utils/insn.mem", "instruction");
            readmemh_if_exists("../../source/utils/insn.mem", "instruction");

            readmemh_if_exists("source/utils/data.mem", "data");
            readmemh_if_exists("../source/utils/data.mem", "data");
            readmemh_if_exists("../../source/utils/data.mem", "data");
        end
    endtask

    initial begin
        rst = 1'b0;
        fromHost = '0;
        cycle_count = 0;

        reload_memories();

        repeat (2) @(posedge clk);
        rst = 1'b1;

        $display(" time | cycle |   pc   | instruction | checkData");
        $display("------+-------+--------+-------------+----------");

        while ((cycle_count < MAX_CYCLES) && (toHost === '0)) begin
            @(posedge clk);
            cycle_count++;
            #1ns;
            $display("%5t | %5d | 0x%08h | 0x%08h  | 0x%08h",
                     $time, cycle_count, checkPC, check, checkData);

            if (uartValid && (uartData != 8'h0d)) begin
                $write("%c", uartData);
            end
        end

        $display("");
        $display("Final state after %0d cycles:", cycle_count);
        $display("  PC           = 0x%08h", checkPC);
        $display("  Instruction  = 0x%08h", check);
        $display("  Writeback    = 0x%08h", checkData);
        $display("  toHost       = 0x%08h", toHost);
        $display("  dataMem[0]   = 0x%08h", dut.memStage.dataMem.mem[0]);
        $display("  dataMem[1]   = 0x%08h", dut.memStage.dataMem.mem[1]);

        $finish;
    end

endmodule
