#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
 
#include "VtopCPU.h"  // create `top.v`,so use `Vtop.h`
#include "verilated.h"
 
#include "verilated_vcd_c.h" //可选，如果要导出vcd则需要加上
 
int main(int argc, char** argv, char** env) {
 
  VerilatedContext* contextp = new VerilatedContext;
  contextp->commandArgs(argc, argv);
  VtopCPU* topCPU = new VtopCPU{contextp};
  
 
  VerilatedVcdC* tfp = new VerilatedVcdC; //初始化VCD对象指针
  contextp->traceEverOn(true); //打开追踪功能
  topCPU->trace(tfp, 0); //
  tfp->open("wave.vcd"); //设置输出的文件wave.vcd
 
  int cnt = 0;
  while (!contextp->gotFinish()) {

    topCPU->clk ^=1;
    if(cnt==0){
      topCPU->rst = 0;
    }else if(cnt==2){
      topCPU->rst = 1;
    }
    printf("clk %d, rst %d\n",topCPU->clk,topCPU->rst);
    printf("program counter %d\n",topCPU->checkPC);
    printf("check data %d\n",topCPU->checkData);
    printf("instruction %x\n\n\n\n",topCPU->check);
    
    
    topCPU->eval();
 
    tfp->dump(contextp->time()); //dump wave
    contextp->timeInc(1); //推动仿真时间
 

    if(cnt++>66){
        printf("simulation finished!!");
        break;
    }

  }
  delete topCPU;
  tfp->close();
  delete contextp;
  return 0;
}