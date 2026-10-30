#!/usr/bin/env python3
"""G6 — opt-in чотиримісний exact T5M→ELF LRU у постійному FPC сеансі.

Перевіряємо фактичні байти ELF і їхнє виконання. Мовний оракул:
готові фізичні очікування pinned SENS із test-irwidefront.
Час — лише host wall-clock, енергія НЕ ВИМІРЯНА.
"""
from __future__ import annotations

import json
import os
import re
import statistics
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

NORMAL = "--компілювати-фізичний-сеанс"
TWO = "--компілювати-фізичний-сеанс-кеш-2"
FOUR = "--компілювати-фізичний-сеанс-кеш-4"


def frame(raw: bytes) -> bytes:
    return struct.pack("<I", len(raw)) + raw


def unpack(raw: bytes) -> list[tuple[int, bytes]]:
    rows: list[tuple[int, bytes]] = []
    pos = 0
    while pos < len(raw):
        assert pos + 5 <= len(raw), "обірваний host-заголовок"
        status, size = struct.unpack_from("<BI", raw, pos)
        pos += 5
        assert status in (0, 1) and 0 < size <= 1048576
        assert pos + size <= len(raw), "обірваний host-результат"
        rows.append((status, raw[pos:pos + size]))
        pos += size
    return rows


def call(exe: Path, mode: str, data: bytes,
         timeout: int = 120) -> tuple[subprocess.CompletedProcess[bytes], int]:
    start = time.perf_counter_ns()
    finished = subprocess.run([str(exe), mode], input=data,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              timeout=timeout, check=False)
    elapsed = time.perf_counter_ns() - start
    if b"unfreed memory blocks" in finished.stderr:
        assert re.search(rb"(?:^|\s)0 unfreed memory blocks", finished.stderr)
    return finished, elapsed


def check(exe: Path, mode: str, inputs: list[bytes],
          *, hits: int | None = None,
          misses: int | None = None) -> tuple[list[tuple[int, bytes]], int]:
    p, elapsed = call(exe, mode, b"".join(frame(src) for src in inputs))
    assert p.returncode == 0, (mode, p.returncode, p.stderr[-1200:])
    if mode == FOUR:
        assert f"КЕШ-4-СЕАНС-ГОТОВО hits={hits} misses={misses}".encode() in p.stderr
    elif mode == TWO:
        assert f"КЕШ-2-СЕАНС-ГОТОВО hits={hits} misses={misses}".encode() in p.stderr
        assert "КЕШ-4-СЕАНС-ГОТОВО".encode() not in p.stderr
    else:
        assert "КЕШ-4-СЕАНС-ГОТОВО".encode() not in p.stderr
        assert "КЕШ-2-СЕАНС-ГОТОВО".encode() not in p.stderr
    result = unpack(p.stdout)
    assert len(result) == len(inputs), (len(result), len(inputs))
    return result, elapsed


def main() -> None:
    assert len(sys.argv) == 3, "вкажіть FPC CLI й каталог 16 pinned fixtures"
    exe, fixture = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    assert exe.is_file() and os.access(exe, os.X_OK)
    labels = ("01", "02", "05", "15", "03")
    physical = {label: (fixture / (label + ".sens")).read_bytes()
                for label in labels}
    a, b, c, d, e = [physical[label] for label in labels]
    assert all(physical.values()) and len(set(physical.values())) == 5

    # Чотири різні ключі + два відхилені кадри, рівно 64 host-кадри.
    # 62 успіхи: 4 cache misses, 58 hits; cache-2 thrash → 62 misses.
    cases = [a, b, c, d] * 15 + [b"\xff", a, b, b""]
    assert len(cases) == 64
    baseline, t0 = check(exe, NORMAL, cases)
    cache2, _ = check(exe, TWO, cases, hits=0, misses=62)
    cache4, t4 = check(exe, FOUR, cases, hits=58, misses=4)
    assert baseline == cache2 == cache4, "кеш змінює машинний вихід"
    assert (sum(status == 1 for status, _ in cache4),
            sum(status == 0 for status, _ in cache4)) == (62, 2)

    # Виконуємо ЧОТИРИ справжні ELF64, звіряючи байти з уже pinned
    # фізичними очікуваннями; Python не виводить жодного мовного закону.
    with tempfile.TemporaryDirectory(prefix="sens-kesh4-") as tmp:
        for label in labels[:4]:
            key = physical[label]
            idx = cases.index(key)
            status, image = cache4[idx]
            assert status == 1 and image.startswith(b"\x7fELF")
            assert all(cache4[i] == (1, image)
                       for i, src in enumerate(cases) if src == key)
            dest = Path(tmp) / (label + ".elf")
            dest.write_bytes(image)
            dest.chmod(0o700)
            executed = subprocess.run([str(dest)], capture_output=True,
                                      timeout=10, check=False)
            expected = (fixture / (label + ".expected.sens")).read_bytes()
            assert (executed.returncode == 0 and executed.stderr == b"" and
                    executed.stdout == expected), (label, executed)

    # LRU: A,B,C,D,A,E,A,B,C,D,(bad),A.
    # Після E витісняється B, далі C,D,E; A весь час лишається.
    evict = [a, b, c, d, a, e, a, b, c, d, b"\xff", a]
    old_evict, _ = check(exe, NORMAL, evict)
    new_evict, _ = check(exe, FOUR, evict, hits=3, misses=8)
    assert old_evict == new_evict
    assert len(new_evict) == 12 and sum(status == 0 for status, _ in new_evict) == 1

    # Відхилення terminal host framing не може створити псевдо-ELF.
    for malformed in (b"", b"\x01\x00",
                      struct.pack("<I", 4) + b"\x01",
                      struct.pack("<I", 65537)):
        result, _ = call(exe, FOUR, malformed, timeout=12)
        assert result.returncode == 2 and result.stdout == b"", result.stderr
        assert "ШИРОКИЙ-СЕАНС-ВІДМОВА".encode() in result.stderr

    # 65-й нульовий кадр — terminal, перші 64 лише recoverable errors.
    over, _ = call(exe, FOUR, struct.pack("<I", 0) * 65, timeout=12)
    assert over.returncode == 2
    assert len(unpack(over.stdout)) == 64
    assert all(status == 0 for status, _ in unpack(over.stdout))

    # Додаткові повтори часу без будь-якого порогу або заяви про рекорд.
    raw_ns = {NORMAL: [t0], FOUR: [t4]}
    for round_index in range(2):
        order = (FOUR, NORMAL) if round_index % 2 == 0 else (NORMAL, FOUR)
        for mode in order:
            observed, duration = check(exe, mode, cases,
                                       hits=58 if mode == FOUR else None,
                                       misses=4 if mode == FOUR else None)
            assert observed == baseline
            raw_ns[mode].append(duration)
    report = {
        "schema": "sens-fpc-verified-elf-cache4-host-latency/1",
        "pin_sens": "2c498b35af53c085450eac6f51b87facf7f9aa47",
        "frames": 64, "successful": 62, "negative": 2,
        "cache4_hits": 58, "cache4_misses": 4,
        "machine_executed": 4, "independent_oracle": "NOT-CHECKED",
        "energy": "NOT-MEASURED",
        "host_wall_ns": raw_ns,
        "median_ns": {mode: int(statistics.median(samples))
                      for mode, samples in raw_ns.items()},
    }
    if os.environ.get("SENS_CACHE4_REPORT"):
        dest = Path(os.environ["SENS_CACHE4_REPORT"]).resolve()
        dest.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                        encoding="utf-8")
    print("G6-КЕШ-4-ПРОЙДЕНО frames=64 good=62 negative=2 "
          "two-hits=0 two-misses=62 four-hits=58 four-misses=4 "
          "evict-hits=3 evict-misses=8 executed=4 terminal=5 "
          "oracle=NOT-CHECKED energy=NOT-MEASURED")
    print("HOST-МЕДІАНА-НС без-кешу="
          + str(report["median_ns"][NORMAL])
          + " кеш-4=" + str(report["median_ns"][FOUR])
          + " рекорд=НЕ-ДОВЕДЕНО")


if __name__ == "__main__":
    main()
