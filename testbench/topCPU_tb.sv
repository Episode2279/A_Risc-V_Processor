`timescale 1ns / 1ps

module topCPU_tb #(
    // Hard simulation cap. Normal tests should finish by writing tohost before
    // this limit; reaching the cap is reported as TIMEOUT.
    parameter int MAX_CYCLES = 10_000_000
);
    import TypesPkg::*;

    // File names are kept under source/ so Vivado and Verilator flows generate
    // artifacts in the same place used by the Konata converter script.
    localparam time CLK_PERIOD = 10ns;
    localparam string DEBUG_FILE_NAME = "topCPU_tb_debug.txt";
    localparam string DUMP_FILE_NAME  = "topCPU_tb_output.txt";
    localparam string SOURCE_DEBUG_FILE_ABS =
        "C:/Users/22793/Desktop/programming/cpubase/A_Risc-V_Processor/source/topCPU_tb_debug.txt";
    localparam string SOURCE_DUMP_FILE_ABS =
        "C:/Users/22793/Desktop/programming/cpubase/A_Risc-V_Processor/source/topCPU_tb_output.txt";
    localparam string INSN_MEM_FILE_ABS =
        "C:/Users/22793/Desktop/programming/cpubase/A_Risc-V_Processor/source/utils/insn.mem";
    localparam string DATA_MEM_FILE_ABS =
        "C:/Users/22793/Desktop/programming/cpubase/A_Risc-V_Processor/source/utils/data.mem";
    localparam word_t TOHOST_PASS_VALUE = word_t'(32'd1);

    // DUT IO signals.
    logic              clk;
    logic              rst;
    word_t             fromHost;
    word_t             toHost;
    logic              uartValid;
    logic [7:0]        uartData;
    instruction_t      check;
    instruction_addr_t checkPC;
    word_t             checkData;

    // Testbench bookkeeping for logs, memory-image discovery, and timeout state.
    int cycle_count;
    int log_fd;
    int dump_fd;
    string log_path;
    string dump_path;
    bit insn_mem_loaded;
    bit data_mem_loaded;
    bit timed_out;

    // Device under test. Verilator-only debug ports are intentionally left
    // unconnected here because this SV testbench reads hierarchy directly.
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
`ifdef VERILATOR
        ,
        .dbg_wrEnable(),
        .dbg_stall(),
        .dbg_flush(),
        .dbg_jumpEnable(),
        .dbg_if_valid(),
        .dbg_if_pc(),
        .dbg_if_insn(),
        .dbg_id_valid(),
        .dbg_id_pc(),
        .dbg_id_insn(),
        .dbg_id_rd(),
        .dbg_id_regWrite(),
        .dbg_id_memWrite(),
        .dbg_id_branchCtr(),
        .dbg_id_aluCtr(),
        .dbg_id_memCtr(),
        .dbg_id_regA(),
        .dbg_id_regB(),
        .dbg_id_imm(),
        .dbg_ex_pc(),
        .dbg_ex_rd(),
        .dbg_ex_regWrite(),
        .dbg_ex_memWrite(),
        .dbg_ex_memCtr(),
        .dbg_ex_aluOut(),
        .dbg_ex_dataA(),
        .dbg_ex_dataB(),
        .dbg_ex_imm(),
        .dbg_mem_pc(),
        .dbg_mem_rd(),
        .dbg_mem_regWrite(),
        .dbg_mem_memWrite(),
        .dbg_mem_memCtr(),
        .dbg_mem_aluOut(),
        .dbg_mem_dataB(),
        .dbg_mem_rdData(),
        .dbg_mem_toHostHit(),
        .dbg_mem_uartHit(),
        .dbg_mem_fromHostHit(),
        .dbg_wb_pc(),
        .dbg_wb_rd(),
        .dbg_wb_regWrite(),
        .dbg_wb_wbSelect(),
        .dbg_wb_aluSrc(),
        .dbg_wb_rdData(),
        .dbg_wb_dataWb()
`endif
    );

    initial begin
        // Free-running 100 MHz simulation clock.
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    function automatic bit insn_known(input instruction_t insn);
        begin
            // Reduction XOR returns X when any bit is X, making this a compact
            // four-state validity check for dump/visualization purposes.
            insn_known = (^insn !== 1'bx);
        end
    endfunction

    function automatic bit word_known(input word_t value);
        begin
            // Avoid treating uninitialized tohost/check data as a real result.
            word_known = (^value !== 1'bx);
        end
    endfunction

    // Open a candidate memory-image path and load it into the DUT hierarchy if
    // it exists. This makes the same testbench work from Vivado project dirs,
    // command-line simulation dirs, and this repository root.
    task automatic readmemh_if_exists(
        input string candidate_path,
        input string label,
        output bit loaded
    );
        int fd;
        begin
            loaded = 1'b0;
            fd = $fopen(candidate_path, "r");
            if (fd != 0) begin
                $fclose(fd);
                if (label == "instruction") begin
                    // Memories store one 32-bit hex word per line.
                    $readmemh(candidate_path, dut.ifStage.insnMem.mem);
                end else begin
                    $readmemh(candidate_path, dut.memStage.dataMem.mem);
                end
                if (log_fd != 0) begin
                    $fdisplay(log_fd, "[%0t] Loaded %s memory from %s", $time, label, candidate_path);
                end
                loaded = 1'b1;
            end
        end
    endtask

    task automatic reload_memories;
        bit loaded;
        begin
            // Try absolute paths first for Vivado, then several relative paths
            // for command-line simulations launched from different directories.
            insn_mem_loaded = 1'b0;
            data_mem_loaded = 1'b0;

            readmemh_if_exists(INSN_MEM_FILE_ABS, "instruction", loaded);
            insn_mem_loaded |= loaded;
            if (!insn_mem_loaded) begin
                readmemh_if_exists("source/utils/insn.mem", "instruction", loaded);
                insn_mem_loaded |= loaded;
            end
            if (!insn_mem_loaded) begin
                readmemh_if_exists("../source/utils/insn.mem", "instruction", loaded);
                insn_mem_loaded |= loaded;
            end
            if (!insn_mem_loaded) begin
                readmemh_if_exists("../../source/utils/insn.mem", "instruction", loaded);
                insn_mem_loaded |= loaded;
            end
            if (!insn_mem_loaded) begin
                readmemh_if_exists("../../../source/utils/insn.mem", "instruction", loaded);
                insn_mem_loaded |= loaded;
            end

            readmemh_if_exists(DATA_MEM_FILE_ABS, "data", loaded);
            data_mem_loaded |= loaded;
            if (!data_mem_loaded) begin
                readmemh_if_exists("source/utils/data.mem", "data", loaded);
                data_mem_loaded |= loaded;
            end
            if (!data_mem_loaded) begin
                readmemh_if_exists("../source/utils/data.mem", "data", loaded);
                data_mem_loaded |= loaded;
            end
            if (!data_mem_loaded) begin
                readmemh_if_exists("../../source/utils/data.mem", "data", loaded);
                data_mem_loaded |= loaded;
            end
            if (!data_mem_loaded) begin
                readmemh_if_exists("../../../source/utils/data.mem", "data", loaded);
                data_mem_loaded |= loaded;
            end

            if (!insn_mem_loaded) begin
                $fatal(1, "Failed to load instruction memory image.");
            end

            if (!data_mem_loaded) begin
                $fatal(1, "Failed to load data memory image.");
            end
        end
    endtask

    task automatic open_log_file;
        begin
            // Debug log is human-readable and intentionally separate from the
            // structured pipeline dump used by tb_dump_to_konata.py.
            log_fd = 0;
            log_path = "";

            log_fd = $fopen(SOURCE_DEBUG_FILE_ABS, "w");
            if (log_fd != 0) begin
                log_path = SOURCE_DEBUG_FILE_ABS;
            end else begin
                log_fd = $fopen("source/topCPU_tb_debug.txt", "w");
                if (log_fd != 0) begin
                    log_path = "source/topCPU_tb_debug.txt";
                end else begin
                    log_fd = $fopen("../source/topCPU_tb_debug.txt", "w");
                    if (log_fd != 0) begin
                        log_path = "../source/topCPU_tb_debug.txt";
                    end else begin
                        log_fd = $fopen("../../source/topCPU_tb_debug.txt", "w");
                        if (log_fd != 0) begin
                            log_path = "../../source/topCPU_tb_debug.txt";
                        end else begin
                            log_fd = $fopen("../../../source/topCPU_tb_debug.txt", "w");
                            if (log_fd != 0) begin
                                log_path = "../../../source/topCPU_tb_debug.txt";
                            end else begin
                                log_fd = $fopen("../../../../source/topCPU_tb_debug.txt", "w");
                                if (log_fd != 0) begin
                                    log_path = "../../../../source/topCPU_tb_debug.txt";
                                end
                            end
                        end
                    end
                end
            end

            if (log_fd == 0) begin
                $fatal(1, "Failed to open %s under the source directory.", DEBUG_FILE_NAME);
            end
        end
    endtask

    task automatic open_dump_file;
        begin
            // Structured dump path mirrors open_log_file's search strategy so
            // users can run the testbench from Vivado without changing cwd.
            dump_fd = 0;
            dump_path = "";

            dump_fd = $fopen(SOURCE_DUMP_FILE_ABS, "w");
            if (dump_fd != 0) begin
                dump_path = SOURCE_DUMP_FILE_ABS;
            end else begin
                dump_fd = $fopen("source/topCPU_tb_output.txt", "w");
                if (dump_fd != 0) begin
                    dump_path = "source/topCPU_tb_output.txt";
                end else begin
                    dump_fd = $fopen("../source/topCPU_tb_output.txt", "w");
                    if (dump_fd != 0) begin
                        dump_path = "../source/topCPU_tb_output.txt";
                    end else begin
                        dump_fd = $fopen("../../source/topCPU_tb_output.txt", "w");
                        if (dump_fd != 0) begin
                            dump_path = "../../source/topCPU_tb_output.txt";
                        end else begin
                            dump_fd = $fopen("../../../source/topCPU_tb_output.txt", "w");
                            if (dump_fd != 0) begin
                                dump_path = "../../../source/topCPU_tb_output.txt";
                            end else begin
                                dump_fd = $fopen("../../../../source/topCPU_tb_output.txt", "w");
                                if (dump_fd != 0) begin
                                    dump_path = "../../../../source/topCPU_tb_output.txt";
                                end
                            end
                        end
                    end
                end
            end

            if (dump_fd == 0) begin
                $fatal(1, "Failed to open %s under the source directory.", DUMP_FILE_NAME);
            end
        end
    endtask

    task automatic write_dump_header;
        begin
            // Header is versioned so the Python converter can reject old or
            // incompatible dump formats cleanly in the future.
            $fdisplay(dump_fd, "TB_PIPE_DUMP_V1");
            $fdisplay(dump_fd, "META clk_period_ns=%0d reset_vector=0x%08h", 10, RESET_VECTOR);
            $fdisplay(dump_fd, "META max_cycles=%0d", MAX_CYCLES);
            $fdisplay(dump_fd, "META dump_path=%s", dump_path);
            $fdisplay(dump_fd, "META notes=Use tb_dump_to_konata.py to convert this dump to Konata format");
        end
    endtask

    task automatic dump_cycle_snapshot;
        bit if_valid;
        bit id_valid;
        begin
            // The dump schema is intentionally text based: it is easy to inspect
            // by hand and easy for tb_dump_to_konata.py to parse.
            if_valid = insn_known(dut.if_fetch_bus.insn);
            id_valid = insn_known(dut.if_decode_bus.insn);

            $fdisplay(dump_fd,
                      "SNAPSHOT cycle=%0d time=%0t rst=%0d wrEnable=%0d stall=%0d flush=%0d jumpEnable=%0d toHost=0x%08h uartValid=%0d uartData=0x%02h checkPC=0x%08h check=0x%08h checkData=0x%08h",
                      cycle_count, $time, rst, dut.wrEnable, dut.stall, dut.flush, dut.jumpEnable,
                      toHost, uartValid, uartData, checkPC, check, checkData);
            $fdisplay(dump_fd,
                      "IF valid=%0d pc=0x%08h insn=0x%08h",
                      if_valid, dut.if_fetch_bus.pc, dut.if_fetch_bus.insn);
            $fdisplay(dump_fd,
                      "ID valid=%0d pc=0x%08h insn=0x%08h rd=%0d regWrite=%0d memWrite=%0d branchCtr=%0d aluCtr=%0d memCtr=%0d regA=%0d regB=%0d imm=0x%08h",
                      id_valid, dut.if_decode_bus.pc, dut.if_decode_bus.insn, dut.id_exe_in_bus.rd,
                      dut.id_exe_in_bus.registerWriteEnable, dut.id_exe_in_bus.dataWriteEnable,
                      dut.id_exe_in_bus.branchCtr, dut.id_exe_in_bus.aluCtr, dut.id_exe_in_bus.memCtr,
                      dut.id_exe_in_bus.regA, dut.id_exe_in_bus.regB, dut.id_exe_in_bus.immediate);
            $fdisplay(dump_fd,
                      "EX pc=0x%08h rd=%0d regWrite=%0d memWrite=%0d memCtr=%0d aluOut=0x%08h dataA=0x%08h dataB=0x%08h imm=0x%08h",
                      dut.id_exe_bus.pc, dut.id_exe_bus.rd, dut.id_exe_bus.registerWriteEnable,
                      dut.id_exe_bus.dataWriteEnable, dut.id_exe_bus.memCtr, dut.aluOut_exe,
                      dut.forwardA_exe, dut.forwardB_exe, dut.id_exe_bus.immediate);
            $fdisplay(dump_fd,
                      "MEM pc=0x%08h rd=%0d regWrite=%0d memWrite=%0d memCtr=%0d aluOut=0x%08h dataB=0x%08h rdData=0x%08h toHostHit=%0d uartHit=%0d fromHostHit=%0d",
                      dut.exe_mem_bus.pc, dut.exe_mem_bus.rd, dut.exe_mem_bus.registerWriteEnable,
                      dut.exe_mem_bus.dataWriteEnable, dut.exe_mem_bus.memCtr, dut.exe_mem_bus.aluOut,
                      dut.exe_mem_bus.dataB, dut.rdData_mem, dut.memStage.dataMem.toHostHit,
                      dut.memStage.dataMem.uartHit, dut.memStage.dataMem.fromHostHit);
            $fdisplay(dump_fd,
                      "WB pc=0x%08h rd=%0d regWrite=%0d wbSelect=%0d aluSrc=0x%08h rdData=0x%08h dataWb=0x%08h",
                      dut.mem_wb_bus.pc, dut.mem_wb_bus.rd, dut.mem_wb_bus.registerWriteEnable,
                      dut.mem_wb_bus.wbSelect, dut.mem_wb_bus.aluSrc, dut.mem_wb_bus.rdData, dut.data_wb);
            if (uartValid && (uartData != 8'h0d)) begin
                // UART and tohost are emitted as explicit events so the trace
                // viewer can annotate key software-visible moments.
                $fdisplay(dump_fd, "EVENT kind=uart cycle=%0d data=0x%02h", cycle_count, uartData);
            end
            if (word_known(toHost) && (toHost != '0)) begin
                $fdisplay(dump_fd, "EVENT kind=tohost cycle=%0d data=0x%08h", cycle_count, toHost);
            end
            $fdisplay(dump_fd, "ENDSNAPSHOT");
        end
    endtask

    initial begin
        // Hold reset low for two positive edges, matching the active-low reset
        // convention used by the RTL.
        rst = 1'b0;
        fromHost = '0;
        cycle_count = 0;
        timed_out = 1'b0;

        open_log_file();
        open_dump_file();
        reload_memories();
        write_dump_header();

        $display("*****simulation started*****\n debug=%s dump=%s", log_path, dump_path);

        repeat (2) @(posedge clk);
        rst = 1'b1;

        $fdisplay(log_fd, " time | cycle |   pc   | instruction | checkData");
        $fdisplay(log_fd, "------+-------+--------+-------------+----------");
        $fdisplay(log_fd, "[%0t] Structured pipeline dump is being written to %s", $time, dump_path);

        forever begin
            @(posedge clk);
            cycle_count++;
            // Wait a delta of real time so registered outputs and combinational
            // debug paths have settled before sampling the pipeline snapshot.
            #1ns;

            $fdisplay(log_fd, "%5t | %5d | 0x%08h | 0x%08h  | 0x%08h",
                      $time, cycle_count, checkPC, check, checkData);

            if (uartValid && (uartData != 8'h0d)) begin
                $fwrite(log_fd, "%c", uartData);
                $write("%c", uartData);
            end

            if ((checkPC >= 32'h0000_04F0) && (checkPC <= 32'h0000_0510)) begin
                // Extra targeted debug around the software completion path.
                $fdisplay(log_fd,
                          "           DBG | toHost=0x%08h hit=%0d wr=%0d memCtr=%0b aluOut=0x%08h dataB=0x%08h",
                          toHost,
                          dut.memStage.dataMem.toHostHit,
                          dut.exe_mem_bus.dataWriteEnable,
                          dut.exe_mem_bus.memCtr,
                          dut.exe_mem_bus.aluOut,
                          dut.exe_mem_bus.dataB);
            end

            dump_cycle_snapshot();

            if (word_known(toHost) && (toHost != '0)) begin
                // Software writes a non-zero tohost value to end the run.
                break;
            end

            if (cycle_count >= MAX_CYCLES) begin
                // A timeout event is written to both logs before ending the sim.
                timed_out = 1'b1;
                $fdisplay(dump_fd,
                          "EVENT kind=timeout cycle=%0d limit=%0d checkPC=0x%08h check=0x%08h toHost=0x%08h",
                          cycle_count, MAX_CYCLES, checkPC, check, toHost);
                $fdisplay(log_fd, "");
                $fdisplay(log_fd,
                          "Timeout after %0d cycles: PC=0x%08h instruction=0x%08h toHost=0x%08h",
                          MAX_CYCLES, checkPC, check, toHost);
                break;
            end
        end

        if (timed_out) begin
            // Console output is intentionally short: one begin message and one
            // final status line group. Detailed data stays in the log files.
            $display("*****simulation finished*****\n cycles=%0d limit=%0d toHost=0x%08h pc=0x%08h dump=%s debug=%s",
                     cycle_count, MAX_CYCLES, toHost, checkPC, dump_path, log_path);
            $display("*****simulation result: TIMEOUT*****");
        end else if (toHost == TOHOST_PASS_VALUE) begin
            $display("*****simulation finished*****\n cycles=%0d toHost=0x%08h pc=0x%08h dump=%s debug=%s",
                     cycle_count, toHost, checkPC, dump_path, log_path);
            $display("*****simulation result: SUCCESS*****");
        end else begin
            $display("*****simulation finished*****\n cycles=%0d toHost=0x%08h pc=0x%08h dump=%s debug=%s",
                     cycle_count, toHost, checkPC, dump_path, log_path);
            $display("*****simulation result: FAIL (toHost=0x%08h)*****", toHost);
        end
        $fdisplay(log_fd, "");
        $fdisplay(log_fd, "Final state after %0d cycles:", cycle_count);
        if (timed_out) begin
            $fdisplay(log_fd, "  Status       = TIMEOUT");
        end else begin
            $fdisplay(log_fd, "  Status       = COMPLETED");
        end
        $fdisplay(log_fd, "  PC           = 0x%08h", checkPC);
        $fdisplay(log_fd, "  Instruction  = 0x%08h", check);
        $fdisplay(log_fd, "  Writeback    = 0x%08h", checkData);
        $fdisplay(log_fd, "  toHost       = 0x%08h", toHost);
        $fdisplay(log_fd, "  dataMem[0]   = 0x%08h", dut.memStage.dataMem.mem[0]);
        $fdisplay(log_fd, "  dataMem[1]   = 0x%08h", dut.memStage.dataMem.mem[1]);
        $fclose(log_fd);
        $fclose(dump_fd);

        $finish;
    end

endmodule
