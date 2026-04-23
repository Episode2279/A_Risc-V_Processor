#!/usr/bin/env python3
"""Convert the topCPU structured testbench dump into native Konata format.

This script is intentionally modeled after the event-based Kanata writer style
used in the referenced `pipe_read.py` file: it emits native Kanata `I/L/S/R/C`
records instead of Gem5 `O3PipeView:*` records.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional, TextIO, Union


def riscv_disasm_hex(
    insns: Union[str, int, Iterable[Union[str, int]]],
    *,
    abi_names: bool = False,
) -> Union[str, List[str]]:
    """Small built-in RV32I disassembler adapted from the reference script."""

    abi = [
        "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1",
        "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7",
        "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11",
        "t3", "t4", "t5", "t6",
    ]

    def rname(index: int) -> str:
        return abi[index] if abi_names else f"x{index}"

    def u32(value: int) -> int:
        return value & 0xFFFF_FFFF

    def sext(value: int, bits: int) -> int:
        sign = 1 << (bits - 1)
        value &= (1 << bits) - 1
        return (value ^ sign) - sign

    def bits(value: int, hi: int, lo: int) -> int:
        return (value >> lo) & ((1 << (hi - lo + 1)) - 1)

    def parse_one(item: Union[str, int]) -> int:
        if isinstance(item, int):
            return u32(item)
        text = item.strip().lower()
        if text.startswith("0x"):
            text = text[2:]
        return u32(int(text, 16))

    def disasm_one(inst: int) -> str:
        opcode = bits(inst, 6, 0)
        rd = bits(inst, 11, 7)
        funct3 = bits(inst, 14, 12)
        rs1 = bits(inst, 19, 15)
        rs2 = bits(inst, 24, 20)
        funct7 = bits(inst, 31, 25)

        imm_i = sext(bits(inst, 31, 20), 12)
        imm_s = sext((bits(inst, 31, 25) << 5) | bits(inst, 11, 7), 12)
        imm_b = sext(
            (bits(inst, 31, 31) << 12)
            | (bits(inst, 7, 7) << 11)
            | (bits(inst, 30, 25) << 5)
            | (bits(inst, 11, 8) << 1),
            13,
        )
        imm_u = bits(inst, 31, 12) << 12
        imm_j = sext(
            (bits(inst, 31, 31) << 20)
            | (bits(inst, 19, 12) << 12)
            | (bits(inst, 20, 20) << 11)
            | (bits(inst, 30, 21) << 1),
            21,
        )

        load_map = {0b000: "lb", 0b001: "lh", 0b010: "lw", 0b100: "lbu", 0b101: "lhu"}
        store_map = {0b000: "sb", 0b001: "sh", 0b010: "sw"}
        branch_map = {
            0b000: "beq",
            0b001: "bne",
            0b100: "blt",
            0b101: "bge",
            0b110: "bltu",
            0b111: "bgeu",
        }

        if opcode == 0b0110011:
            if funct3 == 0b000 and funct7 == 0b0000000:
                return f"add  {rname(rd)}, {rname(rs1)}, {rname(rs2)}"
            if funct3 == 0b000 and funct7 == 0b0100000:
                return f"sub  {rname(rd)}, {rname(rs1)}, {rname(rs2)}"
            if funct3 == 0b001 and funct7 == 0b0000000:
                return f"sll  {rname(rd)}, {rname(rs1)}, {rname(rs2)}"
            if funct3 == 0b010 and funct7 == 0b0000000:
                return f"slt  {rname(rd)}, {rname(rs1)}, {rname(rs2)}"
            if funct3 == 0b011 and funct7 == 0b0000000:
                return f"sltu {rname(rd)}, {rname(rs1)}, {rname(rs2)}"
            if funct3 == 0b100 and funct7 == 0b0000000:
                return f"xor  {rname(rd)}, {rname(rs1)}, {rname(rs2)}"
            if funct3 == 0b101 and funct7 == 0b0000000:
                return f"srl  {rname(rd)}, {rname(rs1)}, {rname(rs2)}"
            if funct3 == 0b101 and funct7 == 0b0100000:
                return f"sra  {rname(rd)}, {rname(rs1)}, {rname(rs2)}"
            if funct3 == 0b110 and funct7 == 0b0000000:
                return f"or   {rname(rd)}, {rname(rs1)}, {rname(rs2)}"
            if funct3 == 0b111 and funct7 == 0b0000000:
                return f"and  {rname(rd)}, {rname(rs1)}, {rname(rs2)}"
            return f".word 0x{inst:08x}"

        if opcode == 0b0010011:
            shamt = bits(inst, 24, 20)
            if funct3 == 0b000:
                return f"addi {rname(rd)}, {rname(rs1)}, {imm_i}"
            if funct3 == 0b010:
                return f"slti {rname(rd)}, {rname(rs1)}, {imm_i}"
            if funct3 == 0b011:
                return f"sltiu {rname(rd)}, {rname(rs1)}, {imm_i}"
            if funct3 == 0b100:
                return f"xori {rname(rd)}, {rname(rs1)}, {imm_i}"
            if funct3 == 0b110:
                return f"ori  {rname(rd)}, {rname(rs1)}, {imm_i}"
            if funct3 == 0b111:
                return f"andi {rname(rd)}, {rname(rs1)}, {imm_i}"
            if funct3 == 0b001 and funct7 == 0b0000000:
                return f"slli {rname(rd)}, {rname(rs1)}, {shamt}"
            if funct3 == 0b101 and funct7 == 0b0000000:
                return f"srli {rname(rd)}, {rname(rs1)}, {shamt}"
            if funct3 == 0b101 and funct7 == 0b0100000:
                return f"srai {rname(rd)}, {rname(rs1)}, {shamt}"
            return f".word 0x{inst:08x}"

        if opcode == 0b0000011:
            mnemonic = load_map.get(funct3)
            return f"{mnemonic:<4} {rname(rd)}, {imm_i}({rname(rs1)})" if mnemonic else f".word 0x{inst:08x}"

        if opcode == 0b0100011:
            mnemonic = store_map.get(funct3)
            return f"{mnemonic:<4} {rname(rs2)}, {imm_s}({rname(rs1)})" if mnemonic else f".word 0x{inst:08x}"

        if opcode == 0b1100011:
            mnemonic = branch_map.get(funct3)
            return f"{mnemonic:<4} {rname(rs1)}, {rname(rs2)}, {imm_b}" if mnemonic else f".word 0x{inst:08x}"

        if opcode == 0b0110111:
            return f"lui  {rname(rd)}, 0x{(imm_u >> 12):x}"
        if opcode == 0b0010111:
            return f"auipc {rname(rd)}, 0x{(imm_u >> 12):x}"
        if opcode == 0b1101111:
            return f"jal  {rname(rd)}, {imm_j}"
        if opcode == 0b1100111 and funct3 == 0:
            return f"jalr {rname(rd)}, {imm_i}({rname(rs1)})"

        if opcode == 0b1110011:
            imm12 = bits(inst, 31, 20)
            if funct3 == 0 and rd == 0 and rs1 == 0:
                if imm12 == 0:
                    return "ecall"
                if imm12 == 1:
                    return "ebreak"
            return f".word 0x{inst:08x}"

        return f".word 0x{inst:08x}"

    if isinstance(insns, (str, int)):
        return disasm_one(parse_one(insns))
    return [disasm_one(parse_one(item)) for item in insns]


@dataclass
class Snapshot:
    cycle: int
    time: int
    rst: int
    wr_enable: int
    stall: int
    flush: int
    jump_enable: int
    issue0: int
    issue1: int
    to_host: int
    uart_valid: int
    uart_data: int
    stages: Dict[str, Dict[str, int | str]] = field(default_factory=dict)


@dataclass
class PipeEntry:
    iid: str
    token: tuple[int, int]
    pc: int
    insn: int
    asm: str
    stage: Optional[str]
    flushed: bool = False


def parse_int(value: str) -> int:
    if value.startswith(("0x", "0X")):
        return int(value, 16)
    return int(value, 10)


def parse_kv_line(line: str) -> tuple[str, Dict[str, str]]:
    parts = line.strip().split()
    record_type = parts[0]
    values: Dict[str, str] = {}
    for token in parts[1:]:
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        values[key] = value
    return record_type, values


def load_dump(path: Path) -> List[Snapshot]:
    snapshots: List[Snapshot] = []
    current: Optional[Snapshot] = None

    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line == "TB_PIPE_DUMP_V1" or line.startswith("META"):
                continue

            record_type, values = parse_kv_line(line)

            if record_type == "SNAPSHOT":
                current = Snapshot(
                    cycle=parse_int(values["cycle"]),
                    time=parse_int(values["time"]),
                    rst=parse_int(values["rst"]),
                    wr_enable=parse_int(values["wrEnable"]),
                    stall=parse_int(values["stall"]),
                    flush=parse_int(values["flush"]),
                    jump_enable=parse_int(values["jumpEnable"]),
                    issue0=parse_int(values.get("issue0", "0")),
                    issue1=parse_int(values.get("issue1", "0")),
                    to_host=parse_int(values["toHost"]),
                    uart_valid=parse_int(values["uartValid"]),
                    uart_data=parse_int(values["uartData"]),
                )
                continue

            if current is None:
                continue

            if record_type.startswith(("IF", "ID", "EX", "MEM", "WB")):
                parsed_stage: Dict[str, int | str] = {}
                for key, value in values.items():
                    if value.startswith(("0x", "0X")) or value.isdigit():
                        parsed_stage[key] = parse_int(value)
                    else:
                        parsed_stage[key] = value
                current.stages[record_type] = parsed_stage
                continue

            if record_type == "ENDSNAPSHOT":
                snapshots.append(current)
                current = None

    return snapshots


def write_header(out: TextIO) -> None:
    out.write("Kanata\t0004\n")
    out.write("C=\t-1\n")


def disasm_cached(insn: int, cache: Dict[int, str]) -> str:
    if insn not in cache:
        cache[insn] = str(riscv_disasm_hex(insn, abi_names=False))
    return cache[insn]


def is_real_insn(insn: int) -> bool:
    return insn != 0


def entry_line(entry: PipeEntry) -> str:
    return f"PC=0x{entry.pc:08x} | 0x{entry.insn:08x} | {entry.asm}"


def entry_detail(entry: PipeEntry) -> str:
    return f"(pc=0x{entry.pc:08x}, insn=0x{entry.insn:08x})"


VISIBLE_SLOTS = ["IF0", "IF1", "ID0", "ID1", "EX0", "EX1", "MEM0", "MEM1", "WB0", "WB1"]
TOKEN_SLOTS = {"IF0", "IF1", "ID0", "ID1"}


def stage_data(snapshot: Snapshot, stage_name: str) -> Dict[str, int | str]:
    if stage_name in snapshot.stages:
        return snapshot.stages[stage_name]
    legacy_name = stage_name.rstrip("01")
    if legacy_name in snapshot.stages:
        return snapshot.stages[legacy_name]
    return {}


def stage_token(snapshot: Snapshot, stage_name: str) -> Optional[tuple[int, int]]:
    stage = stage_data(snapshot, stage_name)
    valid = int(stage.get("valid", 0))
    pc = int(stage.get("pc", 0))
    insn = int(stage.get("insn", 0))
    if not valid or not is_real_insn(insn):
        return None
    return (pc, insn)


def new_entry(
    token: tuple[int, int],
    stage_name: str,
    state: Dict[str, object],
    cache: Dict[int, str],
) -> PipeEntry:
    pc, insn = token
    iid = str(state["next_iid"])
    state["next_iid"] = int(state["next_iid"]) + 1
    return PipeEntry(
        iid=iid,
        token=token,
        pc=pc,
        insn=insn,
        asm=disasm_cached(insn, cache),
        stage=stage_name,
    )


def emit_new_entry(entry: PipeEntry) -> List[str]:
    return [
        f"I\t{entry.iid}\t{entry.iid}\t0\n",
        f"L\t{entry.iid}\t0\t{entry_line(entry)}\n",
        f"L\t{entry.iid}\t1\t{entry_detail(entry)}\n",
    ]


def decode_window_after_issue(
    prev_slots: Dict[str, PipeEntry],
    prev_snapshot: Snapshot,
) -> tuple[List[PipeEntry], List[PipeEntry], Optional[PipeEntry], Optional[PipeEntry]]:
    decode_queue = [prev_slots[name] for name in ("ID0", "ID1") if name in prev_slots]
    fetch_queue = [prev_slots[name] for name in ("IF0", "IF1") if name in prev_slots]

    ex0_entry: Optional[PipeEntry] = None
    ex1_entry: Optional[PipeEntry] = None

    if prev_snapshot.flush:
        return [], [], None, None

    if prev_snapshot.issue0 and decode_queue:
        ex0_entry = decode_queue.pop(0)
    if prev_snapshot.issue1 and decode_queue:
        ex1_entry = decode_queue.pop(0)

    while len(decode_queue) < 2 and fetch_queue:
        decode_queue.append(fetch_queue.pop(0))

    return decode_queue[:2], fetch_queue[:2], ex0_entry, ex1_entry


def build_current_slots(
    prev_slots: Dict[str, PipeEntry],
    prev_snapshot: Optional[Snapshot],
    snapshot: Snapshot,
    state: Dict[str, object],
    cache: Dict[int, str],
) -> tuple[Dict[str, PipeEntry], List[str]]:
    current_slots: Dict[str, PipeEntry] = {}
    emitted: List[str] = []

    # Older pipeline stages are tracked purely by slot progression. This avoids
    # aliasing loop iterations that reuse the same PC in later stages.
    if prev_snapshot is not None:
        if "EX0" in prev_slots:
            current_slots["MEM0"] = prev_slots["EX0"]
        if "EX1" in prev_slots:
            current_slots["MEM1"] = prev_slots["EX1"]
        if "MEM0" in prev_slots:
            current_slots["WB0"] = prev_slots["MEM0"]
        if "MEM1" in prev_slots:
            current_slots["WB1"] = prev_slots["MEM1"]

        decode_queue, fetch_queue, ex0_entry, ex1_entry = decode_window_after_issue(prev_slots, prev_snapshot)
        if ex0_entry is not None:
            current_slots["EX0"] = ex0_entry
        if ex1_entry is not None:
            current_slots["EX1"] = ex1_entry

        for slot_name, entry in zip(("ID0", "ID1"), decode_queue):
            current_slots[slot_name] = entry
        for slot_name, entry in zip(("IF0", "IF1"), fetch_queue):
            current_slots[slot_name] = entry

    # Reconcile the token-bearing IF/ID slots with the actual dump. Any slot
    # that is not explained by carry-over is a newly fetched/visible instruction.
    for slot_name in ("ID0", "ID1", "IF0", "IF1"):
        token = stage_token(snapshot, slot_name)
        assigned = current_slots.get(slot_name)

        if token is None:
            current_slots.pop(slot_name, None)
            continue

        if assigned is not None and assigned.token == token:
            continue

        entry = new_entry(token, slot_name, state, cache)
        current_slots[slot_name] = entry
        emitted.extend(emit_new_entry(entry))

    # For EX/MEM/WB, drop predicted occupants if the current snapshot does not
    # show the matching PC in that slot. This keeps the converter aligned even
    # if the trace begins mid-pipeline or after skipped cycles.
    for slot_name in ("EX0", "EX1", "MEM0", "MEM1", "WB0", "WB1"):
        entry = current_slots.get(slot_name)
        if entry is None:
            continue
        stage = stage_data(snapshot, slot_name)
        if int(stage.get("pc", -1)) != entry.pc:
            current_slots.pop(slot_name, None)

    return current_slots, emitted


def emit_stage_changes(
    prev_slots: Dict[str, PipeEntry],
    prev_snapshot: Optional[Snapshot],
    current_slots: Dict[str, PipeEntry],
    state: Dict[str, object],
) -> List[str]:
    out: List[str] = []

    for slot_name in VISIBLE_SLOTS:
        entry = current_slots.get(slot_name)
        if entry is None:
            continue
        entry.stage = slot_name
        out.append(f"S\t{entry.iid}\t0\t{slot_name}\n")

    current_ids = {entry.iid for entry in current_slots.values()}
    flush_slots = {"IF0", "IF1", "ID0", "ID1"}

    for slot_name in VISIBLE_SLOTS:
        entry = prev_slots.get(slot_name)
        if entry is None or entry.iid in current_ids:
            continue

        out.append(f"S\t{entry.iid}\t0\tCM\n")
        if prev_snapshot is not None and prev_snapshot.flush and slot_name in flush_slots:
            out.append(f"R\t{entry.iid}\t0\t1\n")
        else:
            out.append(f"R\t{entry.iid}\t{state['next_rid']}\t0\n")
            state["next_rid"] = int(state["next_rid"]) + 1
        entry.stage = None

    return out


def convert_dump_to_kanata(input_path: Path, output_path: Path, *, skip_cycles: int = 0) -> int:
    snapshots = load_dump(input_path)
    if skip_cycles:
        snapshots = [snapshot for snapshot in snapshots if snapshot.cycle > skip_cycles]

    cache: Dict[int, str] = {}
    prev_slots: Dict[str, PipeEntry] = {}
    prev_snapshot: Optional[Snapshot] = None
    state: Dict[str, object] = {
        "next_iid": 1,
        "next_rid": 0,
        "current_cycle": -1,
    }
    issued = 0

    with output_path.open("w", encoding="utf-8", newline="\n") as out:
        write_header(out)
        for snapshot in snapshots:
            cycle_delta = snapshot.cycle - int(state["current_cycle"])
            if cycle_delta > 0:
                out.write(f"C\t{cycle_delta}\n")
            state["current_cycle"] = snapshot.cycle

            current_slots, emitted = build_current_slots(prev_slots, prev_snapshot, snapshot, state, cache)
            issued += sum(1 for line in emitted if line.startswith("I\t"))
            for line in emitted:
                out.write(line)

            out.write(f"// cycle {snapshot.cycle}\n")
            for line in emit_stage_changes(prev_slots, prev_snapshot, current_slots, state):
                out.write(line)
            out.write("\n\n")

            prev_slots = current_slots
            prev_snapshot = snapshot

        if prev_slots:
            out.write("// end-of-trace drain\n")
            for slot_name in VISIBLE_SLOTS:
                entry = prev_slots.get(slot_name)
                if entry is None:
                    continue
                out.write(f"S\t{entry.iid}\t0\tCM\n")
                if prev_snapshot is not None and prev_snapshot.flush and slot_name in {"IF0", "IF1", "ID0", "ID1"}:
                    out.write(f"R\t{entry.iid}\t0\t1\n")
                else:
                    out.write(f"R\t{entry.iid}\t{state['next_rid']}\t0\n")
                    state["next_rid"] = int(state["next_rid"]) + 1

    return issued


def validate_kanata_output(path: Path) -> Dict[str, object]:
    issued: Dict[str, bool] = {}
    retired: Dict[str, bool] = {}
    stages: Dict[str, List[str]] = {}

    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\n")
            if line.startswith("I\t"):
                parts = line.split("\t")
                if len(parts) >= 2:
                    issued[parts[1]] = True
            elif line.startswith("R\t"):
                parts = line.split("\t")
                if len(parts) >= 2:
                    retired[parts[1]] = True
            elif line.startswith("S\t"):
                parts = line.split("\t")
                if len(parts) >= 4:
                    stages.setdefault(parts[1], []).append(parts[3])

    missing_retire = sorted((iid for iid in issued if iid not in retired), key=str)
    extra_retire = sorted((iid for iid in retired if iid not in issued), key=str)

    return {
        "issued": len(issued),
        "retired": len(retired),
        "missing_retire": missing_retire,
        "extra_retire": extra_retire,
        "stage_samples": {iid: seq for iid, seq in list(stages.items())[:5]},
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Convert the topCPU structured dump into native Konata trace format."
    )
    parser.add_argument(
        "input",
        nargs="?",
        default="A_Risc-V_Processor/source/topCPU_tb_output.txt",
        help="Structured dump produced by topCPU_tb.sv",
    )
    parser.add_argument(
        "output",
        nargs="?",
        default="A_Risc-V_Processor/source/topCPU_tb_konata.trace",
        help="Native Konata trace output file",
    )
    parser.add_argument(
        "--skip-cycles",
        type=int,
        default=0,
        help="Ignore snapshots up to and including this cycle number.",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    if not input_path.exists():
        parser.error(f"Input dump file does not exist: {input_path}")

    issued = convert_dump_to_kanata(input_path, output_path, skip_cycles=args.skip_cycles)
    report = validate_kanata_output(output_path)

    print(
        f"Wrote native Konata trace to {output_path} "
        f"(issued={issued}, retired={report['retired']}, missing_retire={len(report['missing_retire'])})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
