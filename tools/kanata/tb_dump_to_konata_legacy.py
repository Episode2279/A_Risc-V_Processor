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

        if opcode == 0b0001111:
            if funct3 == 0b000:
                return "fence"
            if funct3 == 0b001:
                return "fence.i"
            return f".word 0x{inst:08x}"

        if opcode == 0b1110011:
            imm12 = bits(inst, 31, 20)
            if funct3 == 0 and rd == 0 and rs1 == 0:
                if imm12 == 0:
                    return "ecall"
                if imm12 == 1:
                    return "ebreak"
                if imm12 == 0x302:
                    return "mret"
                if imm12 == 0x105:
                    return "wfi"
            csr_names = {
                0x300: "mstatus",
                0x304: "mie",
                0x305: "mtvec",
                0x340: "mscratch",
                0x341: "mepc",
                0x342: "mcause",
                0x343: "mtval",
                0x344: "mip",
                0xB00: "mcycle",
                0xB02: "minstret",
                0xC00: "cycle",
                0xC02: "instret",
            }
            csr = csr_names.get(imm12, f"0x{imm12:03x}")
            csr_ops = {
                0b001: "csrrw",
                0b010: "csrrs",
                0b011: "csrrc",
                0b101: "csrrwi",
                0b110: "csrrsi",
                0b111: "csrrci",
            }
            mnemonic = csr_ops.get(funct3)
            if mnemonic is not None:
                source = str(rs1) if funct3 & 0b100 else rname(rs1)
                return f"{mnemonic} {rname(rd)}, {csr}, {source}"
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
    check_pc: int
    check: int
    check_data: int
    stages: Dict[str, Dict[str, int | str]] = field(default_factory=dict)
    format_version: int = 1
    global_flush: int = 0
    recover: int = 0
    recover_tag: int = 0


@dataclass
class PipeEntry:
    iid: str
    token: tuple[int, int]
    pc: int
    insn: int
    asm: str
    stage: Optional[str]
    dispatch_cycle: Optional[int] = None
    closed: bool = False
    rob_tag: Optional[int] = None
    fu: Optional[int] = None


@dataclass
class ConversionStats:
    issued: int = 0
    dispatched: int = 0
    committed: int = 0
    flushed: int = 0
    orphan_commits: int = 0
    orphan_issues: int = 0
    orphan_completions: int = 0


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
    format_version = 1

    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("META"):
                continue
            if line == "TB_PIPE_DUMP_V1":
                format_version = 1
                continue
            if line == "TB_PIPE_DUMP_V2":
                format_version = 2
                continue

            record_type, values = parse_kv_line(line)

            if record_type == "SNAPSHOT":
                current = Snapshot(
                    cycle=parse_int(values["cycle"]),
                    time=parse_int(values["time"]),
                    rst=parse_int(values["rst"]),
                    wr_enable=parse_int(values.get("wrEnable", "1")),
                    stall=parse_int(values["stall"]),
                    flush=parse_int(values.get("frontendFlush", values.get("flush", "0"))),
                    jump_enable=parse_int(values.get("jumpEnable", "0")),
                    issue0=parse_int(values.get("issue0", "0")),
                    issue1=parse_int(values.get("issue1", "0")),
                    to_host=parse_int(values["toHost"]),
                    uart_valid=parse_int(values["uartValid"]),
                    uart_data=parse_int(values["uartData"]),
                    check_pc=parse_int(values.get("checkPC", "0")),
                    check=parse_int(values.get("check", "0")),
                    check_data=parse_int(values.get("checkData", "0")),
                    format_version=format_version,
                    global_flush=parse_int(values.get("globalFlush", "0")),
                    recover=parse_int(values.get("recover", "0")),
                    recover_tag=parse_int(values.get("recoverTag", "0")),
                )
                continue

            if current is None:
                continue

            if record_type.startswith((
                "IF", "ID", "EX", "MEM", "WB", "DISPATCH", "ISSUE",
                "COMPLETE", "COMMIT",
            )):
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


def write_header(out: TextIO, format_version: int = 1) -> None:
    out.write("Kanata\t0004\n")
    out.write("C=\t-1\n")
    if format_version >= 2:
        out.write("// OoO event model: D/RN -> IQ/ROB -> EX* -> WB* -> CM*\n")
        out.write("// Dynamic instructions are correlated exactly by ROB tag.\n")
    else:
        out.write("// OoO stage model: F1 -> D/RN -> IQ/ROB -> CM0/CM1\n")
        out.write("// V1 dumps do not expose issued ROB tags; EX timing is intentionally not inferred.\n")


def disasm_cached(insn: int, cache: Dict[int, str]) -> str:
    if insn not in cache:
        cache[insn] = str(riscv_disasm_hex(insn, abi_names=False))
    return cache[insn]


def is_real_insn(insn: int) -> bool:
    return insn != 0


def entry_line(entry: PipeEntry) -> str:
    return f"PC=0x{entry.pc:08x} | 0x{entry.insn:08x} | {entry.asm}"


def entry_detail(entry: PipeEntry) -> str:
    detail = f"pc=0x{entry.pc:08x}, insn=0x{entry.insn:08x}"
    if entry.rob_tag is not None:
        detail += f", rob={entry.rob_tag}"
    if entry.fu is not None:
        detail += f", fu={entry.fu}"
    return f"({detail})"


FRONTEND_SLOTS = ("IF0", "IF1", "ID0", "ID1")
FRONTEND_STAGE = {
    "IF0": "F1",
    "IF1": "F1",
    "ID0": "D/RN",
    "ID1": "D/RN",
}


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


def unique_entries(entries: Iterable[PipeEntry]) -> List[PipeEntry]:
    seen: set[str] = set()
    result: List[PipeEntry] = []
    for entry in entries:
        if entry.iid not in seen:
            seen.add(entry.iid)
            result.append(entry)
    return result


def emit_stage(entry: PipeEntry, stage: str) -> List[str]:
    if entry.stage == stage:
        return []
    entry.stage = stage
    return [f"S\t{entry.iid}\t0\t{stage}\n"]


def close_entry(
    entry: PipeEntry,
    *,
    flushed: bool,
    state: Dict[str, int],
    stats: ConversionStats,
    commit_lane: Optional[int] = None,
) -> List[str]:
    if entry.closed:
        return []

    out: List[str] = []
    if flushed:
        out.extend(emit_stage(entry, "FL"))
        out.append(f"R\t{entry.iid}\t0\t1\n")
        stats.flushed += 1
    else:
        stage = f"CM{commit_lane}" if commit_lane is not None else "CM"
        out.extend(emit_stage(entry, stage))
        out.append(f"R\t{entry.iid}\t{state['next_rid']}\t0\n")
        state["next_rid"] += 1
        stats.committed += 1
    entry.closed = True
    return out


def advance_frontend(
    prev_slots: Dict[str, PipeEntry],
    prev_snapshot: Snapshot,
) -> tuple[Dict[str, PipeEntry], List[PipeEntry], List[PipeEntry]]:
    """Apply the previous cycle's rename/dispatch handshake.

    ``issue0``/``issue1`` are legacy dump field names. In the current RTL they
    are ``dispatchAccept[0:1]`` and must not be interpreted as EX-lane issue.
    """

    all_previous = unique_entries(prev_slots.values())
    if prev_snapshot.flush:
        return {}, [], all_previous

    decode_queue = [prev_slots[name] for name in ("ID0", "ID1") if name in prev_slots]
    fetch_queue = [prev_slots[name] for name in ("IF0", "IF1") if name in prev_slots]
    dispatched: List[PipeEntry] = []

    if prev_snapshot.issue0 and decode_queue:
        dispatched.append(decode_queue.pop(0))
    if prev_snapshot.issue1 and decode_queue:
        dispatched.append(decode_queue.pop(0))

    while len(decode_queue) < 2 and fetch_queue:
        decode_queue.append(fetch_queue.pop(0))

    expected: Dict[str, PipeEntry] = {}
    for name, entry in zip(("ID0", "ID1"), decode_queue[:2]):
        expected[name] = entry
    for name, entry in zip(("IF0", "IF1"), fetch_queue[:2]):
        expected[name] = entry

    kept_ids = {entry.iid for entry in expected.values()}
    dispatched_ids = {entry.iid for entry in dispatched}
    dropped = [
        entry
        for entry in all_previous
        if entry.iid not in kept_ids and entry.iid not in dispatched_ids
    ]
    return expected, dispatched, dropped


def reconcile_frontend(
    expected: Dict[str, PipeEntry],
    snapshot: Snapshot,
    state: Dict[str, int],
    cache: Dict[int, str],
) -> tuple[Dict[str, PipeEntry], List[PipeEntry], List[PipeEntry]]:
    current_slots: Dict[str, PipeEntry] = {}
    created: List[PipeEntry] = []
    unused = unique_entries(expected.values())

    # Reconcile slot movement against the actual F1 and decode-window contents.
    # ID slots are handled first because they are the oldest front-end entries.
    for slot_name in ("ID0", "ID1", "IF0", "IF1"):
        token = stage_token(snapshot, slot_name)
        if token is None:
            continue

        assigned = expected.get(slot_name)
        if assigned is not None and assigned in unused and assigned.token == token:
            unused.remove(assigned)
        else:
            assigned = next((entry for entry in unused if entry.token == token), None)
            if assigned is not None:
                unused.remove(assigned)

        if assigned is None:
            assigned = new_entry(token, slot_name, state, cache)
            created.append(assigned)
        current_slots[slot_name] = assigned

    return current_slots, created, unused


def commit_pcs(snapshot: Snapshot) -> List[tuple[int, int]]:
    """Return visible commit lane/PC pairs from the compatibility WB view."""

    commits: List[tuple[int, int]] = []
    for lane, name in enumerate(("WB0", "WB1")):
        stage = stage_data(snapshot, name)
        if not stage:
            continue
        if "valid" in stage:
            valid = bool(int(stage["valid"]))
        else:
            pc = int(stage.get("pc", 0))
            # The V1 dump predates explicit commit-valid fields. Non-zero PCs
            # are unambiguous. PC zero is accepted only with a visible write,
            # which covers the reset-vector instruction in current images.
            valid = pc != 0 or bool(int(stage.get("regWrite", 0)))
        if valid:
            commits.append((lane, int(stage.get("pc", 0))))
    return commits


def retire_by_pc(
    window: List[PipeEntry],
    pc: int,
    lane: int,
    state: Dict[str, int],
    stats: ConversionStats,
) -> List[str]:
    out: List[str] = []
    match_index = next(
        (index for index, entry in enumerate(window) if not entry.closed and entry.pc == pc),
        None,
    )
    if match_index is None:
        stats.orphan_commits += 1
        return out

    # Retirement is in order. If the next observed committed PC skips entries,
    # those entries are wrong-path state that the V1 dump cannot identify at
    # execute-time because it exports neither ROB tags nor branch resolve PCs.
    for stale in window[:match_index]:
        out.extend(close_entry(stale, flushed=True, state=state, stats=stats))
    del window[:match_index]

    entry = window.pop(0)
    out.extend(
        close_entry(
            entry,
            flushed=False,
            state=state,
            stats=stats,
            commit_lane=lane,
        )
    )
    return out


def convert_v2_snapshots(
    snapshots: List[Snapshot],
    output_path: Path,
) -> ConversionStats:
    """Convert an event-oriented V2 dump using ROB tags as exact identities."""

    cache: Dict[int, str] = {}
    active_by_tag: Dict[int, PipeEntry] = {}
    active_order: List[PipeEntry] = []
    state: Dict[str, int] = {
        "next_iid": 1,
        "next_rid": 0,
        "current_cycle": -1,
    }
    stats = ConversionStats()

    def emit_lines(out: TextIO, lines: Iterable[str]) -> None:
        for emitted in lines:
            out.write(emitted)

    def remove_active(entry: PipeEntry) -> None:
        if entry.rob_tag is not None and active_by_tag.get(entry.rob_tag) is entry:
            del active_by_tag[entry.rob_tag]
        if entry in active_order:
            active_order.remove(entry)

    def flush_entries(out: TextIO, entries: Iterable[PipeEntry]) -> None:
        for entry in list(entries):
            emit_lines(out, close_entry(entry, flushed=True, state=state, stats=stats))
            remove_active(entry)

    with output_path.open("w", encoding="utf-8", newline="\n") as out:
        write_header(out, format_version=2)
        for snapshot in snapshots:
            cycle_delta = snapshot.cycle - state["current_cycle"]
            if cycle_delta > 0:
                out.write(f"C\t{cycle_delta}\n")
            state["current_cycle"] = snapshot.cycle
            out.write(f"// cycle {snapshot.cycle}\n")

            # Issue is an IQ handshake, not merely a selected candidate.
            for record_name, stage_name in (
                ("ISSUE0", "EX0"),
                ("ISSUE1", "EX1"),
                ("ISSUEF", "EXF"),
            ):
                record = stage_data(snapshot, record_name)
                if not record or not int(record.get("valid", 0)):
                    continue
                tag = int(record["tag"])
                entry = active_by_tag.get(tag)
                if entry is None:
                    stats.orphan_issues += 1
                    out.write(f"// orphan {record_name} rob={tag}\n")
                    continue
                emit_lines(out, emit_stage(entry, stage_name))

            # Completion is the ROB/PRF writeback event.  Loads may spend many
            # cycles between EX and this point while the D-cache services them.
            for lane, record_name in enumerate(("COMPLETE0", "COMPLETE1")):
                record = stage_data(snapshot, record_name)
                if not record or not int(record.get("valid", 0)):
                    continue
                tag = int(record["tag"])
                entry = active_by_tag.get(tag)
                if entry is None:
                    stats.orphan_completions += 1
                    out.write(f"// orphan {record_name} rob={tag}\n")
                    continue
                emit_lines(out, emit_stage(entry, f"WB{lane}"))

            # A trap flush removes the complete speculative window.  Branch
            # recovery retains the resolving branch and discards only younger
            # ROB entries, using dispatch order to disambiguate tag wraparound.
            if snapshot.global_flush:
                out.write("// global ROB flush\n")
                flush_entries(out, list(active_order))
            elif snapshot.recover:
                recover_entry = active_by_tag.get(snapshot.recover_tag)
                if recover_entry is not None:
                    recover_index = active_order.index(recover_entry)
                    out.write(f"// branch recovery rob={snapshot.recover_tag}\n")
                    flush_entries(out, active_order[recover_index + 1 :])
                else:
                    out.write(f"// recovery tag not active rob={snapshot.recover_tag}\n")

            # Retirement is exact even for repeated PCs because COMMIT carries
            # the same ROB tag allocated at dispatch.
            for lane, record_name in enumerate(("COMMIT0", "COMMIT1")):
                record = stage_data(snapshot, record_name)
                if not record or not int(record.get("valid", 0)):
                    continue
                tag = int(record["tag"])
                entry = active_by_tag.get(tag)
                if entry is None:
                    stats.orphan_commits += 1
                    out.write(f"// orphan {record_name} rob={tag}\n")
                    continue
                emit_lines(
                    out,
                    close_entry(
                        entry,
                        flushed=False,
                        state=state,
                        stats=stats,
                        commit_lane=lane,
                    ),
                )
                remove_active(entry)

            # Dispatch records create the dynamic instruction.  Front-end IF/ID
            # snapshots remain in the text dump for inspection, while the
            # Konata lifetime starts where an unambiguous ROB identity exists.
            for lane, record_name in enumerate(("DISPATCH0", "DISPATCH1")):
                record = stage_data(snapshot, record_name)
                if not record or not int(record.get("valid", 0)):
                    continue
                tag = int(record["tag"])
                stale = active_by_tag.get(tag)
                if stale is not None:
                    out.write(f"// ROB tag reused while active rob={tag}\n")
                    flush_entries(out, [stale])
                pc = int(record["pc"])
                insn = int(record["insn"])
                fu = int(record.get("fu", 0))
                iid = str(state["next_iid"])
                state["next_iid"] += 1
                entry = PipeEntry(
                    iid=iid,
                    token=(pc, insn),
                    pc=pc,
                    insn=insn,
                    asm=disasm_cached(insn, cache),
                    stage=None,
                    dispatch_cycle=snapshot.cycle,
                    rob_tag=tag,
                    fu=fu,
                )
                active_by_tag[tag] = entry
                active_order.append(entry)
                stats.issued += 1
                stats.dispatched += 1
                emit_lines(out, emit_new_entry(entry))
                emit_lines(out, emit_stage(entry, f"D/RN{lane}"))
                emit_lines(out, emit_stage(entry, "IQ/ROB"))

            out.write("\n\n")

        if active_order:
            out.write("// end-of-trace: unresolved ROB entries\n")
            flush_entries(out, list(active_order))

    return stats


def convert_dump_to_kanata(
    input_path: Path,
    output_path: Path,
    *,
    skip_cycles: int = 0,
) -> ConversionStats:
    snapshots = load_dump(input_path)
    if skip_cycles:
        snapshots = [snapshot for snapshot in snapshots if snapshot.cycle > skip_cycles]
    if snapshots and snapshots[0].format_version >= 2:
        return convert_v2_snapshots(snapshots, output_path)

    cache: Dict[int, str] = {}
    frontend_slots: Dict[str, PipeEntry] = {}
    ooo_window: List[PipeEntry] = []
    prev_snapshot: Optional[Snapshot] = None
    state: Dict[str, int] = {
        "next_iid": 1,
        "next_rid": 0,
        "current_cycle": -1,
    }
    stats = ConversionStats()

    with output_path.open("w", encoding="utf-8", newline="\n") as out:
        write_header(out)
        for snapshot in snapshots:
            cycle_delta = snapshot.cycle - int(state["current_cycle"])
            if cycle_delta > 0:
                out.write(f"C\t{cycle_delta}\n")
            state["current_cycle"] = snapshot.cycle

            out.write(f"// cycle {snapshot.cycle}\n")

            expected: Dict[str, PipeEntry] = {}
            if prev_snapshot is not None:
                expected, dispatched, dropped = advance_frontend(frontend_slots, prev_snapshot)
                for entry in dropped:
                    for line in close_entry(entry, flushed=True, state=state, stats=stats):
                        out.write(line)
                for entry in dispatched:
                    if entry.closed:
                        continue
                    entry.dispatch_cycle = snapshot.cycle
                    ooo_window.append(entry)
                    stats.dispatched += 1
                    for line in emit_stage(entry, "IQ/ROB"):
                        out.write(line)

            frontend_slots, created, displaced = reconcile_frontend(
                expected, snapshot, state, cache
            )
            for entry in displaced:
                for line in close_entry(entry, flushed=True, state=state, stats=stats):
                    out.write(line)
            for entry in created:
                stats.issued += 1
                for line in emit_new_entry(entry):
                    out.write(line)

            for slot_name in FRONTEND_SLOTS:
                entry = frontend_slots.get(slot_name)
                if entry is not None:
                    for line in emit_stage(entry, FRONTEND_STAGE[slot_name]):
                        out.write(line)

            for lane, pc in commit_pcs(snapshot):
                for line in retire_by_pc(ooo_window, pc, lane, state, stats):
                    out.write(line)

            out.write("\n\n")

            prev_snapshot = snapshot

        remaining = unique_entries([*frontend_slots.values(), *ooo_window])
        if remaining:
            out.write("// end-of-trace: unresolved/front-end entries\n")
            for entry in remaining:
                for line in close_entry(entry, flushed=True, state=state, stats=stats):
                    out.write(line)

    return stats


def validate_kanata_output(path: Path) -> Dict[str, object]:
    issued: Dict[str, bool] = {}
    retired: Dict[str, bool] = {}
    stages: Dict[str, List[str]] = {}
    committed_count = 0
    flushed_count = 0

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
                if len(parts) >= 4 and parts[3] == "1":
                    flushed_count += 1
                else:
                    committed_count += 1
            elif line.startswith("S\t"):
                parts = line.split("\t")
                if len(parts) >= 4:
                    stages.setdefault(parts[1], []).append(parts[3])

    missing_retire = sorted((iid for iid in issued if iid not in retired), key=str)
    extra_retire = sorted((iid for iid in retired if iid not in issued), key=str)

    return {
        "issued": len(issued),
        "retired": len(retired),
        "committed": committed_count,
        "flushed": flushed_count,
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
        default="build/traces/topCPU_tb_output.txt",
        help="Structured dump produced by topCPU_tb.sv",
    )
    parser.add_argument(
        "output",
        nargs="?",
        default="build/traces/topCPU_tb_konata_legacy.trace",
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

    stats = convert_dump_to_kanata(input_path, output_path, skip_cycles=args.skip_cycles)
    report = validate_kanata_output(output_path)

    print(
        f"Wrote native Konata trace to {output_path} "
        f"(instructions={stats.issued}, dispatched={stats.dispatched}, "
        f"committed={stats.committed}, flushed={stats.flushed}, "
        f"orphan_commits={stats.orphan_commits}, "
        f"orphan_issues={stats.orphan_issues}, "
        f"orphan_completions={stats.orphan_completions}, "
        f"missing_retire={len(report['missing_retire'])})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
