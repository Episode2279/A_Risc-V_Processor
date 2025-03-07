//true and false
`define TRUE  1b'1
`define FALSE 1b'0
//reset value
`define RESET_VECTOR 0
//instruction size 4 Bytes * 32 entries = 128 Bytes, need 7 bits to locate the instruction
`define INS_ADDR 7
`define INS_ADDR_SIZE 128
`define instructionAddrPath logic[`INS_ADDR-1:0]
