#!/usr/bin/env python3
import sys

def bin_to_byte_hex(in_path, out_path, total_bytes):
    data = open(in_path, "rb").read()
    if len(data) > total_bytes:
        raise SystemExit(f"{in_path}: {len(data)} bytes > {total_bytes} bytes IMEM size")
    data = data + b"\x00" * (total_bytes - len(data))

    with open(out_path, "w") as f:
        for b in data:
            f.write(f"{b:02x}\n")

if __name__ == "__main__":
    # usage: bin2bytes.py imem.bin insMem.txt 0x10000
    bin_to_byte_hex(sys.argv[1], sys.argv[2], int(sys.argv[3], 0))
