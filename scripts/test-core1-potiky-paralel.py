#!/usr/bin/env python3
"""G6.171: parallel process isolation of pinned Core1→ELF64, no SENS laws here.

Paths and T5M bytes are host data. All compiler outputs are owned by a
temporary directory; no Pascal evaluator, no D7 dispatch, no energy claims.
Questions: Why separate processes? Why exact machine-byte comparisons?
Why reject promotion to D24? Why require the upstream oracle separately?
"""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

PIN = b"1f1bf676eeac605e065035d9dd2adaae807f1788"

def need(ok: bool, why: str) -> None:
    if not ok:
        raise AssertionError("ЯДРО1-ПАРАЛЕЛЬ-ВІДМОВА: " + why)

def proc(argv: list[str], cwd: Path, data: bytes = b"", seconds: int = 120):
    return subprocess.run(argv, cwd=cwd, input=data, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=seconds, check=False)

def cases(path: Path, count: int, width: int):
    parsed = []
    for line in path.read_text(encoding="utf-8").splitlines():
        bits = line.split("\t")
        need(len(bits) == 6, "очікувано шість полів фізичного свідка")
        label, head, left, right, decimal, w = bits
        need(w == str(width) and head != "" and left != "" and right != ""
             and decimal != "" and label[0] in "as" and label[1:].isdigit(),
             "зіпсовано pinned тестовий вектор")
        parsed.append((label, label[0], left, right, decimal))
    need(len(parsed) == count and len({x[0] for x in parsed}) == count,
         "змінено кількість або унікальність фізичних свідків")
    return parsed

def assert_result(reply, expected: bytes, bad: bool, label: str):
    if bad:
        need(reply.returncode == 2 and reply.stdout == b"" and
             "ВІДМОВА".encode("utf-8") in reply.stderr,
             "хибний stdin або D24 прийнято: " + label)
    else:
        need(reply.returncode == 0 and reply.stdout == expected
             and reply.stderr == b"", "машинна відповідь не точна: " + label)

def native(root: Path, compiler: Path, fixtures: Path, tmp: Path) -> None:
    ok = cases(fixtures / "cases.tsv", 33, 12)
    promoted = cases(fixtures / "promotion.tsv", 7, 24)
    def compile_one(job):
        mode, i = job
        output = tmp / f"{mode}-{i}.elf"
        flag = "--ядро1-додати-потік" if mode == "a" else "--ядро1-відняти-потік"
        reply = proc([str(compiler), flag, str(output)], root)
        need(reply.returncode == 0 and b"ELF" in reply.stdout
             and output.is_file() and os.access(output, os.X_OK),
             "незалежний компілятор відмовив: " + output.name +
             reply.stderr.decode("utf-8", "replace")[-150:])
        data = output.read_bytes()
        need(len(data) > 120 and data[:4] == b"\x7fELF",
             "відсутній машинний ELF64")
        header = proc(["readelf", "-h", str(output)], root, seconds=10)
        need(header.returncode == 0 and b"DYN" in header.stdout and
             b"Advanced Micro Devices X86-64" in header.stdout,
             "невірна геометрія машинного ELF")
        return mode, output, hashlib.sha256(data).hexdigest()
    jobs = [(mode, i) for mode in ("a", "s") for i in range(4)]
    with ThreadPoolExecutor(max_workers=8) as pool:
        compiled = list(pool.map(compile_one, jobs))
    binaries = {"a": [], "s": []}
    saved = {}
    for op, binary, sha in compiled:
        binaries[op].append(binary)
        saved[binary] = sha
    for op in ("a", "s"):
        need(len(binaries[op]) == 4 and len({saved[p] for p in binaries[op]}) == 1,
             "конкурентна компіляція не відтворює ELF: " + op)
    tasks = []
    for wave in range(2):
        for i, (label, op, left, right, decimal) in enumerate(ok):
            frame = (fixtures / f"{label}.frame").read_bytes()
            expected = (fixtures / f"{label}.expected.sens").read_bytes()
            need(len(frame) == 6 and len(expected) == 3,
                 "пошкоджено точний 2×D12 → D12 transport")
            tasks.append((binaries[op][(i+wave) % 4], frame, expected, False,
                          f"{label}-хвиля-{wave}"))
    for i, (label, op, *_) in enumerate(promoted):
        frame = (fixtures / f"{label}.frame").read_bytes()
        want = (fixtures / f"{label}.expected.sens").read_bytes()
        need(len(frame) == 6 and len(want) == 5,
             "підвищення потребує фізичного D24 результату")
        tasks.append((binaries[op][i % 4], frame, b"", True, label))
    for op in ("a", "s"):
        for i, key in enumerate(("empty", "short", "extra", "bad-first",
                                 "bad-middle", "text", "d1")):
            tasks.append((binaries[op][i % 4],
                          (fixtures / f"{key}.frame").read_bytes(),
                          b"", True, op + key))
    def execute(task):
        binary, frame, expected, bad, label = task
        return proc([str(binary)], root, frame, 10), expected, bad, label
    with ThreadPoolExecutor(max_workers=8) as pool:
        replies = list(pool.map(execute, tasks))
    for actual, expected, bad, label in replies:
        assert_result(actual, expected, bad, label)
    first, expected, _, _ = replies[0]
    poisoned = subprocess.CompletedProcess([], 0, first.stdout + b"\x00", b"")
    try:
        assert_result(poisoned, expected, False, "підроблений вихід")
    except AssertionError:
        pass
    else:
        raise AssertionError("не виявлено навмисне пошкодження stdout")
    for binary, sha in saved.items():
        need(hashlib.sha256(binary.read_bytes()).hexdigest() == sha,
             "під час паралельного виконання змінено ELF")
    occupied = binaries["a"][0]
    rejected = proc([str(compiler), "--ядро1-відняти-потік", str(occupied)], root)
    need(rejected.returncode == 2 and rejected.stdout == b"" and
         hashlib.sha256(occupied.read_bytes()).hexdigest() == saved[occupied],
         "компілятор перезаписав уже створений ELF")
    name, op, *_ = ok[0]
    assert_result(proc([str(binaries[op][0])], root,
                       (fixtures / f"{name}.frame").read_bytes(), 10),
                  (fixtures / f"{name}.expected.sens").read_bytes(),
                  False, "відновлення")
    print("ЯДРО1-ПАРАЛЕЛЬ-ГОТОВО compilers=8 identical=4+4 "
          "native=66 promoted-rejected=7 invalid-rejected=14 "
          "no-clobber=1 recovery=1 mutation=1 oracle=NOT-CHECKED "
          "energy=NOT-MEASURED")

def oracle(root: Path, binary: Path, fixtures: Path, tmp: Path) -> None:
    good = cases(fixtures / "cases.tsv", 33, 12)
    promoted = cases(fixtures / "promotion.tsv", 7, 24)
    actual_pin = proc(["git", "-C", str(root / "sens-oracle"),
                       "rev-parse", "HEAD"], root, seconds=20)
    need(actual_pin.returncode == 0 and actual_pin.stdout.strip() == PIN,
         "незалежний SENS oracle не pinned Contract 12.0")
    for i, (label, op, left, right, decimal) in enumerate(good + promoted):
        source = tmp / f"orakul-{i}.lisp"
        source.write_text("(" + ("додати" if op == "a" else "відняти") +
                          " " + left + " " + right + ")\n", encoding="utf-8")
        result = proc([str(binary), str(source)], root, seconds=60)
        need(result.returncode == 0 and result.stderr == b"" and
             result.stdout == (decimal + "\n").encode("utf-8"),
             "немає pinned SENS REPL parity: " + label)
    print("ЯДРО1-ПАРАЛЕЛЬ-ОРАКУЛ-ГОТОВО d12=33 d24=7 parity=40 "
          "energy=NOT-MEASURED")

def main() -> None:
    need(len(sys.argv) == 6 and sys.argv[1] in ("native", "oracle"),
         "виклик: native|oracle ROOT COMPILER|SENS_ORACLE FIXTURES TMP")
    mode, root, compiler, fixtures, tmp = sys.argv[1:]
    root, compiler, fixtures, tmp = (Path(x).resolve() for x in
                                     (root, compiler, fixtures, tmp))
    need(root.is_dir() and compiler.is_file() and fixtures.is_dir()
         and tmp.is_dir(), "відсутні шляхи перевірки")
    if mode == "native": native(root, compiler, fixtures, tmp)
    else: oracle(root, compiler, fixtures, tmp)

if __name__ == "__main__":
    try:
        main()
    except (OSError, AssertionError, subprocess.TimeoutExpired) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(2)
