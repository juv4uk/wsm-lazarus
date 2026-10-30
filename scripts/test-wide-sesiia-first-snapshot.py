#!/usr/bin/env python3
"""G6: перша компіляція КОЖНОГО нового фізичного T5M у FPC сеансі.

Один і той самий WideIR+ELF backend; без output cache. Контроль:
16 різних фізичних форм + 2 відмови, усі machine ELF реально виконані.
Host-wall time не дорівнює суто IR time або енергії.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import statistics
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

BASE = "--компілювати-фізичний-сеанс"
FAST = "--компілювати-фізичний-сеанс-швидкий-перший"


def packets(raw: bytes) -> bytes:
    return struct.pack("<I", len(raw)) + raw


def parse(data: bytes) -> list[tuple[int, bytes]]:
    out = []
    pos = 0
    while pos < len(data):
        assert pos + 5 <= len(data), "неповна заголовкова п'ятірка"
        status, size = struct.unpack_from("<BI", data, pos)
        pos += 5
        assert status in (0, 1) and 0 < size <= 1048576
        assert pos + size <= len(data)
        out.append((status, data[pos:pos + size]))
        pos += size
    return out


def execute(exe: Path, mode: str, forms: list[bytes]) -> tuple[list[tuple[int, bytes]], int]:
    before = time.perf_counter_ns()
    call = subprocess.run([str(exe), mode],
                          input=b"".join(packets(form) for form in forms),
                          capture_output=True, timeout=120, check=False)
    duration = time.perf_counter_ns() - before
    assert call.returncode == 0, (mode, call.returncode, call.stderr[-1000:])
    assert b"КЕШ-СЕАНС-ГОТОВО" not in call.stderr
    assert b"КЕШ-2-СЕАНС-ГОТОВО" not in call.stderr
    assert b"КЕШ-4-СЕАНС-ГОТОВО" not in call.stderr
    result = parse(call.stdout)
    assert len(result) == len(forms), (mode, len(result), len(forms))
    return result, duration


def main() -> None:
    assert len(sys.argv) == 3, "потрібні FPC компілятор та фізичні свідки"
    exe = Path(sys.argv[1]).resolve()
    root = Path(sys.argv[2]).resolve()
    assert exe.is_file() and os.access(exe, os.X_OK)
    names = [f"{n:02d}" for n in range(1, 17)]
    bodies = [(root / (name + ".sens")).read_bytes() for name in names]
    assert all(bodies) and len(set(bodies)) == 16
    # Дві відмови: порожній кадр і недопустимий T5M байт.
    corpus = bodies + [b"", b"\xff"]
    a, first_base = execute(exe, BASE, corpus)
    b, first_fast = execute(exe, FAST, corpus)
    assert a == b, "новий scope змінив ELF або текст діагностики"
    assert [s for s, _ in b] == [1] * 16 + [0, 0]
    for _, diagnostic in b[-2:]:
        assert diagnostic and not diagnostic.startswith(b"\x7fELF")

    # Перші 16 позицій — 16 РІЗНИХ програм, тобто жоден ELF не
    # повторюється з output-cache в межах запуску.
    with tempfile.TemporaryDirectory(prefix="sens-persha-kompiliatsiia-") as tmp:
        for name, (status, image) in zip(names, b[:16]):
            assert status == 1 and image.startswith(b"\x7fELF")
            dest = Path(tmp) / (name + ".elf")
            dest.write_bytes(image)
            dest.chmod(0o700)
            machine = subprocess.run([str(dest)], capture_output=True,
                                     timeout=10, check=False)
            expected = (root / (name + ".expected.sens")).read_bytes()
            assert (machine.returncode == 0 and machine.stderr == b"" and
                    machine.stdout == expected), (name, machine.returncode)

    # Три повтори з чергуванням порядку, без вимоги прискорення:
    # вимірюється повний host process для НОВИХ програм у кожному сеансі.
    raw = {BASE: [first_base], FAST: [first_fast]}
    for round_num in range(2):
        order = [FAST, BASE] if round_num == 0 else [BASE, FAST]
        for mode in order:
            observed, duration = execute(exe, mode, corpus)
            assert observed == a, "результат змінився між раундами"
            raw[mode].append(duration)
    med = {mode: int(statistics.median(times)) for mode, times in raw.items()}
    report = {
        "schema": "sens-first-verified-elf-scoped-pinned/1",
        "pinned_sens": "1f1bf676eeac605e065035d9dd2adaae807f1788",
        "distinct_programs": 16,
        "failed_frames": 2,
        "executed_elf": 16,
        "output_sha256": [hashlib.sha256(x).hexdigest() for _, x in a[:16]],
        "raw_host_wall_ns": raw,
        "median_host_wall_ns": med,
        "energy": "NOT-MEASURED",
        "independent_sens_oracle_in_this_test": "NOT-CHECKED",
        "speed_record": "NOT-CLAIMED"
    }
    if os.environ.get("SENS_FIRST_SCOPE_REPORT"):
        Path(os.environ["SENS_FIRST_SCOPE_REPORT"]).write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8"
        )
    print("ПЕРША-КОМПІЛЯЦІЯ-ПРОЙДЕНО fresh=16 negative=2 "
          "elf-executed=16 parity=byte-exact cycles=3 "
          "oracle=NOT-CHECKED energy=NOT-MEASURED")
    print("ПЕРША-КОМПІЛЯЦІЯ-ЧАС-НС звичайний=" + str(med[BASE]) +
          " scope=" + str(med[FAST]) + " speedup=" +
          (f"{med[BASE]/med[FAST]:.3f}" if med[FAST] else "NA"))


if __name__ == "__main__":
    main()
