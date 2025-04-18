//true and false
`define TRUE  1'b1
`define FALSE 1'b0
//reset value
`define RESET_VECTOR 0
//instruction size 4 Bytes * 32 entries = 128 Bytes, need 7 bits to locate the instruction
`define INS_ADDR 7
`define INS_ADDR_SIZE 128
`define instructionAddrPath logic[`INS_ADDR-1:0]

//instruction length and general word length
`define WORD_SIZE 32 
`define INS_SIZE 32
`define BLOCK_SIZE 8
`define instruction logic[`INS_SIZE-1:0]
`define data logic[`WORD_SIZE-1:0]
`define block logic[`BLOCK_SIZE-1:0]

//data size 4 Bytes * 4096 entries =2^14 Bytes,need 14 bits to address.
`define DATA_ADDR 14
`define DATA_ADDR_SIZE 16384
`define dataAddrPath logic[`DATA_ADDR-1:0]

//RISC-V has 32 registers,use 5 bits to address it.
`define REG_NUM 32
`define REG_ADDR 5
`define regAddr logic[`REG_ADDR-1:0]

//ALU controll signal
`define ctrALU logic[1:0]
`define AND 2'b11
`define OR 2'b10
`define ADD 2'b00
`define SUB 2'b01

//Branch controll signal

`define ctrBranch logic[1:0]
`define BEQ 2'b00
`define BLT 2'b10
`define NO_JUMP 2'b01