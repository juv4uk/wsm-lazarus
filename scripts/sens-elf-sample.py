#!/usr/bin/env python3
"""G6.143: чесний вимір процесу фізичного SENS ELF64 з побайтовою відповіддю.

Це зовнішній host-вимірювач, НЕ SENS parser/evaluator і НЕ енергометр.
Семантичний допуск здійснює лише вже існуючий pinned WideIR compiler;
очікувані T5M-байти приходять із перевіреного фізичного свідка.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import statistics
import struct
import subprocess
import sys
import time


class WitnessError(Exception):
    """Непридатний host-артефакт або порушення фізичного свідка."""


def file_bytes(path: Path, suffix: str, limit: int) -> bytes:
    """Позичений шлях; результат — власні bytes, без утримання файлового дескриптора.

    1) Чому .lisp не можна видавати за фізичний .sens?
    2) Чому symlink відхиляється до читання?
    3) Кому належить повернутий byte string?
    """
    if path.suffix != suffix:
        raise WitnessError(f"потрібне розширення {suffix}: {path.name}")
    try:
        info = path.lstat()
        if not stat.S_ISREG(info.st_mode) or not (0 < info.st_size <= limit):
            raise WitnessError(f"відхилено тип або розмір: {path.name}")
        data = path.read_bytes()
        if len(data) != info.st_size:
            raise WitnessError(f"файл змінився під час читання: {path.name}")
        return data
    except OSError as exc:
        raise WitnessError(f"не можна прочитати {path.name}: {exc}") from exc


def check_elf(image: bytes) -> None:
    """Мінімальний незалежний host-огляд ELF, а не другий SENS backend.

    1) Чим ET_DYN відрізняється від запуску через інтерпретатор?
    2) Чому PT_INTERP/PT_DYNAMIC неприпустимі для цього вузького профілю?
    3) Чому перевірка геометрії ще не є доказом машинного результату?
    """
    if (len(image) < 120 or image[:4] != b"\x7fELF" or
            image[4:6] != b"\x02\x01"):
        raise WitnessError("не ELF64 little-endian")
    if struct.unpack_from("<HH", image, 16) != (3, 62):
        raise WitnessError("потрібен Linux x86-64 ET_DYN")
    phoff = struct.unpack_from("<Q", image, 32)[0]
    entsize, count = struct.unpack_from("<HH", image, 54)
    if entsize < 56 or count < 1 or phoff < 64 or phoff + entsize * count > len(image):
        raise WitnessError("пошкоджена ELF program-header геометрія")
    load = False
    for i in range(count):
        kind = struct.unpack_from("<I", image, phoff + i * entsize)[0]
        if kind in (2, 3):  # host PT_DYNAMIC або PT_INTERP
            raise WitnessError("ELF містить динамічні залежності")
        load = load or kind == 1
    if not load:
        raise WitnessError("ELF не містить PT_LOAD")


def execute(executable: Path, expected: bytes) -> int:
    """Кожний процес окремий; повертається monotonic wall time в ns.

    1) Чому час включає fork/exec і НЕ є часом одного SENS виклику?
    2) Чому жоден неправильний stdout не потрапить до фінального JSON?
    3) Чому цей вимір НЕ стверджує джоулі?
    """
    start = time.perf_counter_ns()
    try:
        p = subprocess.run([str(executable.resolve())], input=b"",
                           capture_output=True, timeout=10, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise WitnessError(f"помилка машинного виконання: {exc}") from exc
    elapsed = time.perf_counter_ns() - start
    if p.returncode != 0 or p.stderr or p.stdout != expected:
        raise WitnessError("невідповідність ELF: "
                           f"exit={p.returncode} stderr={len(p.stderr)} "
                           f"stdout={len(p.stdout)} очікувано={len(expected)}")
    return elapsed


def run(source: Path, executable: Path, expected_path: Path,
        repeats: int, warmup: int) -> dict:
    """Усі звірки виконано до повернення report; часткових результатів немає."""
    if not 3 <= repeats <= 50 or not 0 <= warmup <= 10:
        raise WitnessError("потрібно 3..50 повторів і 0..10 прогрівань")
    src = file_bytes(source, ".sens", 65536)
    wanted = file_bytes(expected_path, ".sens", 65536)
    elf = file_bytes(executable, ".elf", 64 * 1024 * 1024)
    check_elf(elf)
    if not os.access(executable, os.X_OK):
        raise WitnessError("ELF не є виконуваним")
    before = executable.stat()
    for _ in range(warmup):
        execute(executable, wanted)
    elapsed = [execute(executable, wanted) for _ in range(repeats)]
    after = executable.stat()
    if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
            after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
        raise WitnessError("ELF змінено під час вимірювання")
    return {
        "тип": "G6.143: process-start-to-physical-stdout",
        "семантичний_оракул": "НЕ_ЗАПУСКАВСЯ_ЦИМ_ВИМІРЮВАЧЕМ",
        "джоулі": "НЕ_ВИМІРЯНО",
        "джерело_sha256": hashlib.sha256(src).hexdigest(),
        "виконуваний_elf64_sha256": hashlib.sha256(elf).hexdigest(),
        "очікувані_t5m_sha256": hashlib.sha256(wanted).hexdigest(),
        "байтів_відповіді": len(wanted),
        "повтори": repeats,
        "прогрівання": warmup,
        "медіана_часу_нс": int(statistics.median(elapsed)),
        "мінімум_часу_нс": min(elapsed),
        "максимум_часу_нс": max(elapsed),
        "побайтовий_збіг": repeats + warmup,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--elf", type=Path, required=True)
    parser.add_argument("--expected", type=Path, required=True)
    parser.add_argument("--repeats", type=int, default=7)
    parser.add_argument("--warmup", type=int, default=1)
    args = parser.parse_args()
    try:
        data = run(args.source, args.elf, args.expected, args.repeats, args.warmup)
    except WitnessError as exc:
        print(f"ЕЛЬФ-ВИМІР-ВІДМОВА: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(data, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
