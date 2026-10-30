#!/usr/bin/env python3
"""G6: незалежний аналіз сирих монотонних наносекунд FPC етапів.

Точні фізичні .sens виміряні у ПОСТІЙНОМУ процесі, але наперед
викликані stage-проходи прогрівають кеш ОС. Це НЕ cold-start, НЕ
міжпрограмний кеш ELF, НЕ скорочення проходів і НЕ вимір енергії.
"""
from __future__ import annotations

import collections
import json
import os
from pathlib import Path
import statistics
import sys

FIELDS = ("decode_t5m_with_locations", "load_pinned_domains",
          "build_wideir", "verify_wideir", "compile_verified_elf")
SCHEMA = "sens-wide-first-stages/1"


def parse(text: str) -> dict:
    by_name: dict[str, list[dict[str, int]]] = collections.defaultdict(list)
    for line in text.splitlines():
        columns = line.split("\t")
        assert len(columns) == 8, f"пошкоджений TSV: {line[:100]!r}"
        name, round_s, *measurements = columns
        assert len(name) == 2 and name.isascii() and name.isdigit()
        assert 1 <= int(name) <= 16
        round_index = int(round_s)
        assert 1 <= round_index <= 3
        numbers = [int(x) for x in measurements]
        assert all(x > 0 for x in numbers), (name, numbers)
        record = {"round": round_index, **dict(zip(FIELDS, numbers[:5])),
                  "elf_bytes": numbers[5]}
        assert 120 < record["elf_bytes"] <= 1048576
        by_name[name].append(record)
    assert sorted(by_name) == [f"{i:02d}" for i in range(1, 17)]
    for name, records in by_name.items():
        assert sorted(x["round"] for x in records) == [1, 2, 3], name
        assert len({x["elf_bytes"] for x in records}) == 1
    stats = {}
    for field in FIELDS:
        raw = [rec[field] for recs in by_name.values() for rec in recs]
        assert len(raw) == 48
        stats[field] = {"raw_ns": raw, "median_ns": int(statistics.median(raw)),
                        "min_ns": min(raw), "max_ns": max(raw)}
    return {"schema": SCHEMA, "distinct_programs": 16,
            "rounds": 3, "raw": dict(sorted(by_name.items())),
            "stage_times_ns": stats,
            "compile_first_miss": "YES_NO_ELF_OUTPUT_CACHE",
            "file_cache_cold": "NOT_VERIFIED_PREWARMED_BY_STAGE_SAMPLES",
            "backend_only_ns": "NOT_ISOLATED",
            "independent_sens_oracle": "NOT_CHECKED_IN_THIS_PROFILE",
            "energy": "NOT_MEASURED",
            "performance_improvement": "NOT_CLAIMED"}


def selftest() -> None:
    row = "01\t1\t1\t2\t3\t4\t5\t200"
    valid = "\n".join(
        f"{i:02d}\t{r}\t1\t2\t3\t4\t5\t200"
        for r in range(1, 4) for i in range(1, 17)
    )
    result = parse(valid)
    assert result["stage_times_ns"]["compile_verified_elf"]["median_ns"] == 5
    for mutated in (valid.replace(row, "01\t1\t0\t2\t3\t4\t5\t200"),
                    valid.replace(row, "01\t1\t1\t2\t3\t4\t5\t100"),
                    valid.replace(row, "01\t1\t1\t2\t3\t4\t5"),
                    valid.replace(row, "01\t1\t1\t2\t3\t4\t5\t200\t7"),
                    valid.replace(row, "99\t1\t1\t2\t3\t4\t5\t200"),
                    valid.replace(row, "01\t2\t1\t2\t3\t4\t5\t200"),
                    "\n".join(valid.splitlines()[:-1])):
        try:
            parse(mutated)
        except (AssertionError, ValueError):
            pass
        else:
            raise AssertionError("спотворений профіль прийнято")
    print("ЕТАПИ-САМОПЕРЕВІРКА-ГАРАЗД негативів=7")


def main() -> None:
    if sys.argv[1:] == ["--самоперевірка"]:
        selftest()
        return
    assert len(sys.argv) == 2
    observed = parse(Path(sys.argv[1]).read_text(encoding="utf-8"))
    target = os.environ.get("SENS_STAGE_REPORT", "")
    if target:
        Path(target).write_text(json.dumps(observed, ensure_ascii=False, indent=2)
                                + "\n", encoding="utf-8")
    for field in FIELDS:
        print(f"ЕТАПИ-НС {field}={observed['stage_times_ns'][field]['median_ns']}")
    print("ЕТАПИ-ПРОЙДЕНО фізичних=16 повторів=3 raw=48 "
          "виконання-ELF=ОКРЕМИЙ-ТЕСТ oracle=NOT-CHECKED "
          "energy=NOT-MEASURED optimization=NOT-CLAIMED")


if __name__ == "__main__":
    main()
