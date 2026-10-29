#!/usr/bin/env python3
# G6.64 — ЧЕСНА межа: cold-start ELF64, не інструкції, не енергія.
# Фізичний pinned SENS і його незалежний oracle доводяться зовнішнім
# benchmark-native-d3.sh ДО цього кроку. Тут не створюємо мовних законів.
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import random
import statistics
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

CASES = (("тотожні-00", 0, 0), ("тотожні-01", 0, 1),
         ("тотожні-10", 1, 0), ("тотожні-11", 1, 1))
LANGS = ("sens-elf", "c-gcc", "rust", "free-pascal")
PIN = "1f1bf676eeac605e065035d9dd2adaae807f1788"
TIMEOUT = 120


def require(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def call(argv: list[str], *, cwd: Path, timeout: int = TIMEOUT) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(argv, cwd=cwd, capture_output=True,
                          timeout=timeout, check=False)


def check_output(code: int, actual: bytes, stderr: bytes, expected: bytes) -> None:
    require(code == 0, f"неуспішне виконання, код={code}")
    require(stderr == b"", "непорожній stderr")
    require(actual == expected, f"порушено exact T5M, отримано={actual.hex()}, очікувано={expected.hex()}")


def checked(argv: list[str], cwd: Path, expected: bytes | None = None) -> bytes:
    result = call(argv, cwd=cwd)
    require(result.returncode == 0, f"помилка команди: {argv!r} {result.stderr[:300]!r}")
    require(result.stderr == b"", f"непорожній stderr: {argv!r} {result.stderr[:300]!r}")
    if expected is not None:
        check_output(result.returncode, result.stdout, result.stderr, expected)
    return result.stdout


def stats(samples: list[int]) -> dict[str, float | int]:
    require(len(samples) >= 30 and all(v > 0 for v in samples),
            "потрібно 30 повних додатних тривалостей")
    ordered = sorted(samples)
    return {"повторів": len(ordered),
            "медіана_мс": round(statistics.median(ordered) / 1e6, 6),
            "р95_мс": round(ordered[math.ceil(.95 * len(ordered)) - 1] / 1e6, 6),
            "мін_мс": round(ordered[0] / 1e6, 6),
            "макс_мс": round(ordered[-1] / 1e6, 6)}


def selftest() -> int:
    rejected = 0
    for code, answer, error, expected in (
        (1, b"\x01", b"", b"\x01"),
        (0, b"\x00", b"", b"\x01"),
        (0, b"\x01\x01", b"", b"\x01"),
        (0, b"", b"", b"\x01"),
        (0, b"\x01", b"помилка", b"\x01"),
    ):
        try:
            check_output(code, answer, error, expected)
        except ValueError:
            rejected += 1
    for values in ([], [1], [1] * 29, [1] * 29 + [0]):
        try:
            stats(values)
        except ValueError:
            rejected += 1
    require(rejected == 9, "самотест не відхилив усі неправильні зразки")
    return rejected


def program_source(lang: str, a: int, b: int, yes: int, no: int) -> str:
    # Фізичні байти yes/no походять із canonical expected.sens pinned
    # тестового генератора, НЕ з перерахованої host-семантики.
    if lang == "c-gcc":
        return f"""#include <stdint.h>
#include <stdio.h>
static volatile uint64_t left = {a}ULL, right = {b}ULL;
int main(void) {{
    const unsigned char answer = (left == right) ? {yes} : {no};
    return fwrite(&answer, 1, 1, stdout) == 1 ? 0 : 2;
}}
"""
    if lang == "rust":
        return f"""use std::hint::black_box;
use std::io::Write;
fn main() {{
    let left = black_box({a}u64);
    let right = black_box({b}u64);
    let answer: u8 = if left == right {{ {yes} }} else {{ {no} }};
    std::io::stdout().write_all(&[answer]).expect("physical output");
}}
"""
    if lang == "free-pascal":
        return f"""program kontrol_fizychnoi_rivnosti;
{{$mode objfpc}}{{$H+}}
uses Classes, SysUtils;
var Left,Right:QWord; Answer:Byte; Sink:THandleStream;
begin
  Left:={a}; Right:={b};
  if Left=Right then Answer:={yes} else Answer:={no};
  Sink:=THandleStream.Create(TextRec(Output).Handle);
  try Sink.WriteBuffer(Answer,1); finally Sink.Free; end;
end.
"""
    raise ValueError("невідомий host-компілятор")


def build_host(lang: str, label: str, a: int, b: int, yes: int, no: int,
               directory: Path, root: Path) -> Path:
    ext = {"c-gcc": ".c", "rust": ".rs", "free-pascal": ".pas"}[lang]
    base = directory / "sources" / f"{label}-{lang}"
    path = Path(str(base) + ext)
    path.write_text(program_source(lang, a, b, yes, no), encoding="utf-8")
    dest = directory / "bin" / f"{label}-{lang}"
    if lang == "c-gcc":
        cmd = ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", str(path), "-o", str(dest)]
    elif lang == "rust":
        cmd = ["rustc", "--edition=2021", "-C", "opt-level=2",
               "-C", "codegen-units=1", str(path), "-o", str(dest)]
    else:
        cmd = ["fpc", "-B", "-O2", "-Mobjfpc", "-Cr", "-Co", "-Ci",
               "-FU" + str(directory / "units"), "-FE" + str(directory / "bin"),
               "-o" + dest.name, str(path)]
    output = call(cmd, cwd=root, timeout=180)
    require(output.returncode == 0, f"компіляція {lang} {label}: {output.stdout[-700:]!r} {output.stderr[-700:]!r}")
    require(dest.is_file(), f"немає host ELF для {lang} {label}")
    return dest


def main() -> None:
    ap = argparse.ArgumentParser(description="Cold-start ELF із фізичним D3:101 і трьома host-компіляторами")
    ap.add_argument("--корінь", type=Path, required=True)
    ap.add_argument("--свідки", type=Path, required=True)
    ap.add_argument("--машина", type=Path, required=True)
    ap.add_argument("--вихід", type=Path, required=True)
    ap.add_argument("--повтори", type=int, default=30)
    ap.add_argument("--зерно", type=int, default=6464)
    ap.add_argument("--самотест", action="store_true")
    args = ap.parse_args()
    rejected = selftest()
    if args.самотест:
        print(f"КОНТРОЛЬ-КОМПАРАТОРА-ГАРАЗД негативів={rejected}")
        return
    require(sys.platform == "linux" and platform.machine() == "x86_64",
            "тільки Linux x86-64 для машинного ABI")
    require(30 <= args.повтори <= 120, "вимірів має бути 30..120")
    root = args.корінь.resolve()
    fixtures = args.свідки.resolve()
    machine = args.машина.resolve()
    out = args.вихід.resolve()
    require(not out.exists(), "ціль результату вже існує")
    require(machine.is_file() and os.access(machine, os.X_OK), "немає FPC sensmashyna")
    require((root / "external/sens/contracts/language-contract-12.lisp").is_file(),
            "немає pinned Contract 12")
    require((root / "build/m0.2/benchmark-native-d3/виміри.json").is_file(),
            "немає завершеного незалежного SENS oracle benchmark")
    oracle = json.loads((root / "build/m0.2/benchmark-native-d3/виміри.json").read_text(encoding="utf-8"))
    require(oracle.get("незалежний_SENS_SHA") == PIN and len(oracle.get("форми", [])) == 4,
            "попередній незалежний SENS oracle не підтвердив 4 форми")

    physical = {}
    for label, _, _ in CASES:
        src = fixtures / f"{label}.sens"
        expected = (fixtures / f"{label}.expected.sens").read_bytes()
        require(src.is_file() and 0 < src.stat().st_size < 65536,
                "немає фізичного канонічного свідка " + label)
        require(len(expected) == 1, "цей тест обмежено однобайтовим D1 T5M")
        physical[label] = (src, expected)
    yes = physical["тотожні-00"][1][0]
    no = physical["тотожні-01"][1][0]
    require(yes != no and physical["тотожні-11"][1] == bytes([yes]) and
            physical["тотожні-10"][1] == bytes([no]),
            "фізичні D1 результати не узгоджені з pinned свідками")

    out.mkdir(parents=True)
    for name in ("sources", "bin", "units"):
        (out / name).mkdir()
    binaries: dict[tuple[str, str], Path] = {}
    manifest = {}
    for label, a, b in CASES:
        src, wanted = physical[label]
        elf = out / "bin" / (label + "-sens.elf")
        produced = checked([str(machine), "--тотожність", str(root / "external/sens"),
                            str(src), str(elf)], cwd=root)
        require(b"ELF" in produced and elf.is_file(), "немає нативного ELF для " + label)
        binaries[(label, "sens-elf")] = elf
        for lang in LANGS[1:]:
            binaries[(label, lang)] = build_host(lang, label, a, b, yes, no, out, root)
        for lang in LANGS:
            exe = binaries[(label, lang)]
            checked([str(exe)], cwd=root, expected=wanted)
            manifest[f"{label}/{lang}"] = {"sha256": sha256(exe.read_bytes()),
                                          "ELF_байтів": exe.stat().st_size}
    order = list(binaries)
    for _ in range(3):  # однаковий прогрів кожного виконуваного файла
        for key in order:
            checked([str(binaries[key])], cwd=root, expected=physical[key[0]][1])

    rng = random.Random(args.зерно)
    samples = []
    times = {key: [] for key in binaries}
    for block in range(args.повтори):
        rng.shuffle(order)
        for label, lang in order:
            before = time.perf_counter_ns()
            output = call([str(binaries[(label, lang)])], cwd=root, timeout=15)
            elapsed = time.perf_counter_ns() - before
            check_output(output.returncode, output.stdout, output.stderr, physical[label][1])
            require(elapsed > 0, "некоректний час")
            times[(label, lang)].append(elapsed)
            samples.append({"блок": block + 1, "випадок": label, "виконавець": lang,
                            "наносекунд": elapsed, "відповідь_sha256": sha256(output.stdout)})

    result = {
        "схема": "sens-elf-c-rust-fpc-coldstart/1",
        "дата_utc": datetime.now(timezone.utc).isoformat(),
        "pinned_SENS_SHA": PIN, "oracle": "незалежний pinned SENS у benchmark-native-d3",
        "операція": "фізична D3:101(D1,D1), фіксовані операнди, packed T5M stdout",
        "межа": "холодний запуск нового процесу + його ABI/IO; НЕ warm throughput, НЕ intrinsic speedup",
        "енергія": "ENERGY_NOT_MEASURED",
        "попередження": "Різні компілятори можуть константно згортати вираз, а runtime/loader різні. Не ранжувати мови за цим стендом. RAPL вимірюють окремо на контрольованому обладнанні.",
        "машина": {"ОС": platform.platform(), "CPU": platform.processor(),
                   "логічні_CPU": os.cpu_count(), "Python": platform.python_version()},
        "метод": {"прогрівань": 3, "повторів": args.повтори, "seed": args.зерно,
                  "порядок": "випадково перемішаний у кожному блоці",
                  "годинник": "perf_counter_ns end-to-end"},
        "виконувані": manifest, "сирі_виміри": samples,
        "підсумки": {f"{k[0]}/{k[1]}": stats(v) for k, v in times.items()},
        "негативів_компаратора": rejected,
    }
    # Успіх публікується лише після завершення ВСІХ перевірок.
    target = out / "виміри.json"
    temp = out / "виміри.json.tmp"
    with temp.open("x", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2, allow_nan=False)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.link(temp, target)  # O_EXCL-семантика; не перезаписувати
    temp.unlink()
    print(f"КОМПІЛЯТОР-ЕЛФ-ПОРІВНЯННЯ-ГАРАЗД програми={len(manifest)} проб={len(samples)}"
          f" негативів={rejected} енергія=ENERGY_NOT_MEASURED")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"КОМПІЛЯТОР-ЕЛФ-ПОРІВНЯННЯ-БЛОК: {error}", file=sys.stderr)
        raise SystemExit(2)
