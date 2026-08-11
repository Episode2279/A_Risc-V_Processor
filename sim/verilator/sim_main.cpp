#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "VtopCPU.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

static const uint64_t kDefaultMaxCycles = 10000000ULL;
static const uint32_t kTohostPassValue = 1U;
static const char* kSimulationLogFileName = "build/traces/simulation_output.txt";
static const char* kPipeDumpFileName = "build/traces/topCPU_tb_output.txt";
static const char* kWaveFileName = "build/traces/wave.vcd";

static void log_both(FILE* log_file, const char* fmt, ...) {
  va_list args;
  va_start(args, fmt);
  vprintf(fmt, args);
  va_end(args);

  if (log_file != NULL) {
    va_start(args, fmt);
    vfprintf(log_file, fmt, args);
    va_end(args);
    fflush(log_file);
  }
}

static uint64_t parse_u64(const char* text, uint64_t fallback) {
  char* end = NULL;
  uint64_t value = strtoull(text, &end, 0);
  return (end != text) ? value : fallback;
}

static uint64_t get_max_cycles(int argc, char** argv) {
  const char* env_cycles = getenv("SIM_MAX_CYCLES");
  uint64_t max_cycles = env_cycles ? parse_u64(env_cycles, kDefaultMaxCycles)
                                   : kDefaultMaxCycles;

  for (int i = 1; i < argc; ++i) {
    const char* arg = argv[i];
    const char* plus_prefix = "+max-cycles=";
    const char* dash_prefix = "--max-cycles=";

    if (strncmp(arg, plus_prefix, strlen(plus_prefix)) == 0) {
      max_cycles = parse_u64(arg + strlen(plus_prefix), max_cycles);
    } else if (strncmp(arg, dash_prefix, strlen(dash_prefix)) == 0) {
      max_cycles = parse_u64(arg + strlen(dash_prefix), max_cycles);
    }
  }

  return max_cycles;
}

static bool trace_enabled(int argc, char** argv) {
  const char* env_trace = getenv("SIM_TRACE");
  if (env_trace != NULL && strcmp(env_trace, "0") != 0) {
    return true;
  }

  for (int i = 1; i < argc; ++i) {
    if (strcmp(argv[i], "+trace") == 0 || strcmp(argv[i], "--trace") == 0) {
      return true;
    }
  }

  return false;
}

static bool pipe_dump_enabled(int argc, char** argv) {
  const char* env_dump = getenv("SIM_PIPE_DUMP");
  bool enable_dump = (env_dump == NULL || strcmp(env_dump, "0") != 0);

  for (int i = 1; i < argc; ++i) {
    if (strcmp(argv[i], "+pipe-dump") == 0 || strcmp(argv[i], "--pipe-dump") == 0) {
      enable_dump = true;
    } else if (strcmp(argv[i], "+no-pipe-dump") == 0 ||
               strcmp(argv[i], "--no-pipe-dump") == 0) {
      enable_dump = false;
    }
  }

  return enable_dump;
}

static void write_pipe_dump_header(FILE* dump_file, uint64_t max_cycles) {
  if (dump_file == NULL) {
    return;
  }

  fprintf(dump_file, "TB_PIPE_DUMP_V2\n");
  fprintf(dump_file, "META clk_period_ns=10 reset_vector=0x%08x\n", 0U);
  fprintf(dump_file, "META max_cycles=%llu\n", (unsigned long long)max_cycles);
  fprintf(dump_file, "META dump_path=%s\n", kPipeDumpFileName);
  fprintf(dump_file, "META notes=Use tb_dump_to_konata.py to convert this dump to Konata format\n");
}

static void dump_pipeline_snapshot(FILE* dump_file,
                                   const VtopCPU* topCPU,
                                   uint64_t cycle_count,
                                   uint64_t sim_time) {
  if (dump_file == NULL) {
    return;
  }

  fprintf(dump_file,
          "SNAPSHOT cycle=%llu time=%llu rst=%u stall=%u frontendFlush=%u "
          "globalFlush=%u recover=%u recoverTag=%u robCount=%u iqCount=%u "
          "lsqCount=%u toHost=0x%08x uartValid=%u uartData=0x%02x "
          "checkPC=0x%08x check=0x%08x checkData=0x%08x\n",
          (unsigned long long)cycle_count,
          (unsigned long long)sim_time,
          (unsigned)topCPU->rst,
          (unsigned)topCPU->dbg_stall,
          (unsigned)topCPU->dbg_flush,
          (unsigned)topCPU->dbg_globalFlush,
          (unsigned)topCPU->dbg_recoverValid,
          (unsigned)topCPU->dbg_recoverRobTag,
          (unsigned)topCPU->dbg_robCount,
          (unsigned)topCPU->dbg_issueCount,
          (unsigned)topCPU->dbg_lsqCount,
          (uint32_t)topCPU->toHost_o,
          (unsigned)topCPU->uartValid_o,
          (uint32_t)topCPU->uartData_o,
          (uint32_t)topCPU->checkPC,
          (uint32_t)topCPU->check,
          (uint32_t)topCPU->checkData);

  fprintf(dump_file,
          "IF0 valid=%u pc=0x%08x insn=0x%08x\n",
          (unsigned)topCPU->dbg_if_valid,
          (uint32_t)topCPU->dbg_if_pc,
          (uint32_t)topCPU->dbg_if_insn);
  fprintf(dump_file,
          "IF1 valid=%u pc=0x%08x insn=0x%08x\n",
          (unsigned)topCPU->dbg_if1_valid,
          (uint32_t)topCPU->dbg_if1_pc,
          (uint32_t)topCPU->dbg_if1_insn);
  fprintf(dump_file,
          "ID0 valid=%u pc=0x%08x insn=0x%08x rd=%u regWrite=%u memWrite=%u "
          "branchCtr=%u aluCtr=%u memCtr=%u regA=%u regB=%u imm=0x%08x\n",
          (unsigned)topCPU->dbg_id_valid,
          (uint32_t)topCPU->dbg_id_pc,
          (uint32_t)topCPU->dbg_id_insn,
          (unsigned)topCPU->dbg_id_rd,
          (unsigned)topCPU->dbg_id_regWrite,
          (unsigned)topCPU->dbg_id_memWrite,
          (unsigned)topCPU->dbg_id_branchCtr,
          (unsigned)topCPU->dbg_id_aluCtr,
          (unsigned)topCPU->dbg_id_memCtr,
          (unsigned)topCPU->dbg_id_regA,
          (unsigned)topCPU->dbg_id_regB,
          (uint32_t)topCPU->dbg_id_imm);
  fprintf(dump_file,
          "ID1 valid=%u pc=0x%08x insn=0x%08x rd=%u regWrite=%u memWrite=%u "
          "branchCtr=%u aluCtr=%u memCtr=%u regA=%u regB=%u imm=0x%08x\n",
          (unsigned)topCPU->dbg_id1_valid,
          (uint32_t)topCPU->dbg_id1_pc,
          (uint32_t)topCPU->dbg_id1_insn,
          (unsigned)topCPU->dbg_id1_rd,
          (unsigned)topCPU->dbg_id1_regWrite,
          (unsigned)topCPU->dbg_id1_memWrite,
          (unsigned)topCPU->dbg_id1_branchCtr,
          (unsigned)topCPU->dbg_id1_aluCtr,
          (unsigned)topCPU->dbg_id1_memCtr,
          (unsigned)topCPU->dbg_id1_regA,
          (unsigned)topCPU->dbg_id1_regB,
          (uint32_t)topCPU->dbg_id1_imm);
  fprintf(dump_file,
          "DISPATCH0 valid=%u tag=%u pc=0x%08x insn=0x%08x fu=%u\n",
          (unsigned)topCPU->dbg_dispatch0Valid,
          (unsigned)topCPU->dbg_dispatch0RobTag,
          (uint32_t)topCPU->dbg_dispatch0Pc,
          (uint32_t)topCPU->dbg_dispatch0Insn,
          (unsigned)topCPU->dbg_dispatch0Fu);
  fprintf(dump_file,
          "DISPATCH1 valid=%u tag=%u pc=0x%08x insn=0x%08x fu=%u\n",
          (unsigned)topCPU->dbg_dispatch1Valid,
          (unsigned)topCPU->dbg_dispatch1RobTag,
          (uint32_t)topCPU->dbg_dispatch1Pc,
          (uint32_t)topCPU->dbg_dispatch1Insn,
          (unsigned)topCPU->dbg_dispatch1Fu);
  fprintf(dump_file,
          "ISSUE0 valid=%u tag=%u pc=0x%08x fu=%u\n",
          (unsigned)topCPU->dbg_oooIssue0Valid,
          (unsigned)topCPU->dbg_oooIssue0RobTag,
          (uint32_t)topCPU->dbg_oooIssue0Pc,
          (unsigned)topCPU->dbg_oooIssue0Fu);
  fprintf(dump_file,
          "ISSUE1 valid=%u tag=%u pc=0x%08x fu=%u\n",
          (unsigned)topCPU->dbg_oooIssue1Valid,
          (unsigned)topCPU->dbg_oooIssue1RobTag,
          (uint32_t)topCPU->dbg_oooIssue1Pc,
          (unsigned)topCPU->dbg_oooIssue1Fu);
  fprintf(dump_file,
          "ISSUEF valid=%u tag=%u pc=0x%08x fu=%u\n",
          (unsigned)topCPU->dbg_oooIssueFallbackValid,
          (unsigned)topCPU->dbg_oooIssueFallbackRobTag,
          (uint32_t)topCPU->dbg_oooIssueFallbackPc,
          (unsigned)topCPU->dbg_oooIssueFallbackFu);
  fprintf(dump_file,
          "COMPLETE0 valid=%u tag=%u exception=%u value=0x%08x\n",
          (unsigned)topCPU->dbg_complete0Valid,
          (unsigned)topCPU->dbg_complete0RobTag,
          (unsigned)topCPU->dbg_complete0Exception,
          (uint32_t)topCPU->dbg_complete0Value);
  fprintf(dump_file,
          "COMPLETE1 valid=%u tag=%u exception=%u value=0x%08x\n",
          (unsigned)topCPU->dbg_complete1Valid,
          (unsigned)topCPU->dbg_complete1RobTag,
          (unsigned)topCPU->dbg_complete1Exception,
          (uint32_t)topCPU->dbg_complete1Value);
  fprintf(dump_file,
          "COMMIT0 valid=%u tag=%u pc=0x%08x rd=%u data=0x%08x\n",
          (unsigned)topCPU->dbg_commit0Valid,
          (unsigned)topCPU->dbg_commit0RobTag,
          (uint32_t)topCPU->dbg_commit0Pc,
          (unsigned)topCPU->dbg_commit0Rd,
          (uint32_t)topCPU->dbg_commit0Data);
  fprintf(dump_file,
          "COMMIT1 valid=%u tag=%u pc=0x%08x rd=%u data=0x%08x\n",
          (unsigned)topCPU->dbg_commit1Valid,
          (unsigned)topCPU->dbg_commit1RobTag,
          (uint32_t)topCPU->dbg_commit1Pc,
          (unsigned)topCPU->dbg_commit1Rd,
          (uint32_t)topCPU->dbg_commit1Data);

  if (topCPU->uartValid_o && topCPU->uartData_o != '\r') {
    fprintf(dump_file,
            "EVENT kind=uart cycle=%llu data=0x%02x\n",
            (unsigned long long)cycle_count,
            (uint32_t)topCPU->uartData_o);
  }
  if ((uint32_t)topCPU->toHost_o != 0U) {
    fprintf(dump_file,
            "EVENT kind=tohost cycle=%llu data=0x%08x\n",
            (unsigned long long)cycle_count,
            (uint32_t)topCPU->toHost_o);
  }
  fprintf(dump_file, "ENDSNAPSHOT\n");
}

static void dump_trace(VerilatedContext* contextp, VerilatedVcdC* tfp) {
  if (tfp != NULL) {
    tfp->dump(contextp->time());
  }
  contextp->timeInc(1);
}

static void eval_half_cycle(VtopCPU* topCPU,
                            VerilatedContext* contextp,
                            VerilatedVcdC* tfp,
                            uint8_t clk) {
  topCPU->clk = clk;
  topCPU->eval();
  dump_trace(contextp, tfp);
}

static void eval_cycle(VtopCPU* topCPU,
                       VerilatedContext* contextp,
                       VerilatedVcdC* tfp) {
  eval_half_cycle(topCPU, contextp, tfp, 0);
  eval_half_cycle(topCPU, contextp, tfp, 1);
}

int main(int argc, char** argv) {
  VerilatedContext* contextp = new VerilatedContext;
  contextp->commandArgs(argc, argv);

  VtopCPU* topCPU = new VtopCPU{contextp};
  FILE* log_file = fopen(kSimulationLogFileName, "w");
  if (log_file == NULL) {
    fprintf(stderr, "Failed to open %s for writing.\n", kSimulationLogFileName);
    delete topCPU;
    delete contextp;
    return 1;
  }

  const uint64_t max_cycles = get_max_cycles(argc, argv);
  const bool enable_trace = trace_enabled(argc, argv);
  const bool enable_pipe_dump = pipe_dump_enabled(argc, argv);
  FILE* pipe_dump_file = NULL;
  FILE* branch_trace_file = NULL;
  VerilatedVcdC* tfp = NULL;

  const char* branch_trace_path = getenv("SIM_BRANCH_TRACE");
  if (branch_trace_path != NULL && branch_trace_path[0] != '\0') {
    branch_trace_file = fopen(branch_trace_path, "w");
    if (branch_trace_file == NULL) {
      fprintf(stderr, "Failed to open branch trace %s.\n", branch_trace_path);
      fclose(log_file);
      delete topCPU;
      delete contextp;
      return 1;
    }
    fprintf(branch_trace_file,
            "pc,history,path,tage,final,taken,strong,sc_low\n");
  }

  if (enable_pipe_dump) {
    pipe_dump_file = fopen(kPipeDumpFileName, "w");
    if (pipe_dump_file == NULL) {
      fprintf(stderr, "Failed to open %s for writing.\n", kPipeDumpFileName);
      fclose(log_file);
      delete topCPU;
      delete contextp;
      return 1;
    }
    write_pipe_dump_header(pipe_dump_file, max_cycles);
  }

  if (enable_trace) {
    contextp->traceEverOn(true);
    tfp = new VerilatedVcdC;
    topCPU->trace(tfp, 0);
    tfp->open(kWaveFileName);
  }

  topCPU->clk = 0;
  topCPU->rst = 0;
  topCPU->fromHost_i = 0;
  topCPU->eval();

  log_both(log_file,
           "***** Verilator simulation started *****\n"
           "max_cycles=%llu trace=%s pipe_dump=%s\n",
           (unsigned long long)max_cycles,
           enable_trace ? "on" : "off",
           enable_pipe_dump ? kPipeDumpFileName : "off");

  for (int i = 0; i < 2; ++i) {
    eval_cycle(topCPU, contextp, tfp);
  }
  topCPU->rst = 1;
  // Snapshot the reset-release state before the first post-reset cycle shifts
  // the initial fetch pair into decode. This gives Konata a real IF stage for
  // the first two dynamic instructions.
  topCPU->eval();
  dump_trace(contextp, tfp);
  dump_pipeline_snapshot(pipe_dump_file, topCPU, 0, contextp->time());

  uint64_t cycle_count = 0;
  uint64_t retired_instructions = 0;
  uint64_t sc_overrides = 0;
  uint64_t sc_corrections = 0;
  uint64_t sc_harms = 0;
  uint64_t sc_family_correct_support[5] = {0, 0, 0, 0, 0};
  uint64_t sc_family_harm_support[5] = {0, 0, 0, 0, 0};
  uint64_t loop_hits = 0;
  uint64_t loop_confident = 0;
  uint64_t loop_overrides = 0;
  uint64_t loop_corrections = 0;
  uint64_t loop_harms = 0;
  uint64_t loop_trip_mismatches = 0;
  uint32_t tohost = 0;
  bool timed_out = true;

  while (!contextp->gotFinish() && cycle_count < max_cycles) {
    cycle_count++;
    eval_cycle(topCPU, contextp, tfp);
    retired_instructions += (uint64_t)topCPU->dbg_retireCount;
    sc_overrides += (uint64_t)topCPU->dbg_scOverrideEvent;
    sc_corrections += (uint64_t)topCPU->dbg_scCorrectEvent;
    sc_harms += (uint64_t)topCPU->dbg_scHarmEvent;
    for (unsigned family = 0; family < 5; ++family) {
      sc_family_correct_support[family] +=
          (uint64_t)((topCPU->dbg_scFamilyCorrectSupport >> family) & 1U);
      sc_family_harm_support[family] +=
          (uint64_t)((topCPU->dbg_scFamilyHarmSupport >> family) & 1U);
    }
    loop_hits += (uint64_t)topCPU->dbg_loopHitEvent;
    loop_confident += (uint64_t)topCPU->dbg_loopConfidentEvent;
    loop_overrides += (uint64_t)topCPU->dbg_loopOverrideEvent;
    loop_corrections += (uint64_t)topCPU->dbg_loopCorrectEvent;
    loop_harms += (uint64_t)topCPU->dbg_loopHarmEvent;
    loop_trip_mismatches +=
        (uint64_t)topCPU->dbg_loopTripMismatchEvent;
    if (branch_trace_file != NULL && topCPU->dbg_branchTrainValid) {
      fprintf(branch_trace_file,
              "%08x,%016llx,%04x,%u,%u,%u,%u,%u\n",
              (uint32_t)topCPU->dbg_branchTrainPc,
              (unsigned long long)topCPU->dbg_branchTrainHistory,
              (uint32_t)topCPU->dbg_branchTrainPathHistory,
              (unsigned)topCPU->dbg_branchTrainTagePrediction,
              (unsigned)topCPU->dbg_branchTrainFinalPrediction,
              (unsigned)topCPU->dbg_branchTrainTaken,
              (unsigned)topCPU->dbg_branchTrainStrong,
              (unsigned)topCPU->dbg_branchTrainScLowConfidence);
    }
    dump_pipeline_snapshot(pipe_dump_file, topCPU, cycle_count, contextp->time());

    if (topCPU->uartValid_o && topCPU->uartData_o != '\r') {
      putchar(topCPU->uartData_o);
      fflush(stdout);
      fputc(topCPU->uartData_o, log_file);
      fflush(log_file);
    }

    tohost = (uint32_t)topCPU->toHost_o;
    if (tohost != 0U) {
      timed_out = false;
      break;
    }
  }

  if (timed_out && pipe_dump_file != NULL) {
    fprintf(pipe_dump_file,
            "EVENT kind=timeout cycle=%llu limit=%llu checkPC=0x%08x "
            "check=0x%08x toHost=0x%08x\n",
            (unsigned long long)cycle_count,
            (unsigned long long)max_cycles,
            (uint32_t)topCPU->checkPC,
            (uint32_t)topCPU->check,
            (uint32_t)topCPU->toHost_o);
  }

  log_both(log_file,
           "\n***** Verilator simulation finished *****\n"
           "cycles=%llu toHost=0x%08x pc=0x%08x instruction=0x%08x "
           "rob=%u issue=%u lsq=%u\n",
           (unsigned long long)cycle_count,
           tohost,
           (uint32_t)topCPU->checkPC,
           (uint32_t)topCPU->check,
           (unsigned)topCPU->dbg_robCount,
           (unsigned)topCPU->dbg_issueCount,
           (unsigned)topCPU->dbg_lsqCount);
  log_both(log_file,
           "retired=%llu measured_ipc=%.4f\n",
           (unsigned long long)retired_instructions,
           cycle_count ? (double)retired_instructions / (double)cycle_count : 0.0);
  log_both(log_file,
           "PERF issue_dual=%llu issue_single=%llu iq_no_ready=%llu "
           "lsu_blocked=%llu branch_candidate_blocked=%llu\n"
           "PERF lsu_lsq_order=%llu lsu_sb_alias=%llu lsu_mmio_order=%llu "
           "lsu_dcache_request=%llu lsu_internal=%llu lsu_fallback=%llu\n"
           "PERF rob_full=%llu iq_full=%llu lsq_full=%llu prf_empty=%llu "
           "branches=%llu mispredicts=%llu jump_serialize=%llu\n",
           (unsigned long long)topCPU->dbg_perfDualIssueCycles,
           (unsigned long long)topCPU->dbg_perfSingleIssueCycles,
           (unsigned long long)topCPU->dbg_perfIqNoReadyCycles,
           (unsigned long long)topCPU->dbg_perfPort0LsuBlockedCycles,
           (unsigned long long)topCPU->dbg_perfPort0BranchBlockedCycles,
           (unsigned long long)topCPU->dbg_perfLsqOrderBlockedCycles,
           (unsigned long long)topCPU->dbg_perfStoreBufferAliasBlockedCycles,
           (unsigned long long)topCPU->dbg_perfMmioOrderBlockedCycles,
           (unsigned long long)topCPU->dbg_perfDcacheRequestBlockedCycles,
           (unsigned long long)topCPU->dbg_perfLsuInternalBlockedCycles,
           (unsigned long long)topCPU->dbg_perfLsuFallbackCycles,
           (unsigned long long)topCPU->dbg_perfRobFullCycles,
           (unsigned long long)topCPU->dbg_perfIqFullCycles,
           (unsigned long long)topCPU->dbg_perfLsqFullCycles,
           (unsigned long long)topCPU->dbg_perfPrfEmptyCycles,
           (unsigned long long)topCPU->dbg_perfBranchCount,
           (unsigned long long)topCPU->dbg_perfBranchMispredictCount,
           (unsigned long long)topCPU->dbg_perfJumpSerializationCycles);
  log_both(log_file,
           "BPU conditional=%llu conditional_misp=%llu direction_misp=%llu target_misp=%llu "
           "btb_miss=%llu jal_misp=%llu jalr_misp=%llu ras_miss=%llu\n",
           (unsigned long long)topCPU->dbg_perfConditionalCount,
           (unsigned long long)topCPU->dbg_perfConditionalMispredictCount,
           (unsigned long long)topCPU->dbg_perfDirectionMispredictCount,
           (unsigned long long)topCPU->dbg_perfTargetMispredictCount,
           (unsigned long long)topCPU->dbg_perfBtbMissCount,
           (unsigned long long)topCPU->dbg_perfJalMispredictCount,
           (unsigned long long)topCPU->dbg_perfJalrMispredictCount,
           (unsigned long long)topCPU->dbg_perfRasMissCount);
  const double retired_for_mpki = retired_instructions ?
      static_cast<double>(retired_instructions) : 1.0;
  const uint64_t dcache_load_accesses =
      static_cast<uint64_t>(topCPU->dbg_perfDcacheLoadHits) +
      static_cast<uint64_t>(topCPU->dbg_perfDcacheLoadMisses);
  log_both(log_file,
           "CACHE I req=%llu hit=%llu miss=%llu line_miss=%llu "
           "miss_stall=%llu refill_lines=%llu refill_cycles=%llu "
           "crossline_miss=%llu response_backpressure=%llu mpki=%.3f\n",
           (unsigned long long)topCPU->dbg_perfIcacheRequests,
           (unsigned long long)topCPU->dbg_perfIcacheHits,
           (unsigned long long)topCPU->dbg_perfIcacheMisses,
           (unsigned long long)topCPU->dbg_perfIcacheLineMisses,
           (unsigned long long)topCPU->dbg_perfIcacheMissStallCycles,
           (unsigned long long)topCPU->dbg_perfIcacheRefillLines,
           (unsigned long long)topCPU->dbg_perfIcacheRefillCycles,
           (unsigned long long)topCPU->dbg_perfIcacheCrosslineMisses,
           (unsigned long long)topCPU->dbg_perfIcacheResponseBackpressureCycles,
           1000.0 * static_cast<double>(topCPU->dbg_perfIcacheLineMisses) /
               retired_for_mpki);
  log_both(log_file,
           "CACHE D req=%llu load_hit=%llu load_miss=%llu load_miss_rate=%.3f%% "
           "store_hit=%llu store_miss=%llu mmio=%llu busy=%llu "
           "refill_lines=%llu refill_cycles=%llu request_backpressure=%llu "
           "store_commit_stall=%llu mpki=%.3f\n",
           (unsigned long long)topCPU->dbg_perfDcacheRequests,
           (unsigned long long)topCPU->dbg_perfDcacheLoadHits,
           (unsigned long long)topCPU->dbg_perfDcacheLoadMisses,
           dcache_load_accesses ?
               100.0 * static_cast<double>(topCPU->dbg_perfDcacheLoadMisses) /
                   static_cast<double>(dcache_load_accesses) : 0.0,
           (unsigned long long)topCPU->dbg_perfDcacheStoreHits,
           (unsigned long long)topCPU->dbg_perfDcacheStoreMisses,
           (unsigned long long)topCPU->dbg_perfDcacheMmioRequests,
           (unsigned long long)topCPU->dbg_perfDcacheBusyCycles,
           (unsigned long long)topCPU->dbg_perfDcacheRefillLines,
           (unsigned long long)topCPU->dbg_perfDcacheRefillCycles,
           (unsigned long long)topCPU->dbg_perfDcacheRequestBackpressureCycles,
           (unsigned long long)topCPU->dbg_perfStoreCommitStallCycles,
           1000.0 * static_cast<double>(topCPU->dbg_perfDcacheLoadMisses) /
               retired_for_mpki);
  log_both(log_file,
           "SC overrides=%llu corrections=%llu harms=%llu net=%lld\n",
           (unsigned long long)sc_overrides,
           (unsigned long long)sc_corrections,
           (unsigned long long)sc_harms,
           (long long)sc_corrections - (long long)sc_harms);
  static const char* kScFamilyNames[5] = {
      "bias", "global", "local", "imli", "path"};
  for (unsigned family = 0; family < 5; ++family) {
    log_both(log_file,
             "SC_FAMILY %s correction_support=%llu harm_support=%llu net=%lld\n",
             kScFamilyNames[family],
             (unsigned long long)sc_family_correct_support[family],
             (unsigned long long)sc_family_harm_support[family],
             (long long)sc_family_correct_support[family] -
                 (long long)sc_family_harm_support[family]);
  }
  log_both(log_file,
           "LOOP hits=%llu confident=%llu overrides=%llu corrections=%llu "
           "harms=%llu net=%lld trip_mismatch=%llu\n",
           (unsigned long long)loop_hits,
           (unsigned long long)loop_confident,
           (unsigned long long)loop_overrides,
           (unsigned long long)loop_corrections,
           (unsigned long long)loop_harms,
           (long long)loop_corrections - (long long)loop_harms,
           (unsigned long long)loop_trip_mismatches);

  int exit_code = 0;
  if (timed_out) {
    log_both(log_file, "***** simulation result: TIMEOUT *****\n");
    exit_code = 1;
  } else if (tohost == kTohostPassValue) {
    log_both(log_file, "***** simulation result: SUCCESS *****\n");
  } else {
    log_both(log_file, "***** simulation result: FAIL (toHost=0x%08x) *****\n", tohost);
    exit_code = 1;
  }

  if (tfp != NULL) {
    tfp->close();
    delete tfp;
  }
  if (pipe_dump_file != NULL) {
    fclose(pipe_dump_file);
  }
  if (branch_trace_file != NULL) {
    fclose(branch_trace_file);
  }
  fclose(log_file);
  delete topCPU;
  delete contextp;

  return exit_code;
}
