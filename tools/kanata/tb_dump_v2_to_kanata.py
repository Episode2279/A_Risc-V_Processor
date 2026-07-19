#!/usr/bin/env python3
"""Convert this core's TB_PIPE_DUMP_V2 stream to a Kanata 0004 trace.

The organization follows RSD's KanataConverter: a source parser produces
dynamic-operation events, while a generator owns Kanata sid/rid allocation and
the textual protocol.  Hardware ROB tags are deliberately *not* used as Kanata
instruction IDs because they wrap; each dispatch receives a monotonic gid.

Pipeline mapping used by this core:

    dispatch -> Rn -> Iq -> Ex0/Ex1/ExF or LS -> Wb0/Wb1 -> Rob -> Cm0/Cm1

The V2 dump has an exact ROB tag on every back-end event.  Branch recovery
flushes only younger active operations, while a trap/global flush removes the
whole speculative window.  Every stage has an explicit S/E pair.  Like an op
waiting in IQ, an incomplete memory op remains in one continuous ``LS`` stage
until COMPLETE; wait cycles do not create synthetic sub-stages.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, Iterator, List, Optional, TextIO, Tuple

from tb_dump_to_konata_legacy import riscv_disasm_hex


class DumpFormatError(RuntimeError):
    """Raised when a V2 dump is malformed or internally inconsistent."""


def parse_int(text: str) -> int:
    return int(text, 16) if text.lower().startswith("0x") else int(text, 10)


def parse_record(line: str) -> Tuple[str, Dict[str, str]]:
    words = line.strip().split()
    if not words:
        return "", {}
    values: Dict[str, str] = {}
    for word in words[1:]:
        if "=" in word:
            key, value = word.split("=", 1)
            values[key] = value
    return words[0], values


@dataclass
class Snapshot:
    cycle: int
    global_flush: bool
    recover: bool
    recover_tag: int
    records: Dict[str, Dict[str, str]] = field(default_factory=dict)

    def record(self, name: str) -> Dict[str, str]:
        return self.records.get(name, {})


class V2DumpParser:
    """Streaming parser for snapshots produced by sim_main/topCPU_tb."""

    RECORD_PREFIXES = ("DISPATCH", "ISSUE", "COMPLETE", "COMMIT")

    def __init__(self, path: Path):
        self.path = path

    def snapshots(self) -> Iterator[Snapshot]:
        current: Optional[Snapshot] = None
        saw_header = False

        with self.path.open("r", encoding="utf-8") as source:
            for line_number, raw_line in enumerate(source, 1):
                line = raw_line.strip()
                if not line or line.startswith("META"):
                    continue
                if line == "TB_PIPE_DUMP_V2":
                    saw_header = True
                    continue
                if line.startswith("TB_PIPE_DUMP_"):
                    raise DumpFormatError(
                        f"{self.path}:{line_number}: expected TB_PIPE_DUMP_V2"
                    )
                if not saw_header:
                    raise DumpFormatError(
                        f"{self.path}:{line_number}: missing TB_PIPE_DUMP_V2 header"
                    )

                record_type, values = parse_record(line)
                if record_type == "SNAPSHOT":
                    if current is not None:
                        raise DumpFormatError(
                            f"{self.path}:{line_number}: nested SNAPSHOT"
                        )
                    try:
                        current = Snapshot(
                            cycle=parse_int(values["cycle"]),
                            global_flush=bool(parse_int(values.get("globalFlush", "0"))),
                            recover=bool(parse_int(values.get("recover", "0"))),
                            recover_tag=parse_int(values.get("recoverTag", "0")),
                        )
                    except (KeyError, ValueError) as error:
                        raise DumpFormatError(
                            f"{self.path}:{line_number}: malformed SNAPSHOT: {error}"
                        ) from error
                    continue

                if record_type == "ENDSNAPSHOT":
                    if current is None:
                        raise DumpFormatError(
                            f"{self.path}:{line_number}: ENDSNAPSHOT without SNAPSHOT"
                        )
                    yield current
                    current = None
                    continue

                if current is not None and record_type.startswith(self.RECORD_PREFIXES):
                    current.records[record_type] = values

        if not saw_header:
            raise DumpFormatError(f"{self.path}: missing TB_PIPE_DUMP_V2 header")
        if current is not None:
            raise DumpFormatError(f"{self.path}: unterminated final SNAPSHOT")


class KanataGenerator:
    """Small Kanata 0004 writer modeled after RSD's KanataGenerator."""

    HEADER = "Kanata\t0004\n"
    INITIAL_CYCLE = -1
    DEFAULT_LANE = 0

    def __init__(self, output: TextIO):
        self.output = output
        self.current_cycle = self.INITIAL_CYCLE
        self.next_sid = 0
        self.next_rid = 0
        self.sid_by_gid: Dict[int, int] = {}
        self.output.write(self.HEADER)
        self.output.write(f"C=\t{self.INITIAL_CYCLE}\n")
        self.output.write(
            "// RSD-style event conversion; gid is monotonic and ROB tags may wrap.\n"
        )
        self.output.write(
            "// Stages: Rn -> Iq -> Ex* or LS -> Wb* -> Rob -> Cm*.\n"
        )
        self.output.write("// Multi-cycle LSU waits remain in one continuous LS stage.\n")

    def cycle(self, cycle: int) -> None:
        if cycle < self.current_cycle:
            raise DumpFormatError(
                f"Kanata cycle moved backwards: {self.current_cycle} -> {cycle}"
            )
        if cycle > self.current_cycle:
            self.output.write(f"C\t{cycle - self.current_cycle}\n")
            self.current_cycle = cycle

    def initialize(self, gid: int, abstract: str, detail: str) -> None:
        if gid in self.sid_by_gid:
            raise DumpFormatError(f"gid {gid} initialized twice")
        sid = self.next_sid
        self.next_sid += 1
        self.sid_by_gid[gid] = sid
        self.output.write(f"I\t{sid}\t{gid}\t0\n")
        self.label(gid, 0, abstract)
        self.label(gid, 1, detail)

    def label(self, gid: int, label_type: int, text: str) -> None:
        self.output.write(f"L\t{self.sid(gid)}\t{label_type}\t{text}\n")

    def stage_begin(self, gid: int, stage: str) -> None:
        self.output.write(f"S\t{self.sid(gid)}\t{self.DEFAULT_LANE}\t{stage}\n")

    def stage_end(self, gid: int, stage: str) -> None:
        self.output.write(f"E\t{self.sid(gid)}\t{self.DEFAULT_LANE}\t{stage}\n")

    def retire(self, gid: int) -> None:
        sid = self.sid(gid)
        self.output.write(f"R\t{sid}\t{self.next_rid}\t0\n")
        self.next_rid += 1
        del self.sid_by_gid[gid]

    def flush(self, gid: int) -> None:
        sid = self.sid(gid)
        self.output.write(f"R\t{sid}\t0\t1\n")
        del self.sid_by_gid[gid]

    def comment(self, text: str) -> None:
        self.output.write(f"// {text}\n")

    def sid(self, gid: int) -> int:
        try:
            return self.sid_by_gid[gid]
        except KeyError as error:
            raise DumpFormatError(f"unknown gid {gid}") from error


@dataclass
class DynamicOp:
    gid: int
    rob_tag: int
    pc: int
    insn: int
    fu: int
    stage: Optional[str] = None


@dataclass
class ScheduledTransition:
    gid: int
    expected_stage: str
    next_stage: Optional[str]
    retire: bool = False


@dataclass
class ConversionStats:
    dispatched: int = 0
    issued: int = 0
    completed: int = 0
    committed: int = 0
    flushed: int = 0
    recoveries: int = 0
    global_flushes: int = 0
    orphan_issues: int = 0
    orphan_completions: int = 0
    orphan_commits: int = 0
    inactive_recoveries: int = 0
    tag_reuse_errors: int = 0

    def error_count(self) -> int:
        return (
            self.orphan_issues
            + self.orphan_completions
            + self.orphan_commits
            + self.inactive_recoveries
            + self.tag_reuse_errors
        )


FU_NAMES = {0: "int", 1: "branch", 2: "memory", 3: "csr"}


class OoOKanataConverter:
    """Translate V2 ROB-tagged events into RSD-style Kanata lifetimes."""

    def __init__(self, generator: KanataGenerator):
        self.generator = generator
        self.stats = ConversionStats()
        self.next_gid = 0
        self.ops_by_gid: Dict[int, DynamicOp] = {}
        self.active_by_tag: Dict[int, DynamicOp] = {}
        self.active_order: List[DynamicOp] = []
        self.scheduled: Dict[int, List[ScheduledTransition]] = defaultdict(list)
        self.last_cycle = -1

    @staticmethod
    def valid(record: Dict[str, str]) -> bool:
        return bool(record) and bool(parse_int(record.get("valid", "0")))

    def transition(self, op: DynamicOp, next_stage: str) -> None:
        if op.stage == next_stage:
            return
        if op.stage is not None:
            self.generator.stage_end(op.gid, op.stage)
        self.generator.stage_begin(op.gid, next_stage)
        op.stage = next_stage

    def schedule_stage(
        self,
        cycle: int,
        op: DynamicOp,
        expected_stage: str,
        next_stage: Optional[str],
        *,
        retire: bool = False,
    ) -> None:
        self.scheduled[cycle].append(
            ScheduledTransition(op.gid, expected_stage, next_stage, retire)
        )

    def apply_scheduled(self, cycle: int) -> None:
        for event in self.scheduled.pop(cycle, []):
            op = self.ops_by_gid.get(event.gid)
            if op is None or op.stage != event.expected_stage:
                continue
            if op.stage is not None:
                self.generator.stage_end(op.gid, op.stage)
                op.stage = None
            if event.next_stage is not None:
                self.generator.stage_begin(op.gid, event.next_stage)
                op.stage = event.next_stage
            if event.retire:
                self.generator.retire(op.gid)
                del self.ops_by_gid[op.gid]

    def lookup(self, record: Dict[str, str], kind: str) -> Optional[DynamicOp]:
        tag = parse_int(record["tag"])
        op = self.active_by_tag.get(tag)
        if op is None:
            if kind == "issue":
                self.stats.orphan_issues += 1
            elif kind == "complete":
                self.stats.orphan_completions += 1
            else:
                self.stats.orphan_commits += 1
            self.generator.comment(f"orphan {kind} rob={tag}")
        return op

    def remove_from_active(self, op: DynamicOp) -> None:
        if self.active_by_tag.get(op.rob_tag) is op:
            del self.active_by_tag[op.rob_tag]
        if op in self.active_order:
            self.active_order.remove(op)

    def flush_ops(self, ops: Iterable[DynamicOp]) -> None:
        for op in list(ops):
            if op.stage is not None:
                self.generator.stage_end(op.gid, op.stage)
                op.stage = None
            self.generator.flush(op.gid)
            self.remove_from_active(op)
            self.ops_by_gid.pop(op.gid, None)
            self.stats.flushed += 1

    def process_issue(self, snapshot: Snapshot) -> None:
        for record_name, execution_port in (
            ("ISSUE0", "Ex0"),
            ("ISSUE1", "Ex1"),
            ("ISSUEF", "ExF"),
        ):
            record = snapshot.record(record_name)
            if not self.valid(record):
                continue
            op = self.lookup(record, "issue")
            if op is not None:
                # Loads and Stores enter one continuous LS stage.  As with an
                # IQ wait, no event is emitted again until the op completes.
                stage = "LS" if op.fu == 2 else execution_port
                self.transition(op, stage)
                self.generator.label(
                    op.gid,
                    2,
                    f"rob={op.rob_tag} port={execution_port} unit={stage}",
                )
                self.stats.issued += 1

    def process_completion(self, snapshot: Snapshot) -> None:
        for lane, record_name in enumerate(("COMPLETE0", "COMPLETE1")):
            record = snapshot.record(record_name)
            if not self.valid(record):
                continue
            op = self.lookup(record, "complete")
            if op is not None:
                stage = f"Wb{lane}"
                self.transition(op, stage)
                self.generator.label(
                    op.gid,
                    2,
                    f"rob={op.rob_tag} value={record.get('value', '0x00000000')} "
                    f"exception={record.get('exception', '0')}",
                )
                self.schedule_stage(snapshot.cycle + 1, op, stage, "Rob")
                self.stats.completed += 1

    def process_recovery(self, snapshot: Snapshot) -> None:
        if snapshot.global_flush:
            self.stats.global_flushes += 1
            self.generator.comment("global ROB flush")
            self.flush_ops(self.active_order)
            return
        if not snapshot.recover:
            return

        self.stats.recoveries += 1
        branch = self.active_by_tag.get(snapshot.recover_tag)
        if branch is None:
            self.stats.inactive_recoveries += 1
            self.generator.comment(f"recovery tag not active rob={snapshot.recover_tag}")
            return
        branch_index = self.active_order.index(branch)
        self.generator.comment(f"branch recovery rob={snapshot.recover_tag}")
        self.flush_ops(self.active_order[branch_index + 1 :])

    def process_commit(self, snapshot: Snapshot) -> None:
        for lane, record_name in enumerate(("COMMIT0", "COMMIT1")):
            record = snapshot.record(record_name)
            if not self.valid(record):
                continue
            op = self.lookup(record, "commit")
            if op is None:
                continue
            stage = f"Cm{lane}"
            self.transition(op, stage)
            self.generator.label(
                op.gid,
                2,
                f"rob={op.rob_tag} rd={record.get('rd', '0')} "
                f"data={record.get('data', '0x00000000')}",
            )
            self.remove_from_active(op)
            self.schedule_stage(
                snapshot.cycle + 1,
                op,
                stage,
                None,
                retire=True,
            )
            self.stats.committed += 1

    def process_dispatch(self, snapshot: Snapshot) -> None:
        for lane, record_name in enumerate(("DISPATCH0", "DISPATCH1")):
            record = snapshot.record(record_name)
            if not self.valid(record):
                continue
            tag = parse_int(record["tag"])
            if tag in self.active_by_tag:
                self.stats.tag_reuse_errors += 1
                self.generator.comment(f"ROB tag reused while active rob={tag}")
                self.flush_ops([self.active_by_tag[tag]])

            pc = parse_int(record["pc"])
            insn = parse_int(record["insn"])
            fu = parse_int(record.get("fu", "0"))
            gid = self.next_gid
            self.next_gid += 1
            op = DynamicOp(gid=gid, rob_tag=tag, pc=pc, insn=insn, fu=fu)
            self.ops_by_gid[gid] = op
            self.active_by_tag[tag] = op
            self.active_order.append(op)

            asm = str(riscv_disasm_hex(insn, abi_names=False))
            self.generator.initialize(
                gid,
                f"0x{pc:08x}: {asm}",
                f"gid={gid} rob={tag} fu={FU_NAMES.get(fu, str(fu))} "
                f"pc=0x{pc:08x} insn=0x{insn:08x}",
            )
            stage = f"Rn{lane}"
            self.transition(op, stage)
            self.schedule_stage(snapshot.cycle + 1, op, stage, "Iq")
            self.stats.dispatched += 1

    def process_snapshot(self, snapshot: Snapshot) -> None:
        if snapshot.cycle <= self.last_cycle:
            raise DumpFormatError(
                f"snapshot cycle is not increasing: {self.last_cycle} -> {snapshot.cycle}"
            )
        self.last_cycle = snapshot.cycle
        self.generator.cycle(snapshot.cycle)
        self.generator.comment(f"cycle {snapshot.cycle}")
        self.apply_scheduled(snapshot.cycle)

        # Older operations are observed before prospective dispatch allocations.
        self.process_issue(snapshot)
        self.process_completion(snapshot)
        self.process_recovery(snapshot)
        self.process_commit(snapshot)
        self.process_dispatch(snapshot)

    def finish(self) -> None:
        final_cycle = self.last_cycle + 1
        self.generator.cycle(final_cycle)
        self.apply_scheduled(final_cycle)
        # A truncated simulation may leave live ROB entries.  Close them as
        # flushed so every Kanata I command has exactly one R command.
        if self.active_order:
            self.generator.comment("end-of-trace: unresolved ROB entries")
            self.flush_ops(self.active_order)
        # Defensive cleanup for committed ops whose scheduled retirement lies
        # beyond the final sampled snapshot.
        for cycle in sorted(self.scheduled):
            self.generator.cycle(cycle)
            self.apply_scheduled(cycle)


def validate_kanata(path: Path) -> Dict[str, int]:
    initialized: set[int] = set()
    retired: set[int] = set()
    stage_begin = 0
    stage_end = 0
    commits = 0
    flushes = 0

    with path.open("r", encoding="utf-8") as trace:
        for raw_line in trace:
            line = raw_line.rstrip("\n")
            if line.startswith("I\t"):
                initialized.add(int(line.split("\t")[1]))
            elif line.startswith("S\t"):
                stage_begin += 1
            elif line.startswith("E\t"):
                stage_end += 1
            elif line.startswith("R\t"):
                fields = line.split("\t")
                retired.add(int(fields[1]))
                if fields[3] == "1":
                    flushes += 1
                else:
                    commits += 1

    return {
        "initialized": len(initialized),
        "retired": len(retired),
        "missing_retire": len(initialized - retired),
        "extra_retire": len(retired - initialized),
        "stage_begin": stage_begin,
        "stage_end": stage_end,
        "commits": commits,
        "flushes": flushes,
    }


def convert(input_path: Path, output_path: Path) -> Tuple[ConversionStats, Dict[str, int]]:
    parser = V2DumpParser(input_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="\n") as output:
        generator = KanataGenerator(output)
        converter = OoOKanataConverter(generator)
        for snapshot in parser.snapshots():
            converter.process_snapshot(snapshot)
        converter.finish()
    return converter.stats, validate_kanata(output_path)


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Convert TB_PIPE_DUMP_V2 into an RSD-style Kanata 0004 trace."
    )
    parser.add_argument(
        "input",
        nargs="?",
        default="build/traces/topCPU_tb_output.txt",
    )
    parser.add_argument(
        "output",
        nargs="?",
        default="build/traces/topCPU_tb_kanata.trace",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="return a failure status if an orphan/tag-reuse/lifecycle error is found",
    )
    return parser


def main() -> int:
    args = build_argument_parser().parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output)
    if not input_path.exists():
        raise SystemExit(f"input dump does not exist: {input_path}")

    try:
        stats, validation = convert(input_path, output_path)
    except (DumpFormatError, KeyError, ValueError) as error:
        raise SystemExit(f"conversion failed: {error}") from error

    print(
        f"Wrote Kanata trace to {output_path} "
        f"(dispatch={stats.dispatched}, issue={stats.issued}, "
        f"complete={stats.completed}, commit={stats.committed}, "
        f"flush={stats.flushed}, recovery={stats.recoveries}, "
        f"errors={stats.error_count()}, "
        f"missing_retire={validation['missing_retire']}, "
        f"stage_S={validation['stage_begin']}, "
        f"stage_E={validation['stage_end']})"
    )

    lifecycle_errors = validation["missing_retire"] + validation["extra_retire"]
    if args.strict and (stats.error_count() or lifecycle_errors):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
