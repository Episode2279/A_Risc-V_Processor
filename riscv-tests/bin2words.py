#!/usr/bin/env python3
import sys

def bin_to_word_hex(in_path, out_path, total_bytes):
    data = open(in_path, "rb").read()
    if len(data) > total_bytes:
        raise SystemExit(f"{in_path}: {len(data)} bytes > {total_bytes}")
    data += b"\x00" * (total_bytes - len(data))
    with open(out_path, "w") as f:
        for i in range(0, total_bytes, 4):
            b0, b1, b2, b3 = data[i:i+4]
            w = b0 | (b1<<8) | (b2<<16) | (b3<<24)  # little-endian
            f.write(f"{w:08x}\n")

if __name__ == "__main__":
    bin_to_word_hex(sys.argv[1], sys.argv[2], int(sys.argv[3], 0))
