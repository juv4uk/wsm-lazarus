#!/usr/bin/env python3
# G6.59 — часові виміри вже виконуваного фізичного SENS, не нова семантика.
# Всі заміри — end-to-end wall-clock разом із запуском процесу; ніякого
# твердження про IPC, швидкість однієї машинної інструкції або JIT.
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import statistics
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

PIN = "1f1bf676eeac605e065035d9dd2adaae807f1788"
CASES = (
    "тотожні-00",
    "тотожні-01",
    "тотожні-10",
    "тотожні-11",
)
CHANNELS = ("компіляція_ELF", "готовий_ELF", "виконавець_FPC", "еталон_SENS")
TIMEOUT_SEC = 25


def require(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def invoke(argv: list[str], *, cwd: Path) -> tuple[int, bytes, bytes, int]:
    before = time.perf_counter_ns()
    completed = subprocess.run(
        argv, cwd=cwd, capture_output=True, timeout=TIMEOUT_SEC, check=False
    )
    elapsed = time.perf_counter_ns() - before
    return completed.returncode, completed.stdout, completed.stderr, elapsed


def checked(argv: list[str], *, cwd: Path, expected: bytes | None = None) -> int:
    code, actual, stderr, elapsed = invoke(argv, cwd=cwd)
    require(code == 0, "Ненульовий код: " + repr(argv) + " " + repr(stderr[:250]))
    require(not stderr, "Непорожній stderr: " + repr(argv) + " " + repr(stderr[:250]))
    if expected is not None:
        require(actual == expected, "Побайтова відповідь не збігається: " + repr(argv))
    return elapsed


def stats(ns: list[int]) -> dict[str, float | int]:
    require(len(ns) >= 3, "Недостатня кількість справжніх вимірів")
    values = sorted(ns)
    return {
        "повторів": len(values),
        "мін_мс": round(values[0] / 1e6, 3),
        "медіана_мс": round(statistics.median(values) / 1e6, 3),
        "р95_мс": round(values[math.ceil(0.95 * len(values)) - 1] / 1e6, 3),
        "макс_мс": round(values[-1] / 1e6, 3),
    }


def profile_cpu() -> str:
    path = Path("/proc/cpuinfo")
    if not path.exists():
        return platform.processor() or "невідомий"
    for line in path.read_text(errors="replace").splitlines():
        if line.startswith("model name"):
            return line.split(":", 1)[1].strip()
    return "невідомий"


def selfcheck() -> int:
    failures = 0
    for wanted, received in (
        (b"1\n", b"0\n"),
        (b"1\n", b"1\n0\n"),
        (b"1\n", b""),
        (b"\x01", b"1\n"),
    ):
        try:
            require(wanted == received, "Імітована помилкова відповідь")
        except ValueError:
            failures += 1
    require(failures == 4, "Негативні тести побайтового компаратора не відхилені")
    for bogus in ([], [1], [1, 2]):
        try:
            stats(bogus)
        except ValueError:
            failures += 1
    require(failures == 7, "Відхилення неповних вимірів не працює")
    return failures


def main() -> None:
    ap = argparse.ArgumentParser(description="Фізичний D3:101 — відтворюваний wall-clock")
    ap.add_argument("--корінь", type=Path, required=True)
    ap.add_argument("--свідки", type=Path, required=True)
    ap.add_argument("--машина", type=Path, required=True)
    ap.add_argument("--виконавець", type=Path, required=True)
    ap.add_argument("--читач", type=Path, required=True)
    ap.add_argument("--оракул", type=Path, required=True)
    ap.add_argument("--вихід", type=Path, required=True)
    ap.add_argument("--повтори", type=int, default=7)
    options = ap.parse_args()
    root = options.корінь.resolve()
    fixtures = options.свідки.resolve()
    out = options.вихід.resolve()
    machine = options.машина.resolve()
    evaluator = options.виконавець.resolve()
    viewer = options.читач.resolve()
    oracle = options.оракул.resolve()
    require(3 <= options.повтори <= 25, "Кількість повторів має бути від 3 до 25")
    require((root / "external/sens/contracts/language-contract-12.lisp").is_file(),
            "Немає ратифікованого контракту SENS 12.0")
    require((root / "sens-oracle").is_dir(), "Немає незалежного SENS")
    ref = subprocess.check_output(["git", "-C", str(root / "sens-oracle"),
                                   "rev-parse", "HEAD"], timeout=TIMEOUT_SEC).decode().strip()
    require(ref == PIN, "Незалежний upstream SHA не дорівнює pinned SENS")
    for path in (machine, evaluator, viewer, oracle):
        require(path.is_file() and os.access(path, os.X_OK), "Немає виконуваного бінарника: " + str(path))
    out.mkdir(parents=True, exist_ok=True)
    negative = selfcheck()
    report: dict[str, object] = {
        "схема": "sеns-нативні-виміри/1",
        "дата_utc": datetime.now(timezone.utc).isoformat(),
        "main_джерело": subprocess.check_output(["git", "rev-parse", "HEAD"],
                                                cwd=root, timeout=TIMEOUT_SEC).decode().strip(),
        "незалежний_SENS_SHA": PIN,
        "контракт": "12.0",
        "операція": "D3:101(D1,D1), точні фізичні packed T5M слова",
        "ос": platform.platform(),
        "процесор": profile_cpu(),
        "логічних_ядер": os.cpu_count(),
        "python": platform.python_version(),
        "повторів_на_форму": options.повтори,
        "прогрівань_на_форму": 1,
        "метод": "perf_counter_ns; новий процес кожного виклику, зовнішній wall-clock; "
                 "компіляція = запуск FPC CLI з pinned IR admission і запис ELF; "
                 "виконання = повторний запуск уже зібраного ELF; "
                 "FPC evaluator = запуск sensvykon; незалежний SENS = запуск CLI. "
                 "Виміри не ізолюють startup/FS cache, інтерпретатор Rust/Zig і x86-64 "
                 "мають різні витрати запуску; відносний speedup машинної інструкції НЕ доводиться.",
        "негативів_компаратора": negative,
        "форми": [],
    }
    with tempfile.TemporaryDirectory(prefix="sens-perf-") as scratch:
        tmp = Path(scratch)
        for label in CASES:
            source = fixtures / (label + ".sens")
            expected = (fixtures / (label + ".expected.sens")).read_bytes()
            require(source.is_file() and source.suffix == ".sens", "Немає фізичного джерела: " + label)
            before_sha = sha256(source)
            bit_word = checked([str(viewer), "--view", str(fixtures / (label + ".expected.sens"))], cwd=root)
            # Окрема перевірка фактичного decoder stdout; вимір читача не записуємо в метрики.
            code, bits_out, err, _ = invoke([str(viewer), "--view",
                                             str(fixtures / (label + ".expected.sens"))], cwd=root)
            require(code == 0 and not err and bits_out.strip() in (b"0", b"1"),
                    "Невідомий результат exact D1")
            bit = bits_out.strip()
            expected_oracle = bit + b"\n"
            expected_fpc = b"(" + bit + b")\n"
            source_path = str(source)
            oracle_cmd = [str(oracle), source_path]
            fpc_cmd = [str(evaluator), "--виконати", source_path]
            checked(oracle_cmd, cwd=root, expected=expected_oracle)
            checked(fpc_cmd, cwd=root, expected=expected_fpc)
            samples: dict[str, list[int]] = {name: [] for name in CHANNELS}
            generated = tmp / (label + "-перевірено.elf")
            print("ВИМІР-МАШИНИ: "+label, flush=True)
            for iteration in range(options.повтори + 1):
                current = tmp / (label + "-" + str(iteration) + ".elf")
                compile_cmd = [str(machine), "--тотожність",
                               str(root / "external/sens"), source_path, str(current)]
                elapsed = checked(compile_cmd, cwd=root)
                require(current.is_file() and os.access(current, os.X_OK),
                        "Нативний компілятор не опублікував виконуваний ELF")
                # Кожну компіляцію перевірено реальним виконанням ДО збереження числа.
                checked([str(current)], cwd=root, expected=expected)
                if iteration == 0:
                    generated = current
                else:
                    samples["компіляція_ELF"].append(elapsed)
            # Не перевимірюємо повторну компіляцію під час окремого запуску.
            for name, command, answer in (
                ("готовий_ELF", [str(generated)], expected),
                ("виконавець_FPC", fpc_cmd, expected_fpc),
                ("еталон_SENS", oracle_cmd, expected_oracle),
            ):
                for i in range(options.повтори + 1):
                    elapsed = checked(command, cwd=root, expected=answer)
                    if i:
                        samples[name].append(elapsed)
            require(sha256(source) == before_sha,
                    "Фізичне джерело було змінено під час замірів")
            report["форми"].append({
                "мітка": label,
                "джерело_SHA256": before_sha,
                "вхід_байтів": source.stat().st_size,
                "відповідь_SHA256": hashlib.sha256(expected).hexdigest(),
                "відповідь_домен": "D1",
                "часи": {key: stats(samples[key]) for key in CHANNELS},
            })
    require(len(report["форми"]) == 4, "Загублено одну з чотирьох форм")
    json_path = out / "виміри.json"
    json_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    md = [
        "# Відтворювані часові виміри фізичного D3:101",
        "",
        "Контракт: pinned SENS 12.0, SHA " + PIN + ".",
        "Дата UTC: " + str(report["дата_utc"]),
        "Середовище: " + str(report["ос"]) + "; CPU: " + str(report["процесор"]) + ".",
        "Повтори: 1 прогрівання + " + str(options.повтори) + " вимірів для кожного режиму/форми.",
        "",
        "| Фізична форма | Компіляція ELF p50/p95 (мс) | Готовий ELF p50/p95 | FPC evaluator p50/p95 | Незалежний SENS p50/p95 |",
        "|---|---:|---:|---:|---:|",
    ]
    for rec in report["форми"]:
        row = [str(rec["мітка"])]
        for ch in CHANNELS:
            vals = rec["часи"][ch]
            row.append(str(vals["медіана_мс"]) + " / " + str(vals["р95_мс"]))
        md.append("| " + " | ".join(row) + " |")
    md += [
        "",
        "**Межа виміру:** кожне значення — зовнішній wall-clock нового процесу,",
        "включно зі стартом, файловими операціями та запуском CLI. Готовий ELF",
        "повторно використовує той самий скомпільований образ. Ні частоту",
        "виконання окремих інструкцій x86, ні внутрішній throughput evaluator",
        "ці цифри НЕ визначають. Висновок про speedup робити не можна.",
        "",
        "Кожен вимір приймався лише після byte-exact перевірки відповіді.",
        "Чотири фізичні джерела залишилися незмінними за SHA256.",
        "Побайтовий компаратор відхилив " + str(negative) + " негативних випадків.",
        "Усі сирі метрики та SHA256 збережені у виміри.json.",
        "",
    ]
    (out / "звіт.md").write_text("\n".join(md), encoding="utf-8")
    print("НАТИВНІ-ЧАСОВІ-ВИМІРИ-ГАРАЗД фізичних=4 "
          "комбінацій=4 незалежний-SENS=так збережено=виміри.json/звіт.md "
          "повторів=" + str(options.повтори) + " негативів=" + str(negative))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print("НАТИВНІ-ЧАСОВІ-ВИМІРИ-ПОМИЛКА: " + str(exc), file=sys.stderr)
        sys.exit(2)
