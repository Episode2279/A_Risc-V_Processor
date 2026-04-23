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
  VerilatedVcdC* tfp = NULL;

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
           "max_cycles=%llu trace=%s\n",
           (unsigned long long)max_cycles,
           enable_trace ? "on" : "off");

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
  fclose(log_file);
  delete topCPU;
  delete contextp;

  return exit_code;
}
