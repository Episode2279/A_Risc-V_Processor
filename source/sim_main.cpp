#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

#include "VtopCPU.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

int main(int argc, char** argv, char** env) {
  VerilatedContext* contextp = new VerilatedContext;
  contextp->commandArgs(argc, argv);
  VtopCPU* topCPU = new VtopCPU{contextp};

  VerilatedVcdC* tfp = new VerilatedVcdC;
  contextp->traceEverOn(true);
  topCPU->trace(tfp, 0);
  tfp->open("wave.vcd");

  int cnt = 0;
  topCPU->clk = 0;
  topCPU->rst = 0;
  topCPU->fromHost_i = 0;

  while (!contextp->gotFinish()) {
    topCPU->clk ^= 1;
    if (cnt == 2) {
      topCPU->rst = 1;
    }

    printf("clk %d, rst %d\n", topCPU->clk, topCPU->rst);
    printf("program counter %d\n", topCPU->checkPC);
    printf("check data %d\n", topCPU->checkData);
    printf("instruction %x\n\n\n\n", topCPU->check);

    topCPU->eval();

    tfp->dump(contextp->time());
    contextp->timeInc(1);

    if (topCPU->uartValid_o && topCPU->uartData_o != '\r') {
      putchar(topCPU->uartData_o);
      fflush(stdout);
    }

    if (topCPU->toHost_o != 0) {
      printf("\ntohost = 0x%08x\n", topCPU->toHost_o);
      break;
    }

    if (cnt++ > 66) {
      printf("simulation finished!!");
      break;
    }
  }

  delete topCPU;
  tfp->close();
  delete contextp;
  return 0;
}
