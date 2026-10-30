#!/usr/bin/env python3
# G1.52: безколізійні D7/v2 поверхні та фізичний FPC T5M.
# Це перевірка кодування, не новий закон, не evaluator і не REPL.
from __future__ import annotations

import argparse
import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path

PIN = "2c498b35af53c085450eac6f51b87facf7f9aa47"
GLYPH_COLUMNS = ("ascii", "uk", "san")


class D7Error(ValueError):
    pass


def require(ok: bool, message: str) -> None:
    if not ok:
        raise D7Error(message)


def admit_table(data: object) -> tuple[list[dict], dict[str, dict[str, str]]]:
    """Borrowed JSON -> owned W7→glyph rows and glyph→exact bits indexes.

    D7 is TEXT/DATA ONLY. No semantic dispatch; no Unicode normalization.
    The iast field is a human annotation, deliberately NOT a reversible codec.
    """
    require(isinstance(data, dict), "корінь D7 не є об'єктом")
    require(data.get("schema") == "sens.d7.keyboard/v2", "неправильна схема D7")
    require(data.get("status") == "owner-ratified", "D7 не ратифіковано")
    require(type(data.get("width")) is int and data["width"] == 7, "D7 не W7")
    require(type(data.get("capacity")) is int and data["capacity"] == 128,
            "хибна місткість D7")
    require(type(data.get("occupancy")) is int and data["occupancy"] == 128,
            "неповний D7")
    rows = data.get("table")
    require(isinstance(rows, list) and len(rows) == 128,
            "фізична таблиця D7 не має 128 рядків")
    reverse: dict[str, dict[str, str]] = {key: {} for key in GLYPH_COLUMNS}
    for index, row in enumerate(rows):
        require(isinstance(row, dict), f"рядок {index} не об'єкт")
        bits = format(index, "07b")
        require(row.get("bits") == bits,
                f"рядок {index}: пропущена/переставлена точна W7-координата")
        require(row.get("ascii") == chr(index),
                f"рядок {index}: англійська ASCII клавіша не відповідає W7")
        for column in GLYPH_COLUMNS:
            glyph = row.get(column)
            require(isinstance(glyph, str) and len(glyph) == 1,
                    f"рядок {index}: {column} — не один Unicode scalar")
            require(glyph not in reverse[column],
                    f"колізія {column}: {reverse[column].get(glyph)} і {bits}")
            reverse[column][glyph] = bits
    for column in GLYPH_COLUMNS:
        require(len(reverse[column]) == 128,
                f"неповна зворотна D7 {column} таблиця")
        text = "".join(row[column] for row in rows)
        encoded = "".join(reverse[column][glyph] for glyph in text)
        require(encoded == "".join(row["bits"] for row in rows),
                f"зворотне W7 кодування {column} змінило біти")
        decoded = "".join(rows[int(encoded[i:i+7], 2)][column]
                          for i in range(0, len(encoded), 7))
        require(decoded == text, f"пряме W7 кодування {column} змінило знаки")
    return rows, reverse


def check_negative_controls(data: dict) -> int:
    """Owned deep copies — оригінальний ратифікований JSON незмінний."""
    mutations = []

    duplicate_uk = copy.deepcopy(data)
    duplicate_uk["table"][42]["uk"] = duplicate_uk["table"][41]["uk"]
    mutations.append(("колізія ук", duplicate_uk))

    duplicate_san = copy.deepcopy(data)
    duplicate_san["table"][70]["san"] = duplicate_san["table"][69]["san"]
    mutations.append(("колізія san", duplicate_san))

    missing = copy.deepcopy(data)
    missing["table"].pop()
    mutations.append(("зникла W7 координата", missing))

    wrong_bits = copy.deepcopy(data)
    wrong_bits["table"][127]["bits"] = "1111110"
    mutations.append(("підміна exact bits", wrong_bits))

    multi = copy.deepcopy(data)
    multi["table"][43]["san"] += "क"
    mutations.append(("неодносимвольна san клітинка", multi))

    wrong_ascii = copy.deepcopy(data)
    wrong_ascii["table"][65]["ascii"] = "a"
    mutations.append(("переставлена ASCII клавіша", wrong_ascii))

    for name, tampered in mutations:
        try:
            admit_table(tampered)
        except D7Error:
            continue
        raise D7Error(f"негативний контроль прийняв: {name}")
    return len(mutations)


def cli(cli_path: Path, option: str, input_path: Path) -> subprocess.CompletedProcess:
    return subprocess.run([str(cli_path), option, str(input_path)],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=20, check=False)


def physical_round_trip(cli_path: Path, bits: list[str],
                        workspace: Path, index: int) -> None:
    """Owned temp input + packed output; no text projection in machine call."""
    words_path = workspace / "слова.txt"
    sens_path = workspace / "доказ.sens"
    expected = (" ".join(bits) + "\n").encode("ascii")
    words_path.write_bytes(expected)
    packed = cli(cli_path, "--pack-words", words_path)
    require(packed.returncode == 0 and packed.stdout and not packed.stderr,
            f"FPC не спакував фізичний D7 приклад {index}: "
            f"{packed.stderr.decode('utf-8', 'replace')}")
    sens_path.write_bytes(packed.stdout)
    view = cli(cli_path, "--view", sens_path)
    require(view.returncode == 0 and not view.stderr and view.stdout == expected,
            f"FPC змінив exact W7 при відновленні прикладу {index}")


def check_physical(cli_path: Path, rows: list[dict]) -> int:
    require(cli_path.is_file(), "немає зібраного FPC senst5m")
    with tempfile.TemporaryDirectory(prefix="sens-d7-v2-") as temp:
        root = Path(temp)
        # Окрема фізична перевірка КОЖНОГО з 128 W7; без ANSI/UTF8 конверсії.
        for i, row in enumerate(rows):
            physical_round_trip(cli_path, [row["bits"]], root, i)
        # Усі 128 різної ширини? Ні: рівно W7, у порядку pinned файлу.
        physical_round_trip(cli_path, [r["bits"] for r in rows], root, 128)
        bad_words = root / "недійсні-слова.txt"
        bad_words.write_bytes(b"0000000 0000002\n")
        invalid = cli(cli_path, "--pack-words", bad_words)
        require(invalid.returncode != 0 and not invalid.stdout
                and b"SENST5M-FAIL" in invalid.stderr,
                "FPC пропустив небінарну W7 координату / частковий stdout")
    return 129


def main() -> int:
    parser = argparse.ArgumentParser(description="D7/v2: pinned взаємна однозначність + FPC")
    parser.add_argument("--json", type=Path, required=True,
                        help="knowledge/d7-keyboard-v2-ratified.json з pinned SENS")
    parser.add_argument("--cli", type=Path, required=True,
                        help="реально зібраний Free Pascal senst5m")
    args = parser.parse_args()
    try:
        data = json.loads(args.json.read_text(encoding="utf-8"))
        rows, _ = admit_table(data)
        negative_count = check_negative_controls(data)
        round_trips = check_physical(args.cli.resolve(), rows)
        print(f"Д7-БІЄКЦІЯ-ГАРАЗД pinned={PIN} W7=128 "
              f"зворотні=ascii,uk,san негативи={negative_count} "
              f"FPC-фізичних={round_trips} несемантичне=так")
        return 0
    except (D7Error, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"Д7-БІЄКЦІЯ-ВІДМОВА: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
