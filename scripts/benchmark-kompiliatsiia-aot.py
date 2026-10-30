#!/usr/bin/env python3
"""G6.67: час справжньої AOT-компіляції SENS ELF64 та C/Rust/FPC.

Вимірюємо окремо ОДИН виклик компілятора; виконання кожного нового
ELF — за межами таймера, але обов'язкове exact T5M підтвердження.
Закони й фізичні еталони — ТІЛЬКИ pinned SENS/наявні свідки.
Це не RAPL, не енергія, не загальний compiler benchmark.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import os
import platform
import random
import struct
import statistics
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

PIN = "1f1bf676eeac605e065035d9dd2adaae807f1788"
LANGS = ("sens-elf", "c-gcc", "rust", "free-pascal")
CASES = (("тотожні-00", 0, 0), ("тотожні-01", 0, 1),
         ("тотожні-10", 1, 0), ("тотожні-11", 1, 1))
TIMEOUT = 180


def need(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def verify_elf64_x86_64(image: bytes) -> None:
    """Перевірка виконуваного Linux x86-64 ELF, а не тільки магічних байтів."""
    need(len(image) >= 120 and image[:7] == b"\x7fELF\x02\x01\x01",
         "неправильний ELF64 little-endian заголовок")
    (kind, machine, version, entry, phoff, _shoff, _flags, ehsize,
     phentsize, phnum, _shentsize, _shnum, _shstrndx) = struct.unpack_from(
         "<HHIQQQIHHHHHH", image, 16)
    need(kind in (2, 3) and machine == 62 and version == 1,
         "потрібен виконуваний x86-64 ELF64 (ET_EXEC або ET_DYN)")
    need(ehsize == 64 and phentsize == 56 and phoff >= 64
         and phoff <= len(image) and 0 < phnum <= (len(image) - phoff) // phentsize,
         "пошкоджена геометрія ELF64 program headers")
    executable_entry = False
    for index in range(phnum):
        (segment, flags, offset, vaddr, _paddr, file_size,
         memory_size, _align) = struct.unpack_from(
             "<IIQQQQQQ", image, phoff + index * phentsize)
        if segment != 1:  # PT_LOAD: host linker metadata не є семантикою SENS.
            continue
        need(offset <= len(image) and file_size <= len(image) - offset
             and memory_size >= file_size
             and memory_size <= (1 << 64) - vaddr,
             "ELF64 PT_LOAD поза межами файлу або 64-бітної адреси")
        # Тільки файлозабезпечені виконувані байти допускають машинний entry.
        # Віртуальна BSS-частина, інший PT_LOAD чи вихід за QWord — відмова.
        if (flags & 1) and file_size > 0 and entry >= vaddr \
                and entry - vaddr < file_size:
            executable_entry = True
    need(executable_entry, "ELF64 точка входу поза виконуваними байтами PT_LOAD")


def elf64_negative_selftest() -> int:
    # Штучний коректний каркас: НЕ виконуємо його як машинну програму.
    sample = bytearray(160)
    sample[:7] = b"\x7fELF\x02\x01\x01"
    struct.pack_into("<HHIQQQIHHHHHH", sample, 16,
                     3, 62, 1, 0x401000, 64, 0, 0, 64, 56, 1, 0, 0, 0)
    struct.pack_into("<IIQQQQQQ", sample, 64,
                     1, 5, 120, 0x401000, 0, 16, 16, 4096)
    sample[120:136] = b"\x90" * 16
    verify_elf64_x86_64(bytes(sample))

    def damaged(offset: int, fmt: str, value: int) -> bytes:
        result = bytearray(sample)
        struct.pack_into(fmt, result, offset, value)
        return bytes(result)

    invalid = (
        b"",
        damaged(4, "B", 1),           # ELFCLASS32
        damaged(5, "B", 2),           # big-endian, а не x86-64 LE
        damaged(18, "<H", 183),       # AArch64, не x86-64
        damaged(16, "<H", 1),         # ET_REL, не виконуваний
        damaged(32, "<Q", 120),       # phoff + phentsize > EOF
        damaged(56, "<H", 0),         # жодного program header
        damaged(68, "<I", 4),         # тільки PF_R, немає PF_X
        damaged(96, "<Q", 100),       # PT_LOAD виходить за EOF
        damaged(104, "<Q", 8),        # p_memsz < p_filesz
        damaged(24, "<Q", 0x404000),  # e_entry поза виконуваним сегментом
        damaged(80, "<Q", 0x403000),  # X-сегмент не містить e_entry
        damaged(80, "<Q", (1 << 64) - 8),  # p_vaddr + p_memsz > QWord
    )
    rejected = 0
    for raw in invalid:
        try:
            verify_elf64_x86_64(raw)
        except ValueError:
            rejected += 1
    need(rejected == len(invalid), "ELF64 admission прийняв пошкоджений образ")
    return rejected


def invoke(cmd: list[str], root: Path, timeout: int = TIMEOUT) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(cmd, cwd=root, capture_output=True, timeout=timeout, check=False)


def check_answer(executable: Path, root: Path, expected: bytes) -> str:
    # Запуск ELF — ЗА МЕЖАМИ таймера компілятора.
    need(executable.is_file() and os.access(executable, os.X_OK),
         "компілятор не створив виконуваний ELF64")
    raw = executable.read_bytes()
    verify_elf64_x86_64(raw)
    result = invoke([str(executable)], root, timeout=20)
    need(result.returncode == 0 and result.stderr == b"" and
         result.stdout == expected,
         f"компільований ELF дав неправильну фізичну відповідь: {executable.name}")
    return sha256(raw)


def quantiles(values: list[int]) -> dict[str, int | float]:
    need(len(values) >= 30 and all(isinstance(x, int) and x > 0 for x in values),
         "потрібні щонайменше 30 правильних часів компіляції")
    ordered = sorted(values)
    return {"кількість": len(ordered),
            "медіана_мс": round(statistics.median(ordered) / 1_000_000, 6),
            "р95_мс": round(ordered[math.ceil(.95 * len(ordered)) - 1] / 1_000_000, 6),
            "мін_мс": round(ordered[0] / 1_000_000, 6),
            "макс_мс": round(ordered[-1] / 1_000_000, 6)}


def selftest() -> int:
    failures = 0
    for samples in ([], [1], [1] * 29, [1] * 29 + [0], [-1] * 30):
        try:
            quantiles(samples)
        except ValueError:
            failures += 1
    for code, out, err, expected in (
        (1, b"\x01", b"", b"\x01"),
        (0, b"\x00", b"", b"\x01"),
        (0, b"\x01", b"error", b"\x01"),
        (0, b"", b"", b"\x01"),
    ):
        try:
            need(code == 0 and out == expected and err == b"",
                 "відхилено хибну фізичну відповідь")
        except ValueError:
            failures += 1
    need(failures == 9, "самотест не відхилив усі хибні випадки")
    need(quantiles([1_000_000] * 30)["медіана_мс"] == 1.0,
         "хибний часовий масштаб")
    return failures + elf64_negative_selftest()


def prior_oracle(root: Path) -> dict:
    path = root / "build/m0.2/benchmark-native-d3/виміри.json"
    need(path.is_file(), "немає чинного перевіреного незалежного SENS oracle")
    report = json.loads(path.read_text(encoding="utf-8"))
    need(report.get("незалежний_SENS_SHA") == PIN and
         len(report.get("форми", [])) == 4,
         "незалежний SENS REPL не перевірив потрібні фізичні форми")
    return report


def existing_program_source(root: Path):
    # Самі host C/Rust/FPC реалізації вже пройшли G6.64: НЕ переписуємо
    # їх у другому benchmark і не визначаємо закон SENS у Python.
    path = root / "scripts/benchmark-elf-porivniannia.py"
    spec = importlib.util.spec_from_file_location("kontrol_aot_komparatora", path)
    need(spec is not None and spec.loader is not None, "відсутній наявний host comparator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    need(module.PIN == PIN and tuple(module.LANGS) == LANGS and
         tuple(module.CASES) == CASES,
         "змінилися незалежні C/Rust/FPC контрольні форми")
    return module.program_source


def create_sources(root: Path, temp: Path, fixtures: Path) -> tuple[dict, dict]:
    program_source = existing_program_source(root)
    inputs = {}
    for label, a, b in CASES:
        physical = fixtures / (label + ".sens")
        expected = fixtures / (label + ".expected.sens")
        need(physical.is_file() and expected.is_file(),
             "відсутня точна фізична пара для " + label)
        data = physical.read_bytes()
        wanted = expected.read_bytes()
        need(0 < len(data) <= 65536 and len(wanted) == 1,
             "непідтримана фізична форма або очікувана відповідь")
        inputs[label] = {"path": physical, "expected": wanted,
                         "source_sha256": sha256(data), "answer_sha256": sha256(wanted)}
    yes = inputs["тотожні-00"]["expected"][0]
    no = inputs["тотожні-01"]["expected"][0]
    need(yes != no and inputs["тотожні-11"]["expected"] == bytes([yes])
         and inputs["тотожні-10"]["expected"] == bytes([no]),
         "порушено pinned фізичні свідки D1")
    source_dir = temp / "sources"
    source_dir.mkdir()
    names = {"c-gcc": ".c", "rust": ".rs", "free-pascal": ".pas"}
    programs = {}
    for label, a, b in CASES:
        for lang in LANGS[1:]:
            source = source_dir / (label + "-" + lang + names[lang])
            source.write_text(program_source(lang, a, b, yes, no), encoding="utf-8")
            programs[label, lang] = source
    return inputs, programs


def build_command(lang: str, label: str, target: Path, source: Path | None,
                  machine: Path, root: Path, temp: Path, physical: Path) -> list[str]:
    if lang == "sens-elf":
        return [str(machine), "--тотожність",
                str(root / "external/sens"), str(physical), str(target)]
    need(source is not None and source.is_file(), "немає host джерела")
    if lang == "c-gcc":
        return ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
                str(source), "-o", str(target)]
    if lang == "rust":
        return ["rustc", "--edition=2021", "--crate-name", "kontrol_t5m",
                "-C", "opt-level=2", "-C", "codegen-units=1",
                str(source), "-o", str(target)]
    if lang == "free-pascal":
        return ["fpc", "-B", "-O2", "-Mobjfpc", "-Cr", "-Co", "-Ci",
                "-FU" + str(temp / "units"), "-FE" + str(target.parent),
                "-o" + target.name, str(source)]
    raise ValueError("невідомий host compiler; відмовлено без запуску")


def one_compile(lang: str, label: str, turn: int, root: Path, temp: Path,
                inputs: dict, programs: dict, machine: Path) -> tuple[int, str, int]:
    target = temp / "bin" / (label + "-" + lang + "-" + str(turn) + ".elf")
    need(not target.exists(), "не допускаємо перезапис уже створеного ELF")
    cmd = build_command(lang, label, target, programs.get((label, lang)),
                        machine, root, temp, inputs[label]["path"])
    before = time.perf_counter_ns()
    result = invoke(cmd, root)
    nanos = time.perf_counter_ns() - before
    need(result.returncode == 0 and result.stderr == b"" and nanos > 0,
         "компілятор відмовив або дав stderr: " + lang + " " +
         result.stderr.decode("utf-8", errors="replace")[-300:])
    # SENS compiler друкує лише host-діагностику; ELF зберігає у файлі.
    elf_sha = check_answer(target, root, inputs[label]["expected"])
    length = target.stat().st_size
    target.unlink()
    return nanos, elf_sha, length


def main() -> None:
    parser = argparse.ArgumentParser(description="Вимір часу AOT-компіляції, не енергії")
    parser.add_argument("--корінь", type=Path)
    parser.add_argument("--свідки", type=Path)
    parser.add_argument("--машина", type=Path)
    parser.add_argument("--вихід", type=Path)
    parser.add_argument("--повтори", type=int, default=30)
    parser.add_argument("--зерно", type=int, default=6767)
    parser.add_argument("--самотест", action="store_true")
    args = parser.parse_args()
    rejected = selftest()
    if args.самотест:
        print(f"АВТ-КОМПІЛЯЦІЯ-САМОТЕСТ-ГАРАЗД негативів={rejected}")
        return
    need(all((args.корінь, args.свідки, args.машина, args.вихід)),
         "потрібні корінь, свідки, машина і вихід")
    need(sys.platform == "linux" and platform.machine() == "x86_64",
         "фізичний ELF стенд лише для Linux x86-64")
    need(30 <= args.повтори <= 120, "для серії потрібно 30..120 повторів")
    root = args.корінь.resolve()
    fixtures = args.свідки.resolve()
    machine = args.машина.resolve()
    destination = args.вихід.resolve()
    need(not destination.exists(), "файл результатів існує: ніякого перезапису")
    need(machine.is_file() and os.access(machine, os.X_OK),
         "немає справжнього нативного FPC компілятора")
    need((root / "external/sens/contracts/language-contract-12.lisp").is_file(),
         "немає pinned Contract 12")
    prior_oracle(root)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="aot-6767-", dir=destination.parent) as work:
        temp = Path(work)
        (temp / "bin").mkdir()
        (temp / "units").mkdir()
        inputs, programs = create_sources(root, temp, fixtures)
        plan = [(label, lang) for label, _, _ in CASES for lang in LANGS]
        samples = {key: [] for key in plan}
        raw = []
        sizes = {}
        # Прогріваємо всі 16 однакових фізичних випадків ОДИН раз;
        # правильне ELF виконання обов'язкове навіть для прогріву.
        for label, lang in plan:
            one_compile(lang, label, 0, root, temp, inputs, programs, machine)
        rnd = random.Random(args.зерно)
        for turn in range(1, args.повтори + 1):
            rnd.shuffle(plan)
            for label, lang in plan:
                nanos, digest, size = one_compile(lang, label, turn, root,
                                                 temp, inputs, programs, machine)
                samples[label, lang].append(nanos)
                sizes[label, lang] = size
                raw.append({"блок": turn, "форма": label, "компілятор": lang,
                            "компіляція_нс": nanos, "elf_sha256": digest,
                            "elf_байтів": size,
                            "відповідь_sha256": inputs[label]["answer_sha256"]})
        need(len(raw) == 16 * args.повтори, "неповна матриця часу компіляції")
        report = {
            "схема": "sens-aot-compile-walltime/1",
            "дата_utc": datetime.now(timezone.utc).isoformat(),
            "метрика": "wall-clock процесу AOT compiler: startup+read+admit+emit; виконання ELF поза таймером",
            "енергія": "ENERGY_NOT_MEASURED",
            "компіляторний_напрям": "pinned SENS Contract 12, фізична D3:101(D1,D1) vs C/Rust/FPC",
            "профіль": {"ос": platform.platform(), "процесор": platform.processor(),
                        "архітектура": platform.machine(), "seed": args.зерно,
                        "прогрів_кожного": 1, "повторів_кожного": args.повтори},
            "pinned_SENS_SHA": PIN,
            "незалежний_оракул": "build/m0.2/benchmark-native-d3/виміри.json",
            "механіка": "одна фізична форма → один новий ELF, запуск і byte-exact перевірка кожного",
            "зразки": {label: {k: v for k, v in info.items() if k != "path" and k != "expected"}
                       for label, info in inputs.items()},
            "статистика": {f"{label}/{lang}": dict(quantiles(times),
                              ELF_байтів=sizes[label, lang])
                           for (label, lang), times in samples.items()},
            "сирі_виміри": raw,
            "негативів": rejected,
            "обмеження": "Не RAPL; одна операція над двома D1; різні frontends; не узагальнювати на мови або енергоефективність"
        }
        # Файл публікується лише після ВСІХ компіляцій і виконань,
        # інакше навіть часткова статистика не виглядає як готовий результат.
        candidate = temp / "виміри.json"
        candidate.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                             encoding="utf-8")
        os.replace(candidate, destination)
    print(f"АВТ-КОМПІЛЯЦІЯ-ГАРАЗД компіляцій={16 * args.повтори} "
          f"варіантів=16 повторів={args.повтори} oracle=pinned "
          f"правильність=побайтово енергія=ENERGY_NOT_MEASURED")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        print("АВТ-КОМПІЛЯЦІЯ-БЛОК: " + str(error), file=sys.stderr)
        sys.exit(2)
