#!/usr/bin/env python3
"""G6.188 — зберегти сирі наносекунди FPC етапів без заяви speedup.

Це мікропрофіль на реальних canonical .sens, НЕ elapsed host process,
і НЕ заміна незалежного SENS oracle чи вимірів джоулів.
"""
from __future__ import annotations

import csv
import json
import statistics
import sys
from pathlib import Path

FIELDS = (
    "first_decode_ns",
    "canonical_encode_ns",
    "pinned_domains_ns",
    "first_wideir_ns",
    "first_guard_ns",
    "redecode_ns",
    "rebuild_wideir_ns",
    "reverify_guard_ns",
)
PIN = "1f1bf676eeac605e065035d9dd2adaae807f1788"


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("потрібні raw.tsv та вихідний звіт.json")
    table = Path(sys.argv[1])
    dest = Path(sys.argv[2])
    with table.open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        assert set(reader.fieldnames or ()) == (
            set(FIELDS) | {"trial", "id", "bytes"}
        ), f"неправильні колонки: {reader.fieldnames}"
        raw = list(reader)
    assert len(raw) == 48, f"має бути 3×16 фізичних вимірів: {len(raw)}"
    actual: dict[tuple[int, str], dict[str, int | str]] = {}
    physical_sizes: dict[str, int] = {}
    for row in raw:
        trial = int(row["trial"])
        name = row["id"]
        size = int(row["bytes"])
        assert trial in (1, 2, 3) and name in {
            f"{i:02d}" for i in range(1, 17)
        } and size > 0
        key = (trial, name)
        assert key not in actual, f"повторена комбінація {key}"
        if name in physical_sizes:
            assert physical_sizes[name] == size, "фізичний свідок змінився"
        else:
            physical_sizes[name] = size
        sample: dict[str, int | str] = {
            "trial": trial,
            "id": name,
            "physical_bytes": size,
        }
        for field in FIELDS:
            val = int(row[field])
            assert 0 < val < 10**12, (key, field, val)
            sample[field] = val
        actual[key] = sample
    for trial in (1, 2, 3):
        assert {name for r, name in actual if r == trial} == {
            f"{i:02d}" for i in range(1, 17)
        }
    assert len(physical_sizes) == 16
    samples = [actual[key] for key in sorted(actual)]
    medians = {
        field: int(statistics.median(int(item[field]) for item in samples))
        for field in FIELDS
    }
    report = {
        "schema": "sens-g6-188-stage-only-fpc-nanoseconds/1",
        "pinned_sens": PIN,
        "distinct_physical_programs": 16,
        "rounds": 3,
        "sample_count": len(samples),
        "order": "1..16 / 16..1 / 1..16",
        "timing": "CLOCK_MONOTONIC nanos, within same FPC process",
        "scope": "independent decode/encode, pinned D1-D10, "
                 "WideIR and structural guard; second decode/IR/guard "
                 "simulates duplicate passes but is not a full backend",
        "measurements": {
            "raw_stage_ns": samples,
            "median_stage_ns": medians,
        },
        "known_nonclaims": {
            "production_end_to_end_speedup": "NOT_MEASURED",
            "cold_process_startup": "NOT_MEASURED",
            "cached_hit": "NOT_MEASURED",
            "backend_codegen": "NOT_MEASURED",
            "energy": "NOT_MEASURED",
            "new_semantic_oracle": "NOT_CHECKED",
        },
    }
    dest.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8")
    print("ЕТАПИ-T5M-WIDEIR-OK distinct=16 rounds=3 samples=48 "
          "negatives=2 exact-ir=48 pinned-reloaded=48")
    for field in FIELDS:
        print(f"ЕТАП-МЕДІАНА-НС {field}={medians[field]}")
    print("ПРОФІЛЬ-ОБМЕЖЕННЯ speedup=NOT_MEASURED "
          "oracle=NOT_CHECKED energy=NOT_MEASURED")


if __name__ == "__main__":
    main()
