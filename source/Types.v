//true and false
`define TRUE  1b'1
`define FALSE 1b'0
//reset value
`define RESET_VECTOR 0
//instruction size 4 Bytes * 32 entries = 128 Bytes, need 7 bits to locate the instruction
`define INS_ADDR 7
`define INS_ADDR_SIZE 128
`define instructionAddrPath logic[`INS_ADDR-1:0]

`define WORD_SIZE 32 
`define INS_SIZE 32
`define instruction logic[`INS_SIZE-1:0] 

//data size 4 Bytes * 4096 entries =2^14 Bytes,need 14 bits to addressing.
`define DATA_ADDR 14
`define DATA_ADDR_SIZE 16384
`define dataAddrPath logic[`DATA_ADDR-1:0]