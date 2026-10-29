#!/usr/bin/env python3
"""GЕ.7 — незалежний аудит ЗВІТУ RAPL скомпільованого SENS ELF64.

Не вимірює енергію і не засвідчує автентичності датчика. Перевіряє,
що опубліковані байти RAPL та всі записи експерименту самі собі не
суперечать; не виводить «джоулі процесу», рейтинги мов чи idle-різниці.
Схему видає вже наявний scripts/energy/compiled-elf.py (GЕ.6).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import sys
import tempfile
from pathlib import Path

PIN = "1f1bf676eeac605e065035d9dd2adaae807f1788"
CASES = ("тотожні-00", "тотожні-01", "тотожні-10", "тотожні-11")
CHANNELS = ("готовий_ELF", "фізичний_FPC", "idle")
SCHEMA = "sens-готовий-elf-енергія/1"
RAPL_KEY = re.compile(r"intel-rapl:[0-9]+(?:/intel-rapl:[0-9]+:[0-9]+)*\Z")
HASH = re.compile(r"[0-9a-f]{64}\Z")
FIELDS = {"режим", "форма", "повторів", "elapsed_us", "zones_uj",
          "сирий_рапл", "блок"}

def need(condition: bool, reason: str) -> None:
    if not condition:
        raise ValueError(reason)

def integer(value: object, low: int, high: int, label: str) -> int:
    need(type(value) is int and low <= value <= high, "неприпустиме число: " + label)
    return value

def duplicate_guard(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        need(key not in result, "дубльований ключ JSON: " + key)
        result[key] = value
    return result

def no_nonfinite(value: str) -> None:
    raise ValueError("нескінченне число у звіті: " + value)

def load_report(filename: Path) -> dict:
    size = filename.stat().st_size
    need(0 < size <= 16_000_000, "порожній чи завеликий JSON звіт")
    blob = filename.read_bytes()
    need(blob.endswith(b"\n"), "незавершений файл JSON")
    report = json.loads(blob.decode("utf-8", "strict"),
                        object_pairs_hook=duplicate_guard,
                        parse_constant=no_nonfinite)
    need(isinstance(report, dict), "звіт повинен бути об'єктом")
    return report

def decimal(raw: str, label: str) -> int:
    need(bool(re.fullmatch(r"(?:0|[1-9][0-9]*)", raw)), "неканонічний лічильник " + label)
    return int(raw)

def parse_rapl(raw: str, elapsed_us: int, watts: int) -> tuple[dict[str, int], dict[str, tuple[str, int]]]:
    """Один повністю перевірений RAPL-DELTA1. Кожен рядок = µJ, не Joule."""
    need(isinstance(raw, str) and raw.endswith("\n"), "RAPL без завершального LF")
    lines = raw.splitlines()
    need(2 <= len(lines) <= 257, "відсутній або завеликий набір RAPL зон")
    need(lines[0] == f"RAPL-DELTA1\telapsed_us={elapsed_us}\tmax_watts={watts}",
         "невідповідний заголовок RAPL/інтервал/верхня потужність")
    zones = {}
    identities = {}
    previous = ""
    package = False
    for line in lines[1:]:
        fields = line.split("\t")
        need(len(fields) == 6, "незавершений запис RAPL")
        key, label, sb, sa, sm, sd = fields
        need(bool(RAPL_KEY.fullmatch(key)) and key > previous,
             "дубльована, неканонічна чи неупорядкована зона RAPL")
        need(bool(re.fullmatch(r"[A-Za-z0-9_.+-]{1,80}", label)),
             "неканонічна назва RAPL зони")
        before, after, maximum, delta = (
            decimal(sb, "до"), decimal(sa, "після"),
            decimal(sm, "максимум"), decimal(sd, "різниця"))
        need(maximum > 0 and 0 <= before < maximum and
             0 <= after < maximum and 0 <= delta < maximum,
             "значення RAPL за фізичними межами")
        need((after - before) % maximum == delta,
             "неправильна фізична різниця/обертання RAPL")
        # 1 Вт * 1 мкс = 1 мкДж; обмежуємо можливість другого wrap.
        need(elapsed_us * watts < maximum,
             "двозначне обертання RAPL при заданому max_watts")
        if "/" not in key and label.startswith("package-"):
            package = True
        zones[key] = delta
        identities[key] = (label, maximum)
        previous = key
    need(package, "ENERGY_NOT_MEASURED: відсутня package-зона RAPL")
    return zones, identities

def audit(report: dict) -> dict:
    need(report.get("схема") == SCHEMA, "непідтримана схема енергозвіту")
    need(report.get("SENS_pin") == PIN and report.get("контракт") == "12.0",
         "не pinned SENS Contract 12.0")
    for key in ("ос", "машина", "дата_utc"):
        need(isinstance(report.get(key), str) and bool(report[key].strip()),
             "відсутній provenance: " + key)
    method = report.get("метод")
    need(isinstance(method, str) and
         all(token in method for token in
             ("RAPL hardware-zone energy", "excluded FPC compilation",
              "no per-process attribution", "no cross-language ranking")),
         "змінено фізичну межу інтерпретації RAPL")
    blocks = integer(report.get("блоки"), 30, 10000, "блоки >=30")
    repeats = integer(report.get("виконань_у_блоці"), 1, 5000, "виконань_у_блоці")
    watts = integer(report.get("макс_ват"), 1, 10000, "макс_ват")
    artifacts = report.get("артефакти")
    need(type(artifacts) is list and len(artifacts) == len(CASES),
         "потрібні рівно чотири фізичні артефакти")
    seen_forms = set()
    for entry in artifacts:
        need(isinstance(entry, dict) and set(entry) ==
             {"форма", "джерело_sha256", "результат_sha256", "elf_sha256", "elf_байтів"},
             "невірний фізичний паспорт ELF")
        name = entry["форма"]
        need(isinstance(name, str) and name in CASES and name not in seen_forms,
             "неправильна або повторна форма ELF")
        seen_forms.add(name)
        for key in ("джерело_sha256", "результат_sha256", "elf_sha256"):
            need(isinstance(entry[key], str) and bool(HASH.fullmatch(entry[key])),
                 "невалідний SHA256: " + key)
        integer(entry["elf_байтів"], 120, 1_000_000, "ELF_байтів")
    need(seen_forms == set(CASES), "бракує фізичних форм")
    rows = report.get("сирі_виміри")
    total = blocks * len(CASES) * len(CHANNELS)
    need(type(rows) is list and len(rows) == total,
         "пропущені/зайві сирі RAPL виміри")
    seen = set()
    zone_scheme = None
    samples = {}
    for index, row in enumerate(rows):
        need(isinstance(row, dict) and set(row) == FIELDS,
             f"неповна схема RAPL рядка {index}")
        block = integer(row["блок"], 0, blocks - 1, "блок")
        mode, form = row["режим"], row["форма"]
        need(isinstance(mode, str) and mode in CHANNELS and
             isinstance(form, str) and form in CASES,
             "невідома форма/канал")
        key = (block, form, mode)
        need(key not in seen, "повтор фізичного виміру замість відсутнього")
        seen.add(key)
        count = integer(row["повторів"], 0, repeats, "повторів")
        need(count == (0 if mode == "idle" else repeats),
             "неоднаковий обсяг корисної роботи чи підроблений idle")
        elapsed = integer(row["elapsed_us"], 1, 10**12, "elapsed_us")
        zones, identities = parse_rapl(row["сирий_рапл"], elapsed, watts)
        need(type(row["zones_uj"]) is dict and row["zones_uj"] == zones and
             all(type(value) is int for value in row["zones_uj"].values()),
             "числа в zones_uj не тотожні сирому RAPL")
        if zone_scheme is None:
            zone_scheme = identities
        else:
            need(identities == zone_scheme,
                 "під час вимірів змінилися фізичні зони/діапазони")
        samples[key] = (elapsed, zones)
    need(len(seen) == total, "неповна матриця вимірів")
    # Виводимо лише невідняті package µJ, окремо за формою/каналом.
    # Вкладені core/dram НЕ додаємо до package; віднімання idle
    # за різних тривалостей не є енергією процесу.
    packages = sorted(key for key, (label, _) in zone_scheme.items()
                      if "/" not in key and label.startswith("package-"))
    need(bool(packages), "відсутній фізичний package")
    result = {}
    for form in CASES:
        values = {}
        for mode in CHANNELS:
            selected = [samples[(block, form, mode)] for block in range(blocks)]
            values[mode] = {
                "повторів": blocks,
                "медіана_часу_мкс": statistics.median(x[0] for x in selected),
                "package_медіана_сирих_мкДж": {
                    key: statistics.median(x[1][key] for x in selected)
                    for key in packages
                }
            }
        result[form] = values
    return {
        "схема": "sens-elf-rapl-audit/1",
        "статус": "УЗГОДЖЕНО_СИРУ_СХЕМУ_НЕ_АВТЕНТИЧНІСТЬ_ДАТЧИКА",
        "pinned_SENS_SHA": PIN, "форм": 4, "блоків": blocks,
        "записів": total, "зон": len(zone_scheme),
        "енергія": "НЕ_ЕНЕРГІЯ_ПРОЦЕСУ_НЕ_РЕЙТИНГ_МОВ",
        "метод": "Тільки сирі µJ апаратних package; без idle subtraction, "
                 "без складання вкладених зон, без тверджень про економію.",
        "результати": result,
    }

def publish(path: Path, result: dict) -> None:
    need(not path.exists() and not path.is_symlink(),
         "аудит не може перезаписувати наявний звіт")
    data = (json.dumps(result, ensure_ascii=False, indent=2,
                       allow_nan=False) + "\n").encode("utf-8")
    parent = path.parent
    need(parent.is_dir(), "немає теки звіту")
    tmp_name = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".rapl-audit-", dir=parent,
                                         delete=False) as file:
            tmp_name = file.name
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
        os.link(tmp_name, path)  # атомарний no-clobber, без os.replace
    finally:
        if tmp_name is not None:
            os.unlink(tmp_name)

def main() -> None:
    parser = argparse.ArgumentParser(description="Аудит сирих фізичних RAPL вимірів SENS ELF64")
    parser.add_argument("--звіт", required=True, type=Path)
    parser.add_argument("--вихід", required=True, type=Path)
    args = parser.parse_args()
    report = load_report(args.звіт)
    result = audit(report)
    publish(args.вихід, result)
    print(f"ЕНЕРГІЯ-ELF-АУДИТ-ГАРАЗД записів={result['записів']} "
          f"блоків={result['блоків']} зон={result['зон']} "
          "енергія_процесу=НЕ_ВИМІРЯНО датчик=НЕ_АВТЕНТИФІКОВАНО")

if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, UnicodeError, json.JSONDecodeError) as exc:
        print("ЕНЕРГІЯ-ELF-АУДИТ-ВІДМОВА: " + str(exc), file=sys.stderr)
        sys.exit(2)

# Типи: report — borrowed JSON dict у пам'яті, rows — повні сирі
# рядки апаратного зонального energy_uj. Ні фізичне D12+, ні D7 текст
# не стають джоулями. publish володіє лише тимчасовим файлом, який
# видаляється навіть після відмови. 5 питань:
# 1. Чому нормалізація package на число запусків тут заборонена?
# 2. Чому 30 блоків, а не 30 випадкових процесів?
# 3. Що виключає другий wrap у RAPL-DELTA1?
# 4. Чому два однакових SHA256-тексти не доводять автентичності ELF?
# 5. Чому графічний Lazarus має отримувати лише вже перевірений JSON?
