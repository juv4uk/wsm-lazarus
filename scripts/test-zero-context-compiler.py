#!/usr/bin/env python3
"""G6.190: відтворюване вимірювання нового D5:01000 compiler context.

Це HOST тест, НЕ SENS evaluator. Очікувані T5M формує FPC генератор.
Значення oracle тут — фізичні свідки; незалежний SENS REPL не запускається.
"""
import hashlib
import json
import os
from pathlib import Path
import select
import statistics
import struct
import subprocess
import sys
import tempfile
import time


def need(condition, message):
    if not condition:
        raise AssertionError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_exact(fd, n, deadline):
    result = bytearray()
    while len(result) < n:
        remaining = deadline - time.monotonic()
        need(remaining > 0, "таймаут відповіді host-компілятора")
        ready, _, _ = select.select([fd], [], [], remaining)
        need(ready, "host-компілятор не надіслав відповідь")
        part = os.read(fd, n - len(result))
        need(part, "обірвано host-відповідь")
        result.extend(part)
    return bytes(result)


class Session:
    def __init__(self, binary, mode, directory):
        self.mode = mode
        self.error_log = open(directory / (mode + ".stderr"), "ab")
        self.launch_ns = time.perf_counter_ns()
        self.proc = subprocess.Popen(
            [str(binary), "--звичайний" if mode == "old" else "--контекст"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=self.error_log,
            bufsize=0,
        )

    def compile(self, physical):
        need(0 < len(physical) <= 65536, "потрібен фізичний кадр")
        start = time.perf_counter_ns()
        os.write(self.proc.stdin.fileno(), struct.pack("<I", len(physical)) + physical)
        hdr = read_exact(self.proc.stdout.fileno(), 5, time.monotonic() + 50)
        state, length = struct.unpack("<BI", hdr)
        need(state in (0, 1) and 0 < length <= (1 << 20), "неправильний host header")
        body = read_exact(self.proc.stdout.fileno(), length, time.monotonic() + 50)
        return state, body, time.perf_counter_ns() - start

    def close(self):
        self.proc.stdin.close()
        code = self.proc.wait(timeout=15)
        self.proc.stdout.close()
        self.error_log.close()
        need(code == 0, "некоректне завершення host сеансу %s: %d" % (self.mode, code))


def machine_proof(image, expected, folder, label):
    need(image[:4] == b"\x7fELF", "немає ELF magic")
    need(len(image) >= 120 and image[4:7] == bytes([2, 1, 1]), "не ELF64 LE")
    need(struct.unpack_from("<H", image, 16)[0] == 3, "не ET_DYN PIE")
    need(struct.unpack_from("<Q", image, 24)[0] == 120, "незвичний entry")
    need(struct.unpack_from("<Q", image, 96)[0] == len(image), "неправильна секція PT_LOAD")
    need(struct.unpack_from("<Q", image, 104)[0] == len(image), "неправильний p_memsz")
    filename = folder / (label + ".elf")
    filename.write_bytes(image)
    filename.chmod(0o700)
    proc = subprocess.run([str(filename)], capture_output=True, timeout=7, check=False)
    need(proc.returncode == 0, "ELF завершився з помилкою %s" % label)
    need(proc.stdout == expected, "машинний D1/T5M не збігається %s" % label)
    need(not proc.stderr, "ELF помилково пише в stderr")


def main():
    need(len(sys.argv) == 4, "usage: test.py CLI fixtures output.json")
    binary = Path(sys.argv[1]).resolve()
    folder = Path(sys.argv[2]).resolve()
    report = Path(sys.argv[3]).resolve()
    rows = [line.split("\t") for line in (folder / "cases.tsv").read_text().splitlines()]
    need(len(rows) == 16 and len({r[0] for r in rows}) == 16, "не 16 різних свідків")
    cases = [(label, (folder / (label + ".sens")).read_bytes(),
              (folder / (label + ".expected.sens")).read_bytes())
             for label, _ in rows]
    need(len({sha(raw) for _, raw, _ in cases}) == 16, "корпус містить дублікати")

    raw_timing = {"old": [], "new": []}
    cold = {"old": [], "new": []}
    negatives = [
        "bad-head", "bad-arity", "bad-d1", "bad-d24",
        "bad-open", "bad-two-roots", "bad-t5m", "bad-empty"
    ]
    with tempfile.TemporaryDirectory(prefix="sens-zero-wide-") as tmp:
        evidence = Path(tmp)
        # Незалежний host smoke: нульовий/неканонічний T5M не публікує
        # жодних ELF, після кожної відмови сеанс знову приймає форму.
        for mode in ("old", "new"):
            session = Session(binary, mode, evidence)
            try:
                ok, ref, _ = session.compile(cases[0][1])
                need(ok == 1, "не скомпільовано baseline")
                for name in negatives:
                    physical = (folder / (name + ".sens")).read_bytes()
                    if not physical:
                        # Host frame length=0 — термінальна помилка протоколу.
                        # Порожній T5M перевіряється окремим процесом нижче.
                        continue
                    ok, diagnostic, _ = session.compile(physical)
                    need(ok == 0 and diagnostic, "негатив не відхилено: %s %s" % (mode, name))
                    ok, recovery, _ = session.compile(cases[0][1])
                    need(ok == 1 and recovery == ref, "немає recovery після " + name)
            finally:
                session.close()
            # Порожній кадр термінальний, не перетворюємо його в
            # SENS D3:000 і не намагаємося відновитися посеред кадру.
            dead = subprocess.run(
                [str(binary), "--звичайний" if mode == "old" else "--контекст"],
                input=b"\x00\x00\x00\x00", capture_output=True, timeout=8
            )
            need(dead.returncode == 2 and not dead.stdout,
                 "порожній host кадр не відхилено")
        # 6 дзеркальних пар порядків, 16 РІЗНИХ нових програм
        # кожного persistent host process. ELF/cache reuse заборонено.
        # Прогрів — окремий процес, його числа не публікуємо.
        for mode in ("old", "new"):
            session = Session(binary, mode, evidence)
            try:
                state, value, _ = session.compile(cases[0][1])
                need(state == 1 and value.startswith(b"\x7fELF"), "невдалий прогрів")
            finally:
                session.close()

        for round_index in range(6):
            rotation = round_index * 3 % 16
            order = cases[rotation:] + cases[:rotation]
            modes = ("old", "new") if round_index % 2 == 0 else ("new", "old")
            pairs = {}
            for mode in modes:
                session = Session(binary, mode, evidence)
                try:
                    values = {}
                    for index, (label, physical, expected) in enumerate(order):
                        state, image, elapsed = session.compile(physical)
                        need(state == 1, "відмова позитивного source %s %s" % (mode, label))
                        values[label] = image
                        raw_timing[mode].append({
                            "round": round_index, "program": label,
                            "elapsed_ns": elapsed, "source_sha256": sha(physical)
                        })
                        if index == 0:
                            cold[mode].append(time.perf_counter_ns() - session.launch_ns)
                    pairs[mode] = values
                finally:
                    session.close()
            for label, physical, expected in cases:
                need(pairs["old"][label] == pairs["new"][label],
                     "byte parity ELF порушено: " + label)
                if round_index == 0:
                    machine_proof(pairs["old"][label], expected, evidence, label)
    med_old = statistics.median(x["elapsed_ns"] for x in raw_timing["old"])
    med_new = statistics.median(x["elapsed_ns"] for x in raw_timing["new"])
    speedup = med_old / med_new
    result = {
        "contract": "SENS 12.0 pinned; D5:01000/D12 → D1",
        "scope": "first compilation of distinct physical program within persistent process",
        "samples_per_mode": 96,
        "warmup_excluded": True,
        "byte_identical_elf": 16,
        "executed_elf": 16,
        "machine_output": "canonical T5M D1",
        "negative_fixtures": len(negatives),
        "recoverable_negative": len(negatives)-1,
        "terminal_empty_frame": True,
        "no_cross_program_cache": True,
        "oracle": "NOT_VERIFIED: machine physical fixtures only",
        "energy": "NOT_MEASURED",
        "median_old_ns": med_old,
        "median_new_ns": med_new,
        "speedup": speedup,
        "cold_process_ns": cold,
        "raw": raw_timing,
    }
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(
        "КОНТЕКСТ-D5-НУЛЬ-ГОТОВО unique=16 elfs=16 parity=16 "
        "negatives=8 median_old_ns=%d median_new_ns=%d speedup=%.4f "
        "oracle=NOT_VERIFIED energy=NOT_MEASURED" % (med_old, med_new, speedup)
    )


if __name__ == "__main__":
    main()
