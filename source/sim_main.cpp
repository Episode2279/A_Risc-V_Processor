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
static const char* kPipeDumpFileName = "topCPU_tb_output.txt";

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

  fprintf(dump_file, "TB_PIPE_DUMP_V1\n");
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
          "SNAPSHOT cycle=%llu time=%llu rst=%u wrEnable=%u stall=%u flush=%u "
          "jumpEnable=%u toHost=0x%08x uartValid=%u uartData=0x%02x "
          "checkPC=0x%08x check=0x%08x checkData=0x%08x\n",
          (unsigned long long)cycle_count,
          (unsigned long long)sim_time,
          (unsigned)topCPU->rst,
          (unsigned)topCPU->dbg_wrEnable,
          (unsigned)topCPU->dbg_stall,
          (unsigned)topCPU->dbg_flush,
          (unsigned)topCPU->dbg_jumpEnable,
          (uint32_t)topCPU->toHost_o,
          (unsigned)topCPU->uartValid_o,
          (uint32_t)topCPU->uartData_o,
          (uint32_t)topCPU->checkPC,
          (uint32_t)topCPU->check,
          (uint32_t)topCPU->checkData);

  fprintf(dump_file,
          "IF valid=%u pc=0x%08x insn=0x%08x\n",
          (unsigned)topCPU->dbg_if_valid,
          (uint32_t)topCPU->dbg_if_pc,
          (uint32_t)topCPU->dbg_if_insn);
  fprintf(dump_file,
          "ID valid=%u pc=0x%08x insn=0x%08x rd=%u regWrite=%u memWrite=%u "
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
          "EX pc=0x%08x rd=%u regWrite=%u memWrite=%u memCtr=%u "
          "aluOut=0x%08x dataA=0x%08x dataB=0x%08x imm=0x%08x\n",
          (uint32_t)topCPU->dbg_ex_pc,
          (unsigned)topCPU->dbg_ex_rd,
          (unsigned)topCPU->dbg_ex_regWrite,
          (unsigned)topCPU->dbg_ex_memWrite,
          (unsigned)topCPU->dbg_ex_memCtr,
          (uint32_t)topCPU->dbg_ex_aluOut,
          (uint32_t)topCPU->dbg_ex_dataA,
          (uint32_t)topCPU->dbg_ex_dataB,
          (uint32_t)topCPU->dbg_ex_imm);
  fprintf(dump_file,
          "MEM pc=0x%08x rd=%u regWrite=%u memWrite=%u memCtr=%u "
          "aluOut=0x%08x dataB=0x%08x rdData=0x%08x "
          "toHostHit=%u uartHit=%u fromHostHit=%u\n",
          (uint32_t)topCPU->dbg_mem_pc,
          (unsigned)topCPU->dbg_mem_rd,
          (unsigned)topCPU->dbg_mem_regWrite,
          (unsigned)topCPU->dbg_mem_memWrite,
          (unsigned)topCPU->dbg_mem_memCtr,
          (uint32_t)topCPU->dbg_mem_aluOut,
          (uint32_t)topCPU->dbg_mem_dataB,
          (uint32_t)topCPU->dbg_mem_rdData,
          (unsigned)topCPU->dbg_mem_toHostHit,
          (unsigned)topCPU->dbg_mem_uartHit,
          (unsigned)topCPU->dbg_mem_fromHostHit);
  fprintf(dump_file,
          "WB pc=0x%08x rd=%u regWrite=%u wbSelect=%u aluSrc=0x%08x "
          "rdData=0x%08x dataWb=0x%08x\n",
          (uint32_t)topCPU->dbg_wb_pc,
          (unsigned)topCPU->dbg_wb_rd,
          (unsigned)topCPU->dbg_wb_regWrite,
          (unsigned)topCPU->dbg_wb_wbSelect,
          (uint32_t)topCPU->dbg_wb_aluSrc,
          (uint32_t)topCPU->dbg_wb_rdData,
          (uint32_t)topCPU->dbg_wb_dataWb);

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
  FILE* log_file = fopen("simulation_output.txt", "w");
  if (log_file == NULL) {
    fprintf(stderr, "Failed to open simulation_output.txt for writing.\n");
    delete topCPU;
    delete contextp;
    return 1;
  }

  const uint64_t max_cycles = get_max_cycles(argc, argv);
  const bool enable_trace = trace_enabled(argc, argv);
  const bool enable_pipe_dump = pipe_dump_enabled(argc, argv);
  FILE* pipe_dump_file = NULL;
  VerilatedVcdC* tfp = NULL;

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
    tfp->open("wave.vcd");
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

  uint64_t cycle_count = 0;
  uint32_t tohost = 0;
  bool timed_out = true;

  while (!contextp->gotFinish() && cycle_count < max_cycles) {
    cycle_count++;
    eval_cycle(topCPU, contextp, tfp);
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
           "cycles=%llu toHost=0x%08x pc=0x%08x instruction=0x%08x\n",
           (unsigned long long)cycle_count,
           tohost,
           (uint32_t)topCPU->checkPC,
           (uint32_t)topCPU->check);

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
  fclose(log_file);
  delete topCPU;
  delete contextp;

  return exit_code;
}
