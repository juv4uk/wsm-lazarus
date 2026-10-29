#!/usr/bin/env python3
"""GЕ.5: фізичний compiled ELF проти FPC; RAPL лише за реальних датчиків.

Це вимір енергії апаратної зони під час запусків, НЕ енергія процесу,
НЕ вимір компіляції і НЕ загальний рейтинг мов/компіляторів.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import random
import re
import statistics
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

PIN = "1f1bf676eeac605e065035d9dd2adaae807f1788"
CASES = ("тотожні-00", "тотожні-01", "тотожні-10", "тотожні-11")
CHANNELS = ("готовий_ELF", "фізичний_FPC", "idle")
ZONE = re.compile(r"^intel-rapl:[0-9]+(?:/intel-rapl:[0-9]+:[0-9]+)*$")


def demand(ok: bool, detail: str) -> None:
    if not ok:
        raise ValueError(detail)


def call(argv: list[str], *, cwd: Path, expected: bytes | None = None) -> bytes:
    result = subprocess.run(argv, cwd=cwd, capture_output=True, timeout=30, check=False)
    demand(result.returncode == 0,
           "помилка запуску " + repr(argv) + ": " + repr(result.stderr[:300]))
    demand(not result.stderr, "stderr під час правильного виконання: " + repr(argv))
    if expected is not None:
        demand(result.stdout == expected,
               "неправильна точна відповідь: " + repr(argv) +
               " очікували=" + repr(expected) + " отримали=" + repr(result.stdout[:120]))
    return result.stdout


def parse_rapl(data: bytes, elapsed_us: int, watts: int) -> dict[str, int]:
    """Тільки повністю перевірений RAPL-DELTA1; не підсумовуємо вкладені зони."""
    try:
        text = data.decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        raise ValueError("пошкоджений UTF-8 RAPL") from exc
    lines = text.splitlines()
    demand(len(lines) >= 2 and len(lines) <= 257, "RAPL не має зон")
    demand(lines[0] == f"RAPL-DELTA1\telapsed_us={elapsed_us}\tmax_watts={watts}",
           "неправильний заголовок/інтервал RAPL")
    output: dict[str, int] = {}
    old = ""
    has_package = False
    for line in lines[1:]:
        fields = line.split("\t")
        demand(len(fields) == 6, "зіпсований рядок RAPL")
        key, label, before, after, maximum, delta = fields
        demand(bool(ZONE.fullmatch(key)) and key > old, "дубль або неканонічна зона RAPL")
        demand(bool(label) and all(x.isascii() and x.isdecimal() and
               str(int(x)) == x for x in (before, after, maximum, delta)),
               "пошкоджене фізичне число RAPL")
        b, a, m, d = map(int, (before, after, maximum, delta))
        demand(m > 0 and 0 <= b < m and 0 <= a < m and 0 <= d < m,
               "лічильник RAPL поза діапазоном")
        demand(d == (a - b) % m, "невірний приріст RAPL")
        demand(elapsed_us <= (m - 1) // watts, "неоднозначне обертання RAPL")
        has_package |= label.startswith("package-") and key.count("/") == 0
        output[key] = d
        old = key
    demand(has_package, "ENERGY_NOT_MEASURED: немає package RAPL")
    return output


def negative_tests() -> int:
    good = b"RAPL-DELTA1\telapsed_us=50000\tmax_watts=1000\n" \
           b"intel-rapl:0\tpackage-0\t99999990\t20\t100000000\t30\n"
    demand(parse_rapl(good, 50000, 1000) == {"intel-rapl:0": 30},
           "позитивний wrap RAPL не працює")
    cases = [
        good.replace(b"100000000\t30", b"100000000\t31"),
        good.replace(b"package-0", b"core"),
        good.replace(b"intel-rapl:0", b"intel-rapl:0x"),
        good.replace(b"50000", b"50001"),
        good + b"intel-rapl:0\tpackage-0\t0\t1\t100000000\t1\n",
        good.replace(b"99999990", b"100000000"),
        good.replace(b"\t20\t", b"\t-1\t"),
        b"", b"BAD\n", good + b"BAD\n",
        good.replace(b"\t30\n", b"\t30\t0\n"),
        good.replace(b"99999990", b"not-number"),
        good.replace(b"100000000", b"100"),
    ]
    count = 0
    for wrong in cases:
        try:
            parse_rapl(wrong, 50000, 1000)
        except ValueError:
            count += 1
    demand(count == len(cases), "не всі пошкоджені RAPL дані відхилено")
    try:
        parse_rapl(good, 100000, 1000)
    except ValueError:
        count += 1
    demand(count == len(cases) + 1, "множинне обертання допущено")
    for a, b in ((b"1\n", b"0\n"), (b"1\n", b"1\n0\n"),
                 (b"\x01", b"1\n"), (b"0\n", b"")):
        try:
            demand(a == b, "хибний stdout виконавця")
        except ValueError:
            count += 1
    demand(count == len(cases) + 5, "пошкоджений stdout не відхилено")
    return count


def pin_check(root: Path) -> None:
    contract = root / "external/sens/contracts/language-contract-12.lisp"
    demand(contract.is_file() and '(version . "12.0")' in contract.read_text(),
           "відсутній pinned Contract 12.0")
    oracle_dir = root / "sens-oracle"
    ref = call(["git", "-C", str(oracle_dir), "rev-parse", "HEAD"], cwd=root).strip()
    demand(ref.decode("ascii") == PIN, "незалежний SENS не закріплений за SHA")


def preflight(args: argparse.Namespace, tmp: Path) -> list[dict]:
    root = args.корінь.resolve()
    pin_check(root)
    records = []
    for name in CASES:
        source = args.свідки.resolve() / (name + ".sens")
        expected_path = args.свідки.resolve() / (name + ".expected.sens")
        demand(source.is_file() and expected_path.is_file(), "відсутній фізичний свідок: " + name)
        expected = expected_path.read_bytes()
        demand(bool(expected), "порожня фізична відповідь: " + name)
        bit = call([str(args.читач.resolve()), "--view", str(expected_path)],
                   cwd=root).strip()
        demand(bit in (b"0", b"1"), "не D1 відповідь для: " + name)
        call([str(args.оракул.resolve()), str(source)], cwd=root, expected=bit+b"\n")
        runtime = [str(args.виконавець.resolve()), "--виконати", str(source)]
        call(runtime, cwd=root, expected=bit+b"\n")
        elf = tmp / (name + ".elf")
        call([str(args.машина.resolve()), "--тотожність",
              str(root / "external/sens"), str(source), str(elf)], cwd=root)
        demand(elf.is_file() and os.access(elf, os.X_OK),
               "компілятор не створив ELF: " + name)
        call([str(elf)], cwd=root, expected=expected)
        records.append({
            "форма": name, "джерело_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "результат_sha256": hashlib.sha256(expected).hexdigest(),
            "elf_sha256": hashlib.sha256(elf.read_bytes()).hexdigest(),
            "elf_байтів": elf.stat().st_size, "elf": elf,
            "expected": expected, "runtime_expected": bit+b"\n",
            "runtime": runtime,
        })
    return records


def energy_sample(args: argparse.Namespace, mode: str,
                  rec: dict, duration_idle: float) -> dict:
    root = args.корінь.resolve()
    sensor = str(args.rapl.resolve())
    source = str(args.живлення.resolve())
    with tempfile.TemporaryDirectory(prefix="sens-rapl-") as folder:
        tmp = Path(folder)
        t0 = time.monotonic_ns()
        before = call([sensor, "--знімок", source], cwd=root)
        (tmp/"до.tsv").write_bytes(before)
        if mode == "idle":
            time.sleep(duration_idle)
            iterations = 0
        else:
            cmd = [str(rec["elf"])] if mode == "готовий_ELF" else rec["runtime"]
            response = rec["expected"] if mode == "готовий_ELF" else rec["runtime_expected"]
            for _ in range(args.повторів):
                call(cmd, cwd=root, expected=response)
            iterations = args.повторів
        after = call([sensor, "--знімок", source], cwd=root)
        t1 = time.monotonic_ns()
        (tmp/"після.tsv").write_bytes(after)
        us = (t1-t0+999)//1000  # верхня межа, включно з читанням датчиків
        delta = call([sensor, "--різниця", str(tmp/"до.tsv"),
                      str(tmp/"після.tsv"), str(us), str(args.макс_ват)], cwd=root)
        zones = parse_rapl(delta, us, args.макс_ват)
        return {"режим": mode, "форма": rec["форма"], "повторів": iterations,
                "elapsed_us": us, "zones_uj": zones, "сирий_рапл": delta.decode("utf-8")}


def measure(args: argparse.Namespace, records: list[dict]) -> dict:
    demand(args.блоки >= 20 and 1 <= args.повторів <= 5000,
           "вимір потребує >=20 блоків і 1..5000 виконань у блоці")
    demand(1 <= args.макс_ват <= 10000, "потрібна фізична верхня межа Вт")
    demand(args.rapl is not None and args.живлення is not None,
           "ENERGY_NOT_MEASURED: не задано справжній лічильник RAPL")
    demand(args.живлення.is_dir(), "ENERGY_NOT_MEASURED: датчиків RAPL немає")
    demand(args.rapl.is_file() and os.access(args.rapl, os.X_OK),
           "ENERGY_NOT_MEASURED: немає зібраного sensrapl")
    first = call([str(args.rapl.resolve()), "--знімок",
                  str(args.живлення.resolve())], cwd=args.корінь.resolve())
    demand(first.startswith(b"RAPL1\n"), "ENERGY_NOT_MEASURED: некоректний датчик")
    rng = random.Random(346)
    rows = []
    for block in range(args.блоки):
        for record in records:
            order = list(CHANNELS)
            rng.shuffle(order)
            elapsed = []
            for mode in order:
                # Idle тримаємо в тій самій тривалості, що й виміряні пари;
                # це НЕ дозволяє відняти background як енергію процесу.
                idle_s = statistics.median(elapsed) / 1e6 if elapsed else 0.5
                row = energy_sample(args, mode, record, idle_s)
                row["блок"] = block
                rows.append(row)
                if mode != "idle":
                    elapsed.append(row["elapsed_us"])
    demand(len(rows) == args.блоки*len(CASES)*len(CHANNELS), "загублено RAPL-блок")
    zone_keys = [set(row["zones_uj"]) for row in rows]
    demand(all(keys == zone_keys[0] for keys in zone_keys),
           "під час вимірів змінився перелік RAPL зон")
    return {
        "схема": "sens-готовий-elf-енергія/1",
        "дата_utc": datetime.now(timezone.utc).isoformat(),
        "SENS_pin": PIN, "контракт": "12.0",
        "ос": platform.platform(), "машина": platform.processor(),
        "метод": "RAPL hardware-zone energy, cold separate process, ELF vs FPC; "
                 "excluded FPC compilation; includes startup, decoding in FPC, "
                 "sensor overhead and desktop background; never subtract idle; "
                 "no per-process attribution and no cross-language ranking",
        "блоки": args.блоки, "виконань_у_блоці": args.повторів,
        "макс_ват": args.макс_ват,
        "артефакти": [{k:v for k,v in rec.items()
                      if k in ("форма", "джерело_sha256", "результат_sha256",
                               "elf_sha256", "elf_байтів")} for rec in records],
        "сирі_виміри": rows,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="SENS: готовий ELF64 vs фізичний FPC та RAPL")
    parser.add_argument("--самотест", action="store_true")
    parser.add_argument("--вимір", action="store_true")
    parser.add_argument("--корінь", type=Path)
    parser.add_argument("--свідки", type=Path)
    parser.add_argument("--машина", type=Path)
    parser.add_argument("--виконавець", type=Path)
    parser.add_argument("--читач", type=Path)
    parser.add_argument("--оракул", type=Path)
    parser.add_argument("--rapl", type=Path)
    parser.add_argument("--живлення", type=Path,
                        default=Path("/sys/devices/virtual/powercap/intel-rapl"))
    parser.add_argument("--вихід", type=Path)
    parser.add_argument("--блоки", type=int, default=20)
    parser.add_argument("--повторів", type=int, default=50)
    parser.add_argument("--макс-ват", dest="макс_ват", type=int, default=1000)
    a = parser.parse_args()
    if a.самотест:
        print("ЕЛФ-ЕНЕРГІЯ-САМОТЕСТ-ГАРАЗД негативів=", negative_tests())
        return
    demand(all(getattr(a, x) is not None for x in
               ("корінь", "свідки", "машина", "виконавець", "читач", "оракул")),
           "не задано інструменти/фізичні свідки")
    with tempfile.TemporaryDirectory(prefix="sens-compiled-energy-") as folder:
        records = preflight(a, Path(folder))
        print("ЕЛФ-ЕНЕРГІЯ-ПЕРЕВІРКА-ГАРАЗД форм=4 ELF=справжній "
              "виконавець=FPC оракул=pinned-SENS", flush=True)
        if a.вимір:
            demand(a.вихід is not None, "для реальних даних потрібен --вихід")
            demand(not a.вихід.exists(), "заборонений перезапис звіту")
            report = measure(a, records)
            # Фінальна публікація тільки після всіх фізичних RAPL + byte-exact.
            with a.вихід.open("x", encoding="utf-8") as f:
                json.dump(report, f, ensure_ascii=False, indent=2)
                f.write("\n")
            print("ЕЛФ-ЕНЕРГІЯ-ВИМІР-ГАРАЗД реальний-RAPL=так блоків=",
                  a.блоки, "сирі_зони_мкДж=збережено", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as err:
        print("ЕЛФ-ЕНЕРГІЯ-БЛОК: " + str(err), file=sys.stderr)
        sys.exit(2)
