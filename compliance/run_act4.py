#!/usr/bin/env python3
"""Convert and run every ACT4 self-checking RV32I ELF on the Verilator DUT."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ELF_DIR = ROOT / "compliance/act4/work/a-riscv-processor-rv32i/elfs/rv32i/I"
DEFAULT_OBJCOPY = ROOT / ".tools/riscv-gcc-15/bin/riscv-none-elf-objcopy"
DEFAULT_SIM = ROOT / "build/verilator/act4/VtopCPU"
MEMORY_BYTES = 1 << 20


def binary_to_words(binary: Path, output: Path) -> None:
    data = binary.read_bytes()
    if len(data) > MEMORY_BYTES:
        raise RuntimeError(f"{binary}: {len(data)} bytes exceeds {MEMORY_BYTES}")
    data += bytes(MEMORY_BYTES - len(data))
    with output.open("w", encoding="ascii") as stream:
        for index in range(0, len(data), 4):
            stream.write(f"{int.from_bytes(data[index:index + 4], 'little'):08x}\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--elf-dir", type=Path, default=DEFAULT_ELF_DIR)
    parser.add_argument("--objcopy", type=Path, default=DEFAULT_OBJCOPY)
    parser.add_argument("--sim", type=Path, default=DEFAULT_SIM)
    parser.add_argument("--max-cycles", type=int, default=20_000_000)
    parser.add_argument("--match", default="*.elf")
    args = parser.parse_args()

    elfs = sorted(args.elf_dir.glob(args.match))
    if not elfs:
        raise SystemExit(f"no ELF tests found under {args.elf_dir}")

    passed: list[str] = []
    failed: list[str] = []
    with tempfile.TemporaryDirectory(prefix="a-riscv-act4-") as temp_name:
        temp = Path(temp_name)
        binary = temp / "test.bin"
        image = temp / "test.mem"
        for number, elf in enumerate(elfs, 1):
            subprocess.run([args.objcopy, "-O", "binary", elf, binary], check=True)
            binary_to_words(binary, image)
            print(f"[{number:02d}/{len(elfs):02d}] {elf.name}", flush=True)
            env = os.environ.copy()
            env["SIM_PIPE_DUMP"] = "0"
            result = subprocess.run(
                [args.sim, f"+insn-mem={image}", f"+data-mem={image}",
                 f"+max-cycles={args.max_cycles}"],
                cwd=ROOT, env=env,
            )
            (passed if result.returncode == 0 else failed).append(elf.name)

    print(f"ACT4 RV32I summary: {len(passed)} passed, {len(failed)} failed")
    if failed:
        print("Failed tests:")
        for name in failed:
            print(f"  {name}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
