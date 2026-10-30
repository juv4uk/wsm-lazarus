#!/usr/bin/env python3
"""GЕ.8: справжній RAPL для уже доведених ELF SENS/C/Rust/FPC.

Ніякого компілятора, власних законів або синтетичної енергії.
Вхід: готовий G6.64 JSON+16 ELF і pinned фізичні свідки.
Вихід: тільки фактичні hardware-zone RAPL дельти після 30+ блоків.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import re
import runpy
import statistics
import subprocess
import sys
import tempfile
import time

PIN = "2c498b35af53c085450eac6f51b87facf7f9aa47"
CASES = ("тотожні-00", "тотожні-01", "тотожні-10", "тотожні-11")
LANGS = ("sens-elf", "c-gcc", "rust", "free-pascal")
HERE = Path(__file__).resolve().parent
# Строгий RAPL-DELTA1 parser повторно використовує чинний GЕ.6, а не копіюється.
RAPL_PARSER = runpy.run_path(str(HERE / "compiled-elf.py"))["parse_rapl"]


def require(ok: bool, reason: str) -> None:
    if not ok:
        raise ValueError(reason)


def _json_unique_keys(pairs: list[tuple[str, object]]) -> dict:
    """Не допускати прихованого перезапису ELF-паспорта навіть у вкладеному JSON."""
    result = {}
    for key, value in pairs:
        require(key not in result, "дубльований ключ JSON: " + key)
        result[key] = value
    return result


def _json_nonfinite(value: str) -> None:
    raise ValueError("неканонічне нечислове значення JSON: " + value)


def load_evidence_json(path: Path) -> dict:
    """Host-допуск чужих JSON свідків; не джерело мовної семантики SENS.

    1) Чому перезапис однакового ключа порушує довіру до SHA256 ELF?
    2) Навіщо обмежувати файл до читання й перевіряти розмір ще раз?
    3) Чому NaN/Infinity не можуть бути виміряними фізичними джоулями?
    4) Де окремо перевіряють домени та фізичні свідки .sens?
    """
    require(path.is_file() and not path.is_symlink(),
            "JSON-доказ відсутній або є символьним посиланням")
    size = path.stat().st_size
    require(0 < size <= 16_000_000, "порожній або завеликий JSON-доказ")
    raw = path.read_bytes()
    require(0 < len(raw) <= 16_000_000,
            "JSON-доказ змінено або він завеликий")
    try:
        parsed = json.loads(raw.decode("utf-8", "strict"),
                            object_pairs_hook=_json_unique_keys,
                            parse_constant=_json_nonfinite)
    except UnicodeError as exc:
        raise ValueError("JSON-доказ не є точним UTF-8") from exc
    require(type(parsed) is dict, "корінь JSON-доказу має бути об'єктом")
    return parsed


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(argv: list[str], cwd: Path, wanted: bytes | None = None,
        timeout: int = 30) -> bytes:
    got = subprocess.run(argv, cwd=cwd, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, timeout=timeout, check=False)
    require(got.returncode == 0, "код виконання: " + str(got.returncode) +
            " команда=" + repr(argv) + " stderr=" + repr(got.stderr[:150]))
    require(not got.stderr, "непорожній stderr " + repr(got.stderr[:200]))
    if wanted is not None:
        require(got.stdout == wanted,
                "не точний фізичний T5M: " + repr(argv) +
                " expected=" + wanted.hex() + " actual=" + got.stdout[:64].hex())
    return got.stdout


def validate_manifest(data: object) -> dict:
    require(isinstance(data, dict), "маніфест не об'єкт")
    require(data.get("схема") == "sens-elf-c-rust-fpc-coldstart/1",
            "інша схема порівняння")
    require(data.get("pinned_SENS_SHA") == PIN, "інший SENS pin")
    require(data.get("енергія") == "ENERGY_NOT_MEASURED",
            "базовий стенд не повинен містити вигадані джоулі")
    required = {case + "/" + lang for case in CASES for lang in LANGS}
    items = data.get("виконувані")
    require(isinstance(items, dict) and set(items) == required,
            "не рівно 16 фізичних виконуваних програм")
    for name, item in items.items():
        require(isinstance(item, dict) and isinstance(item.get("sha256"), str)
                and re.fullmatch(r"[0-9a-f]{64}", item["sha256"]) is not None
                and type(item.get("ELF_байтів")) is int and item["ELF_байтів"] > 0,
                "відсутній точний ELF паспорт " + name)
    return items


def preflight(root: Path, report: Path, fixtures: Path) -> list[dict]:
    require(platform.system() == "Linux" and platform.machine() == "x86_64",
            "потрібний справжній Linux x86-64")
    root = root.resolve()
    require((root / "external/sens/contracts/language-contract-12.lisp").is_file(),
            "немає pinned SENS Contract 12")
    oracle_report = root / "build/m0.2/benchmark-native-d3/виміри.json"
    require(oracle_report.is_file(), "немає незалежного pinned SENS oracle")
    oracle = load_evidence_json(oracle_report)
    require(oracle.get("незалежний_SENS_SHA") == PIN and
            len(oracle.get("форми", [])) == 4,
            "не засвідчено чотири незалежні SENS форми")
    require(report.is_file() and not report.is_symlink(),
            "базовий JSON відсутній або є посиланням")
    data = load_evidence_json(report)
    items = validate_manifest(data)
    records: list[dict] = []
    seen = set()
    for case in CASES:
        source = fixtures / (case + ".sens")
        expected_file = fixtures / (case + ".expected.sens")
        require(source.is_file() and not source.is_symlink()
                and expected_file.is_file() and not expected_file.is_symlink(),
                "немає двійкового свідка " + case)
        wanted = expected_file.read_bytes()
        require(len(wanted) == 1, "потрібна точна однословна D1 T5M відповідь")
        for lang in LANGS:
            key = case + "/" + lang
            name = case + ("-sens.elf" if lang == "sens-elf" else "-" + lang)
            elf = report.parent / "bin" / name
            require(elf.is_file() and not elf.is_symlink() and os.access(elf, os.X_OK),
                    "відсутній/небезпечний ELF " + key)
            physical = elf.read_bytes()
            require(len(physical) == items[key]["ELF_байтів"] and
                    digest(physical) == items[key]["sha256"],
                    "порушено SHA256/довжину ELF " + key)
            run([str(elf.resolve())], cwd=root, wanted=wanted)
            require(key not in seen, "дублікат виконуваного ключа")
            seen.add(key)
            records.append({"випадок": case, "виконавець": lang,
                            "elf": elf.resolve(),
                            "wanted": wanted,
                            "elf_sha256": items[key]["sha256"],
                            "input_sha256": digest(source.read_bytes()),
                            "expected_sha256": digest(wanted)})
    require(len(records) == 16 and len(seen) == 16,
            "недостатній фізичний preflight")
    return records


def sample(root: Path, rapl: Path, sensor: Path, watts: int,
           executable: Path | None, wanted: bytes | None,
           repeats: int, idle_ms: int) -> dict:
    with tempfile.TemporaryDirectory(prefix="sens-compare-rapl-") as folder:
        temporary = Path(folder)
        # Включає overhead RAPL та cold-start; НЕ енергія процесу.
        start = time.monotonic_ns()
        before = run([str(rapl), "--знімок", str(sensor)], cwd=root)
        (temporary / "before.tsv").write_bytes(before)
        if executable is None:
            time.sleep(idle_ms / 1000)
        else:
            for _ in range(repeats):
                run([str(executable)], cwd=root, wanted=wanted, timeout=15)
        after = run([str(rapl), "--знімок", str(sensor)], cwd=root)
        stop = time.monotonic_ns()
        elapsed_us = (stop - start + 999) // 1000
        require(elapsed_us > 0, "ненадійний часовий інтервал RAPL")
        (temporary / "after.tsv").write_bytes(after)
        delta = run([str(rapl), "--різниця",
                     str(temporary / "before.tsv"),
                     str(temporary / "after.tsv"),
                     str(elapsed_us), str(watts)], cwd=root)
        zones = RAPL_PARSER(delta, elapsed_us, watts)
        return {"elapsed_us": elapsed_us, "zones_uj": zones,
                "сирий_RAPL_DELTA1": delta.decode("utf-8"),
                "виконань": repeats if executable else 0}


def publish(path: Path, value: dict) -> None:
    require(path.parent.is_dir() and not path.exists() and not path.is_symlink(),
            "результат уже існує або немає теки")
    value_text = json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8",
                dir=str(path.parent), prefix=".sens-rapl-", delete=False) as out:
            temp_name = Path(out.name)
            out.write(value_text)
            out.flush()
            os.fsync(out.fileno())
        os.link(temp_name, path)  # ніякого перезапису чужого звіту
    finally:
        if temp_name is not None:
            temp_name.unlink(missing_ok=True)


def measure(args: argparse.Namespace, records: list[dict]) -> dict:
    require(args.блоки >= 30 and 1 <= args.повторів <= 5000,
            "потрібні >=30 блоків та 1..5000 cold запусків у вибірці")
    require(1 <= args.макс_ват <= 10000 and 1 <= args.idle_ms <= 10000,
            "неприпустима потужність/idle")
    require(args.rapl is not None and args.живлення is not None,
            "ENERGY_NOT_MEASURED: немає вказаного RAPL")
    sensor = args.живлення.resolve()
    require(str(sensor).startswith("/sys/devices/virtual/powercap/") or
            str(sensor).startswith("/sys/class/powercap/"),
            "ENERGY_NOT_MEASURED: потрібна справжня Linux powercap зона")
    require(sensor.is_dir() and args.rapl.is_file() and
            os.access(args.rapl, os.X_OK),
            "ENERGY_NOT_MEASURED: немає доступного апаратного RAPL/CLI")
    first = run([str(args.rapl.resolve()), "--знімок", str(sensor)],
                cwd=args.корінь.resolve())
    require(first.startswith(b"RAPL1\n"),
            "ENERGY_NOT_MEASURED: датчик не видає RAPL1")
    seed = args.зерно
    rng = random.Random(seed)
    rows = []
    zone_keys = None
    for block in range(args.блоки):
        order = list(range(16)) + [-1]  # idle у кожному рандомізованому блоці
        rng.shuffle(order)
        for ordinal in order:
            record = records[ordinal] if ordinal >= 0 else None
            result = sample(args.корінь.resolve(), args.rapl.resolve(),
                            sensor, args.макс_ват,
                            record["elf"] if record else None,
                            record["wanted"] if record else None,
                            args.повторів, args.idle_ms)
            keys = set(result["zones_uj"])
            if zone_keys is None:
                zone_keys = keys
            require(keys == zone_keys and bool(keys),
                    "RAPL hardware zones змінилися між вибірками")
            result.update({"блок": block + 1,
                           "випадок": record["випадок"] if record else "idle",
                           "виконавець": record["виконавець"] if record else "idle"})
            rows.append(result)
    require(len(rows) == args.блоки * 17, "пропущено енергетичні виміри")
    return {
        "схема": "sens-4-elf-rapl/1", "status": "HARDWARE_RAPL_MEASURED",
        "SENS_pin": PIN, "метод": "cold process 4 D3:101 cases × SENS/C/Rust/FPC; "
                "RAPL hardware zone, sensor and startup overhead included; "
                "not individual process energy; no nested sum/idle subtraction/energy ranking",
        "блоки": args.блоки, "повторів": args.повторів,
        "idle_ms": args.idle_ms, "seed": seed, "макс_ват": args.макс_ват,
        "джерело_попереднього_звіту_sha256": digest(args.звіт.read_bytes()),
        "hardware": {"os": platform.platform(), "cpu": platform.processor(),
                     "cpu_count": os.cpu_count(), "powercap": str(sensor)},
        "виконувані": [{k: r[k] for k in ("випадок", "виконавець",
                         "elf_sha256", "input_sha256", "expected_sha256")}
                        for r in records],
        "сирі_виміри": rows,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Чесний RAPL для 16 готових SENS/C/Rust/FPC ELF64")
    ap.add_argument("--корінь", type=Path)
    ap.add_argument("--звіт", type=Path)
    ap.add_argument("--свідки", type=Path)
    ap.add_argument("--rapl", type=Path)
    ap.add_argument("--живлення", type=Path)
    ap.add_argument("--вихід", type=Path)
    ap.add_argument("--блоки", type=int, default=30)
    ap.add_argument("--повторів", type=int, default=30)
    ap.add_argument("--idle-ms", type=int, default=50)
    ap.add_argument("--макс-ват", dest="макс_ват", type=int, default=1000)
    ap.add_argument("--зерно", type=int, default=3468)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--перевірка", action="store_true")
    mode.add_argument("--вимір", action="store_true")
    args = ap.parse_args()
    try:
        require(args.корінь is not None and args.звіт is not None and
                args.свідки is not None, "потрібні шляхи pinned збірки/звіту/свідків")
        records = preflight(args.корінь, args.звіт, args.свідки)
        if args.перевірка:
            require(args.вихід is None, "preflight не публікує енерговимірів")
            print("ЧОТИРИ-ЕЛФ-ПЕРЕВІРКА-ГАРАЗД 16/16 exact-T5M "
                  "SHA256=так oracle=pinned-SENS energy=ENERGY_NOT_MEASURED")
            return
        require(args.вихід is not None, "ENERGY_NOT_MEASURED: не вказано вихід")
        require(not args.вихід.exists(), "ціль вже існує, no-clobber")
        result = measure(args, records)
        publish(args.вихід, result)
        print("ЧОТИРИ-ЕЛФ-RAPL-ГАРАЗД апаратні-зони=так блоків=" +
              str(args.блоки) + " програм=16")
    except (ValueError, OSError, subprocess.TimeoutExpired,
            json.JSONDecodeError) as exc:
        print("ЧОТИРИ-ЕЛФ-БЛОК: " + str(exc), file=sys.stderr)
        raise SystemExit(2)


if __name__ == "__main__":
    main()
