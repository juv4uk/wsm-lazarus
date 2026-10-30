#!/usr/bin/env python3
"""G6 / #848: незалежний host-wall профіль окремих FPC проходів.

Це НЕ профіль загальної компіляції та НЕ перший cached-hit.
Він вимірює повні окремі процеси, тому старт/читання fixtures
є складником wall_ns. Не складати тривалості й не приписувати speedup.
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

MODES = ("pinned", "decode", "locations", "wideir", "guard")
ROUNDS = 3
MARKER = re.compile(
    r"^PROFILE_STAGE_OK mode=(pinned|decode|locations|wideir|guard)"
    r" forms=(\d+) calls=(\d+) witness=(\d+) elapsed_ms=(\d+)$"
)


def execute(executable: Path, mode: str, fixture_dir: Path, root: Path):
    started = time.perf_counter_ns()
    result = subprocess.run(
        [str(executable), mode, str(fixture_dir)],
        cwd=root, capture_output=True, timeout=75, check=False,
    )
    elapsed = time.perf_counter_ns() - started
    if result.returncode != 0:
        raise AssertionError(
            f"{mode}: rc={result.returncode} "
            f"stderr={result.stderr[-1000:]!r}"
        )
    stdout = result.stdout.decode("utf-8", errors="strict").strip()
    match = MARKER.fullmatch(stdout)
    assert match, (mode, stdout[-1000:], result.stderr[-1000:])
    assert match.group(1) == mode
    forms, calls, witness, internal_ms = map(int, match.groups()[1:])
    assert forms == 16 and calls == (16 if mode == "pinned" else 1024)
    assert witness > 0 and internal_ms >= 0
    return elapsed, internal_ms


def expect_rejected(executable: Path, fixture_dir: Path, root: Path):
    call = subprocess.run(
        [str(executable), "decode", str(fixture_dir)],
        cwd=root, capture_output=True, timeout=20, check=False,
    )
    assert call.returncode != 0, "некоректний фізичний вхід прийнято"
    assert b"PROFILE_STAGE_OK" not in call.stdout
    return call.returncode


def main():
    assert len(sys.argv) == 4, "потрібні <FPC exe> <16 fixture dir> <JSON path>"
    exe = Path(sys.argv[1]).resolve()
    folder = Path(sys.argv[2]).resolve()
    report_path = Path(sys.argv[3]).resolve()
    root = Path(__file__).resolve().parent.parent
    assert exe.is_file() and folder.is_dir()
    forms = [(folder / f"{n:02d}.sens").read_bytes() for n in range(1, 17)]
    assert all(forms) and len(set(forms)) == 16, "потрібні 16 РІЗНИХ .sens"

    # Два справжні негативи для standalone FPC допуску: 0 bytes,
    # а також недопустимий base-3 фізичний байт FF.
    negatives = []
    with tempfile.TemporaryDirectory(prefix="sens-etapy-neg-") as tmp:
        invalid = Path(tmp)
        for n in range(1, 17):
            shutil.copyfile(folder / f"{n:02d}.sens", invalid / f"{n:02d}.sens")
        for bad in (b"", b"\xff"):
            (invalid / "01.sens").write_bytes(bad)
            negatives.append(expect_rejected(exe, invalid, root))

    raw = {mode: [] for mode in MODES}
    internal = {mode: [] for mode in MODES}
    for round_id in range(ROUNDS):
        # Збалансована ротація, щоб не порівнювати лише перший cold-run.
        order = MODES[round_id:] + MODES[:round_id]
        for mode in order:
            wall_ns, stage_ms = execute(exe, mode, folder, root)
            raw[mode].append(wall_ns)
            internal[mode].append(stage_ms)

    median_ns = {mode: sorted(raw[mode])[1] for mode in MODES}
    report = {
        "schema": "sens-g6-once-ir-stage-profile/1",
        "physical_forms": 16,
        "rounds": ROUNDS,
        "negative_rejections": negatives,
        "repetitions_per_form": {"pinned": 1, "decode": 64,
                                 "locations": 64, "wideir": 64, "guard": 64},
        "raw_host_wall_ns": raw,
        "internal_elapsed_ms": internal,
        "median_host_wall_ns": median_ns,
        "scope": "SEPARATE_STAGE_PROCESS_WITH_STARTUP_AND_FIXTURES",
        "end_to_end_first_compile_speedup": "NOT_MEASURED",
        "independent_sens_repl_oracle": "NOT_RUN",
        "energy": "NOT_MEASURED",
        "note": "Не підсумовувати stage-times: wideir включає decoder."
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print("ПРОФІЛЬ-ЕТАПІВ-ПРОЙДЕНО forms=16 rounds=3 negatives=2")
    for mode in MODES:
        print(f"ПРОФІЛЬ-ЕТАП mode={mode} host_median_ns={median_ns[mode]}"
              f" internal_ms={internal[mode]}")
    print("ПРОФІЛЬ-ОБМЕЖЕННЯ end_to_end_speedup=NOT_MEASURED"
          " oracle=NOT_RUN energy=NOT_MEASURED")


if __name__ == "__main__":
    main()
