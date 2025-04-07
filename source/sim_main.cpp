#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
 
#include "VtopCPU.h"  // create `top.v`,so use `Vtop.h`
#include "verilated.h"
 
#include "verilated_vcd_c.h" //可选，如果要导出vcd则需要加上
 
int main(int argc, char** argv, char** env) {
 
  VerilatedContext* contextp = new VerilatedContext;
  contextp->commandArgs(argc, argv);
  VtopCPU* top = new VtopCPU{contextp};
  
 
  VerilatedVcdC* tfp = new VerilatedVcdC; //初始化VCD对象指针
  contextp->traceEverOn(true); //打开追踪功能
  top->trace(tfp, 0); //
  tfp->open("wave.vcd"); //设置输出的文件wave.vcd
 
  int cnt = 0;
  while (!contextp->gotFinish()) {

    top->clk ^=1;

    
    
    top->eval();
 
    tfp->dump(contextp->time()); //dump wave
    contextp->timeInc(1); //推动仿真时间
 

    if(cnt++>100){
        printf("simulation finished!!");
        break;
    }

  }
  delete top;
  tfp->close();
  delete contextp;
  return 0;
}