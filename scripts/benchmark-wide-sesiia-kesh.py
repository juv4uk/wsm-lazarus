#!/usr/bin/env python3
"""G6.175: чесний профіль persistent FPC ELF64 із точнобайтовим кешем.

Дві реалізації = той самий бінарний CLI у різних HOST-режимах.
Мовні відповіді: тільки фізичні свідки pinned SENS, не Python evaluator.
Енергія: опційна пакетна RAPL, не PID. CI на hosted runner НЕ вимірює її.
"""
from __future__ import annotations

import hashlib
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

PIN = "1f1bf676eeac605e065035d9dd2adaae807f1788"
NORMAL = "--компілювати-фізичний-сеанс"
CACHED = "--компілювати-фізичний-сеанс-кеш"
ROUNDS = 6
FRAMES = 64
STATUS = "КЕШ-СЕАНС-ГОТОВО hits=60 misses=2".encode("utf-8")
HOST_ERROR = "ШИРОКИЙ-СЕАНС-ВІДМОВА".encode("utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def host_frame(payload: bytes) -> bytes:
    return struct.pack("<I", len(payload)) + payload


def read_replies(data: bytes) -> list[tuple[int, bytes]]:
    replies: list[tuple[int, bytes]] = []
    pos = 0
    while pos < len(data):
        require(pos + 5 <= len(data), "обірвана host-відповідь")
        status = data[pos]
        size = struct.unpack_from("<I", data, pos + 1)[0]
        pos += 5
        require(status in (0, 1) and 0 < size <= 1048576,
                "помилковий статус або довжина ELF")
        require(pos + size <= len(data), "відповідь обірвано")
        replies.append((status, data[pos:pos + size]))
        pos += size
    return replies


class PackageRapl:
    """Необов'язковий повний енергопакет ОС, НЕ енергія процесу."""
    def __init__(self) -> None:
        raw = os.environ.get("SENS_RAPL_ENERGY_PATH", "")
        self.path = Path(raw) if raw else None
        self.maximum: int | None = None
        if self.path is not None:
            require(self.path.name == "energy_uj",
                    "SENS_RAPL_ENERGY_PATH має закінчуватися energy_uj")
            self.maximum = int(
                (self.path.parent / "max_energy_range_uj").read_text().strip()
            )
            require(self.maximum > 0, "некоректна межа RAPL")
            self.read()

    def read(self) -> int | None:
        if self.path is None:
            return None
        value = int(self.path.read_text().strip())
        require(self.maximum is not None and 0 <= value < self.maximum,
                "неправильне значення лічильника RAPL")
        return value

    def delta(self, before: int | None, after: int | None) -> int | None:
        if before is None or after is None:
            return None
        require(self.maximum is not None, "не заданий RAPL діапазон")
        # Вірно лише якщо між пробами не більш як один оберт лічильника.
        return (after - before) % self.maximum


def execute_once(exe: Path, mode: str, incoming: bytes,
                 rapl: PackageRapl) -> tuple[bytes, int, int | None]:
    start_energy = rapl.read()
    start = time.perf_counter_ns()
    completed = subprocess.run(
        [str(exe), mode], input=incoming,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=100,
        check=False,
    )
    elapsed_ns = time.perf_counter_ns() - start
    end_energy = rapl.read()
    require(completed.returncode == 0,
            f"{mode}: rc={completed.returncode}: {completed.stderr[-600:]!r}")
    stderr = completed.stderr
    if b"unfreed memory blocks" in stderr:
        require(re.search(rb"(?:^|\s)0 unfreed memory blocks", stderr) is not None,
                "HeapTrc виявив витік")
    if mode == CACHED:
        require(STATUS in stderr,
                f"не підтверджено exact hits/misses: {stderr[-400:]!r}")
    else:
        require(STATUS not in stderr, "старий режим змінив діагностику")
    return completed.stdout, elapsed_ns, rapl.delta(start_energy, end_energy)


def median_ms(samples: list[int]) -> float:
    return round(statistics.median(samples) / 1_000_000, 4)


def main() -> None:
    require(len(sys.argv) == 4,
            "виклик: benchmark.py КОМПІЛЯТОР ФІЗИЧНІ_СВІДКИ ЗВІТ.json")
    exe = Path(sys.argv[1]).resolve()
    source_dir = Path(sys.argv[2]).resolve()
    report_path = Path(sys.argv[3]).resolve()
    require(exe.is_file() and os.access(exe, os.X_OK), "немає FPC-компілятора")

    a = (source_dir / "01.sens").read_bytes()
    b = (source_dir / "15.sens").read_bytes()
    require(bool(a) and bool(b) and a != b, "вхідні T5M не унікальні")
    # 30×A, відмова, A, 30×B, B, відмова:
    # 64 кадри: 62 success; 2 miss; 60 exact-byte hit; 2 recovery.
    physical = [a] * 30 + [b"\xff"] + [a] + [b] * 30 + [b] + [b"\xff"]
    require(len(physical) == FRAMES, "змінена кількість host-кадрів")
    incoming = b"".join(host_frame(x) for x in physical)
    rapl = PackageRapl()
    durations: dict[str, list[int]] = {NORMAL: [], CACHED: []}
    energies: dict[str, list[int]] = {NORMAL: [], CACHED: []}

    # Прогрів: до усіх вимірів той самий pinned authority і та сама робота.
    golden, _, _ = execute_once(exe, NORMAL, incoming, rapl)
    cached_golden, _, _ = execute_once(exe, CACHED, incoming, rapl)
    require(golden == cached_golden,
            "кеш змінює фізичний вихід чи host-діагностику")
    replies = read_replies(golden)
    require(len(replies) == FRAMES, "загублено host-кадри")
    for i, ((status, payload), src) in enumerate(zip(replies, physical)):
        if src == b"\xff":
            require(status == 0 and bool(payload), f"негатив {i} пропущено")
        else:
            require(status == 1 and payload.startswith(b"\x7fELF"),
                    f"не ELF64 у кадрі {i}")
    require(sum(status == 1 for status, _ in replies) == 62,
            "не 62 справжні машинні відповіді")

    # Після компіляції реально виконати ДВА різні ELF64; очікувані
    # результати беремо із чинних canonical T5M свідків, не обчислюємо.
    with tempfile.TemporaryDirectory(prefix="sens-kesh-perf-") as tmp:
        for src, label in ((a, "01"), (b, "15")):
            indices = [i for i, p in enumerate(physical) if p == src]
            elf_bytes = replies[indices[0]][1]
            require(all(replies[i][1] == elf_bytes for i in indices),
                    f"{label}: повторний ELF неідентичний")
            path = Path(tmp) / (label + ".elf")
            path.write_bytes(elf_bytes)
            path.chmod(0o700)
            done = subprocess.run([str(path)], capture_output=True,
                                  timeout=8, check=False)
            require(done.returncode == 0 and not done.stderr,
                    f"{label}: ELF не виконується")
            require(done.stdout ==
                    (source_dir / (label + ".expected.sens")).read_bytes(),
                    f"{label}: machine stdout != pinned T5M fixture")

    # Поперемінний порядок A/B, щоб відокремити прогрів і час запуску.
    # Не ставимо порога швидкодії: шум спільного CI не є дефектом.
    for trial in range(ROUNDS):
        order = (NORMAL, CACHED) if trial % 2 == 0 else (CACHED, NORMAL)
        for mode in order:
            stdout, elapsed, microjoules = execute_once(
                exe, mode, incoming, rapl
            )
            require(stdout == golden, f"розбіжність machine ELF trial={trial}")
            durations[mode].append(elapsed)
            if microjoules is not None:
                energies[mode].append(microjoules)

    baseline_median = median_ms(durations[NORMAL])
    cache_median = median_ms(durations[CACHED])
    require(baseline_median > 0 and cache_median > 0,
            "неправильний таймер")
    energy_data: dict[str, object] = {
        "стан": "НЕ-ВИМІРЯНО",
        "зауваження": "GitHub hosted CI без RAPL; час не є енергією",
    }
    if rapl.path is not None:
        require(all(len(v) == ROUNDS for v in energies.values()),
                "неповні RAPL вимірювання")
        energy_data = {
            "стан": "ПАКЕТ-ОС-ВИМІРЯНО",
            "джерело": str(rapl.path),
            "одиниця": "мікроджоулі",
            "медіана_без_кешу": statistics.median(energies[NORMAL]),
            "медіана_з_кешем": statistics.median(energies[CACHED]),
            "зауваження": (
                "Це енергія CPU-пакета разом із фоновими процесами; НЕ PID. "
                "Дійсна лише за відсутності більш ніж одного оберту RAPL."
            ),
        }

    report = {
        "зріз": "G6.175",
        "pin_SENS": PIN,
        "джерело": "packed canonical .sens/T5M, 01 та 15 з pinned генератора",
        "host_кадрів": FRAMES,
        "позитивних": 62,
        "негативних": 2,
        "кеш_hits": 60,
        "кеш_misses": 2,
        "виконано_ELF": 2,
        "раундів_на_режим": ROUNDS,
        "SHA256_побайтового_потоку": hashlib.sha256(golden).hexdigest(),
        "без_кешу_час_мс": [round(x / 1_000_000, 4) for x in durations[NORMAL]],
        "з_кешем_час_мс": [round(x / 1_000_000, 4) for x in durations[CACHED]],
        "медіана_без_кешу_мс": baseline_median,
        "медіана_з_кешем_мс": cache_median,
        "співвідношення_часу": round(baseline_median / cache_median, 3),
        "енергія": energy_data,
        "межа": "Тільки 2 профільні фізичні SENS тіла; не загальна швидкість мови",
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2,
                                      sort_keys=True) + "\n", encoding="utf-8")
    print("G6.175-КЕШ-ПРОФІЛЬ-ПРОЙДЕНО frames=64 good=62 negative=2 "
          "hits=60 misses=2 rounds=6 machine=2 oracle=NOT-CHECKED "
          "rapl=" + ("PACKAGE" if rapl.path else "NOT-MEASURED"))
    print(f"ЧАС-МЕДІАНА без-кешу={baseline_median:.4f}мс "
          f"із-кешем={cache_median:.4f}мс "
          f"співвідношення={baseline_median/cache_median:.3f}")


if __name__ == "__main__":
    main()
