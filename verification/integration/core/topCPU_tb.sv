`timescale 1ns / 1ps

module topCPU_tb #(
    // Hard simulation cap. Normal tests should finish by writing tohost before
    // this limit; reaching the cap is reported as TIMEOUT.
    parameter int MAX_CYCLES = 10_000_000
);
    import TypesPkg::*;

    // Generated images and traces live under build/.  Plusargs take precedence
    // so Vivado can pass normalized absolute paths from its generated run dir.
    localparam time CLK_PERIOD = 10ns;
    localparam string DEBUG_FILE_NAME = "topCPU_tb_debug.txt";
    localparam string DUMP_FILE_NAME  = "topCPU_tb_output.txt";
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
        .dbg_issue0(),
        .dbg_issue1(),
        .dbg_if_valid(),
        .dbg_if_pc(),
        .dbg_if_insn(),
        .dbg_if1_valid(),
        .dbg_if1_pc(),
        .dbg_if1_insn(),
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
        .dbg_id1_valid(),
        .dbg_id1_pc(),
        .dbg_id1_insn(),
        .dbg_id1_rd(),
        .dbg_id1_regWrite(),
        .dbg_id1_memWrite(),
        .dbg_id1_branchCtr(),
        .dbg_id1_aluCtr(),
        .dbg_id1_memCtr(),
        .dbg_id1_regA(),
        .dbg_id1_regB(),
        .dbg_id1_imm(),
        .dbg_ex_pc(),
        .dbg_ex_rd(),
        .dbg_ex_regWrite(),
        .dbg_ex_memWrite(),
        .dbg_ex_memCtr(),
        .dbg_ex_aluOut(),
        .dbg_ex_dataA(),
        .dbg_ex_dataB(),
        .dbg_ex_imm(),
        .dbg_ex1_pc(),
        .dbg_ex1_rd(),
        .dbg_ex1_regWrite(),
        .dbg_ex1_memWrite(),
        .dbg_ex1_memCtr(),
        .dbg_ex1_aluOut(),
        .dbg_ex1_dataA(),
        .dbg_ex1_dataB(),
        .dbg_ex1_imm(),
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
        .dbg_mem1_pc(),
        .dbg_mem1_rd(),
        .dbg_mem1_regWrite(),
        .dbg_mem1_memWrite(),
        .dbg_mem1_memCtr(),
        .dbg_mem1_aluOut(),
        .dbg_mem1_dataB(),
        .dbg_mem1_rdData(),
        .dbg_wb_pc(),
        .dbg_wb_rd(),
        .dbg_wb_regWrite(),
        .dbg_wb_wbSelect(),
        .dbg_wb_aluSrc(),
        .dbg_wb_rdData(),
        .dbg_wb_dataWb(),
        .dbg_wb1_pc(),
        .dbg_wb1_rd(),
        .dbg_wb1_regWrite(),
        .dbg_wb1_wbSelect(),
        .dbg_wb1_aluSrc(),
        .dbg_wb1_rdData(),
        .dbg_wb1_dataWb(),
        .dbg_robCount(),
        .dbg_issueCount(),
        .dbg_lsqCount(),
        .dbg_retireCount(),
        .dbg_perfDualIssueCycles(), .dbg_perfSingleIssueCycles(), .dbg_perfIqNoReadyCycles(),
        .dbg_perfPort0LsuBlockedCycles(), .dbg_perfPort0BranchBlockedCycles(),
        .dbg_perfLsqOrderBlockedCycles(),
        .dbg_perfStoreBufferAliasBlockedCycles(),
        .dbg_perfMmioOrderBlockedCycles(),
        .dbg_perfDcacheRequestBlockedCycles(),
        .dbg_perfLsuInternalBlockedCycles(),
        .dbg_perfLsuFallbackCycles(),
        .dbg_perfRobFullCycles(), .dbg_perfIqFullCycles(), .dbg_perfLsqFullCycles(),
        .dbg_perfPrfEmptyCycles(), .dbg_perfBranchCount(), .dbg_perfBranchMispredictCount(),
        .dbg_perfJumpSerializationCycles()
        ,.dbg_perfConditionalCount(),.dbg_perfConditionalMispredictCount(),
        .dbg_perfDirectionMispredictCount(),.dbg_perfTargetMispredictCount(),.dbg_perfBtbMissCount(),
        .dbg_perfJalMispredictCount(),.dbg_perfJalrMispredictCount(),.dbg_perfRasMissCount(),
        .dbg_perfStoreCommitStallCycles(),
        .dbg_perfIcacheRequests(),.dbg_perfIcacheHits(),.dbg_perfIcacheMisses(),
        .dbg_perfIcacheLineMisses(),.dbg_perfIcacheMissStallCycles(),
        .dbg_perfIcacheRefillLines(),.dbg_perfIcacheRefillCycles(),
        .dbg_perfIcacheCrosslineMisses(),.dbg_perfIcacheResponseBackpressureCycles(),
        .dbg_perfDcacheRequests(),.dbg_perfDcacheLoadHits(),.dbg_perfDcacheLoadMisses(),
        .dbg_perfDcacheStoreHits(),.dbg_perfDcacheStoreMisses(),.dbg_perfDcacheBusyCycles(),
        .dbg_perfDcacheRefillLines(),.dbg_perfDcacheRefillCycles(),
        .dbg_perfDcacheMmioRequests(),.dbg_perfDcacheRequestBackpressureCycles(),
        .dbg_scOverrideEvent(),.dbg_scCorrectEvent(),.dbg_scHarmEvent(),
        .dbg_scFamilyCorrectSupport(),.dbg_scFamilyHarmSupport(),
        .dbg_loopHitEvent(),.dbg_loopConfidentEvent(),
        .dbg_loopOverrideEvent(),.dbg_loopCorrectEvent(),
        .dbg_loopHarmEvent(),.dbg_loopTripMismatchEvent(),
        .dbg_branchTrainValid(),.dbg_branchTrainTaken(),
        .dbg_branchTrainTagePrediction(),.dbg_branchTrainFinalPrediction(),
        .dbg_branchTrainStrong(),.dbg_branchTrainScLowConfidence(),
        .dbg_branchTrainPc(),.dbg_branchTrainHistory(),
        .dbg_branchTrainPathHistory(),
        .dbg_dispatch0Valid(),.dbg_dispatch1Valid(),
        .dbg_dispatch0RobTag(),.dbg_dispatch1RobTag(),
        .dbg_dispatch0Pc(),.dbg_dispatch1Pc(),
        .dbg_dispatch0Insn(),.dbg_dispatch1Insn(),
        .dbg_dispatch0Fu(),.dbg_dispatch1Fu(),
        .dbg_oooIssue0Valid(),.dbg_oooIssue1Valid(),
        .dbg_oooIssueFallbackValid(),
        .dbg_oooIssue0RobTag(),.dbg_oooIssue1RobTag(),
        .dbg_oooIssueFallbackRobTag(),
        .dbg_oooIssue0Pc(),.dbg_oooIssue1Pc(),
        .dbg_oooIssueFallbackPc(),
        .dbg_oooIssue0Fu(),.dbg_oooIssue1Fu(),
        .dbg_oooIssueFallbackFu(),
        .dbg_complete0Valid(),.dbg_complete1Valid(),
        .dbg_complete0RobTag(),.dbg_complete1RobTag(),
        .dbg_complete0Exception(),.dbg_complete1Exception(),
        .dbg_complete0Value(),.dbg_complete1Value(),
        .dbg_commit0Valid(),.dbg_commit1Valid(),
        .dbg_commit0RobTag(),.dbg_commit1RobTag(),
        .dbg_commit0Pc(),.dbg_commit1Pc(),
        .dbg_commit0Rd(),.dbg_commit1Rd(),
        .dbg_commit0Data(),.dbg_commit1Data(),
        .dbg_recoverValid(),.dbg_recoverRobTag(),.dbg_globalFlush()
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
                    $readmemh(candidate_path, dut.ifStage.insnMem0.mem);
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
        string requested_path;
        begin
            insn_mem_loaded = 1'b0;
            data_mem_loaded = 1'b0;

            if ($value$plusargs("insn-mem=%s", requested_path)) begin
                readmemh_if_exists(requested_path, "instruction", loaded);
                insn_mem_loaded |= loaded;
            end
            if (!insn_mem_loaded) begin
                readmemh_if_exists("build/images/insn.mem", "instruction", loaded);
                insn_mem_loaded |= loaded;
            end
            if (!insn_mem_loaded) begin
                readmemh_if_exists("../build/images/insn.mem", "instruction", loaded);
                insn_mem_loaded |= loaded;
            end
            if (!insn_mem_loaded) begin
                readmemh_if_exists("../../build/images/insn.mem", "instruction", loaded);
                insn_mem_loaded |= loaded;
            end
            if (!insn_mem_loaded) begin
                readmemh_if_exists("../../../build/images/insn.mem", "instruction", loaded);
                insn_mem_loaded |= loaded;
            end

            if ($value$plusargs("data-mem=%s", requested_path)) begin
                readmemh_if_exists(requested_path, "data", loaded);
                data_mem_loaded |= loaded;
            end
            if (!data_mem_loaded) begin
                readmemh_if_exists("build/images/data.mem", "data", loaded);
                data_mem_loaded |= loaded;
            end
            if (!data_mem_loaded) begin
                readmemh_if_exists("../build/images/data.mem", "data", loaded);
                data_mem_loaded |= loaded;
            end
            if (!data_mem_loaded) begin
                readmemh_if_exists("../../build/images/data.mem", "data", loaded);
                data_mem_loaded |= loaded;
            end
            if (!data_mem_loaded) begin
                readmemh_if_exists("../../../build/images/data.mem", "data", loaded);
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

            if (!$value$plusargs("debug-log=%s", log_path))
                log_path = "build/traces/topCPU_tb_debug.txt";
            log_fd = $fopen(log_path, "w");
            if (log_fd == 0) begin
                log_path = DEBUG_FILE_NAME;
                log_fd = $fopen(log_path, "w");
            end

            if (log_fd == 0) begin
                $fatal(1, "Failed to open debug log %s.", log_path);
            end
        end
    endtask

    task automatic open_dump_file;
        begin
            dump_fd = 0;
            dump_path = "";

            if (!$value$plusargs("pipe-dump-file=%s", dump_path))
                dump_path = "build/traces/topCPU_tb_output.txt";
            dump_fd = $fopen(dump_path, "w");
            if (dump_fd == 0) begin
                dump_path = DUMP_FILE_NAME;
                dump_fd = $fopen(dump_path, "w");
            end

            if (dump_fd == 0) begin
                $fatal(1, "Failed to open pipeline dump %s.", dump_path);
            end
        end
    endtask

    task automatic write_dump_header;
        begin
            // Header is versioned so the Python converter can reject old or
            // incompatible dump formats cleanly in the future.
            $fdisplay(dump_fd, "TB_PIPE_DUMP_V2");
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
            // V2 is event-oriented.  Every back-end record carries the ROB tag
            // which identifies a dynamic instruction even when execution and
            // completion occur out of program order.
            if_valid = insn_known(dut.if_fetch_bus.insn);
            id_valid = insn_known(dut.if_decode_bus.insn);

            $fdisplay(dump_fd,
                      "SNAPSHOT cycle=%0d time=%0t rst=%0d stall=%0d frontendFlush=%0d globalFlush=%0d recover=%0d recoverTag=%0d robCount=%0d iqCount=%0d lsqCount=%0d toHost=0x%08h uartValid=%0d uartData=0x%02h checkPC=0x%08h check=0x%08h checkData=0x%08h",
                      cycle_count, $time, rst, dut.stall, dut.flush, dut.trapValid,
                      dut.backend.recoveryValid, dut.backend.recoveryTag,
                      dut.robCount, dut.issueCount, dut.lsqCount,
                      toHost, uartValid, uartData, checkPC, check, checkData);
            $fdisplay(dump_fd,
                      "IF0 valid=%0d pc=0x%08h insn=0x%08h",
                      if_valid, dut.if_fetch_bus.pc, dut.if_fetch_bus.insn);
            $fdisplay(dump_fd,
                      "IF1 valid=%0d pc=0x%08h insn=0x%08h",
                      insn_known(dut.if_fetch_bus1.insn), dut.if_fetch_bus1.pc, dut.if_fetch_bus1.insn);
            $fdisplay(dump_fd,
                      "ID0 valid=%0d pc=0x%08h insn=0x%08h rd=%0d regWrite=%0d memWrite=%0d branchCtr=%0d aluCtr=%0d memCtr=%0d regA=%0d regB=%0d imm=0x%08h",
                      id_valid, dut.if_decode_bus.pc, dut.if_decode_bus.insn, dut.id_exe_in_bus.rd,
                      dut.id_exe_in_bus.registerWriteEnable, dut.id_exe_in_bus.dataWriteEnable,
                      dut.id_exe_in_bus.branchCtr, dut.id_exe_in_bus.aluCtr, dut.id_exe_in_bus.memCtr,
                      dut.id_exe_in_bus.regA, dut.id_exe_in_bus.regB, dut.id_exe_in_bus.immediate);
            $fdisplay(dump_fd,
                      "ID1 valid=%0d pc=0x%08h insn=0x%08h rd=%0d regWrite=%0d memWrite=%0d branchCtr=%0d aluCtr=%0d memCtr=%0d regA=%0d regB=%0d imm=0x%08h",
                      insn_known(dut.if_decode_bus1.insn), dut.if_decode_bus1.pc, dut.if_decode_bus1.insn, dut.id_exe1_in_bus.rd,
                      dut.id_exe1_in_bus.registerWriteEnable, dut.id_exe1_in_bus.dataWriteEnable,
                      dut.id_exe1_in_bus.branchCtr, dut.id_exe1_in_bus.aluCtr, dut.id_exe1_in_bus.memCtr,
                      dut.id_exe1_in_bus.regA, dut.id_exe1_in_bus.regB, dut.id_exe1_in_bus.immediate);
            $fdisplay(dump_fd,
                      "DISPATCH0 valid=%0d tag=%0d pc=0x%08h insn=0x%08h fu=%0d dest=%0d",
                      dut.backend.robAllocValid[0] && !dut.backend.recoveryValid && !dut.trapValid,
                      dut.backend.robAllocTag[0], dut.id_exe_in_bus.pc,
                      dut.if_decode_bus.insn, dut.backend.renamedUop[0].fuClass,
                      dut.backend.renamedUop[0].destPhys);
            $fdisplay(dump_fd,
                      "DISPATCH1 valid=%0d tag=%0d pc=0x%08h insn=0x%08h fu=%0d dest=%0d",
                      dut.backend.robAllocValid[1] && !dut.backend.recoveryValid && !dut.trapValid,
                      dut.backend.robAllocTag[1], dut.id_exe1_in_bus.pc,
                      dut.if_decode_bus1.insn, dut.backend.renamedUop[1].fuClass,
                      dut.backend.renamedUop[1].destPhys);
            $fdisplay(dump_fd,
                      "ISSUE0 valid=%0d tag=%0d pc=0x%08h fu=%0d",
                      dut.backend.issueValid[0] && dut.backend.issueReady[0],
                      dut.backend.issueUop[0].robTag,
                      dut.backend.issueUop[0].pc, dut.backend.issueUop[0].fuClass);
            $fdisplay(dump_fd,
                      "ISSUE1 valid=%0d tag=%0d pc=0x%08h fu=%0d",
                      dut.backend.issueValid[1] && dut.backend.issueReady[1],
                      dut.backend.issueUop[1].robTag,
                      dut.backend.issueUop[1].pc, dut.backend.issueUop[1].fuClass);
            $fdisplay(dump_fd,
                      "ISSUEF valid=%0d tag=%0d pc=0x%08h fu=%0d",
                      dut.backend.issueFallbackValid && dut.backend.issueFallbackReady,
                      dut.backend.issueFallbackUop.robTag,
                      dut.backend.issueFallbackUop.pc,
                      dut.backend.issueFallbackUop.fuClass);
            $fdisplay(dump_fd,
                      "COMPLETE0 valid=%0d tag=%0d exception=%0d value=0x%08h",
                      dut.backend.robCompleteValid[0], dut.backend.robCompleteTag[0],
                      dut.backend.robCompleteException[0], dut.backend.robCompleteValue[0]);
            $fdisplay(dump_fd,
                      "COMPLETE1 valid=%0d tag=%0d exception=%0d value=0x%08h",
                      dut.backend.robCompleteValid[1], dut.backend.robCompleteTag[1],
                      dut.backend.robCompleteException[1], dut.backend.robCompleteValue[1]);
            $fdisplay(dump_fd,
                      "COMMIT0 valid=%0d tag=%0d pc=0x%08h rd=%0d data=0x%08h",
                      dut.backend.robRetireValid[0], dut.backend.robCommitTag[0],
                      dut.backend.robCommitEntry[0].pc, dut.commitRd[0], dut.commitData[0]);
            $fdisplay(dump_fd,
                      "COMMIT1 valid=%0d tag=%0d pc=0x%08h rd=%0d data=0x%08h",
                      dut.backend.robRetireValid[1], dut.backend.robCommitTag[1],
                      dut.backend.robCommitEntry[1].pc, dut.commitRd[1], dut.commitData[1]);
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
        // Capture the freshly released reset state before the first post-reset
        // clock edge advances the initial fetch pair into decode.
        #1ns;
        dump_cycle_snapshot();

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
