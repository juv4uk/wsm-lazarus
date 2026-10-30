#!/usr/bin/env python3
"""Фізичний cold-start/RAPL профіль D5 частки: SENS, C, Rust і FPC.

Host кадр — дві окремі signed D12 T5M слова (шість байтів), результат —
одне signed D12 T5M слово (три байти). Кодек тут описує тільки транспорт;
допуск D5 та семантичний oracle залишаються pinned SENS.

Питання: чому T5M padding перевіряється окремо від бітів? Чому відмова
на остачі не є новим законом? Чому package RAPL не належить PID? Чому
ручний workflow не створює енергію для hosted runner? Яку межу має цей зріз?
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
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

PIN = "2c498b35af53c085450eac6f51b87facf7f9aa47"
LANGUAGES = ("sens-elf", "c-gcc", "rust", "free-pascal")
CASES = ("07", "12", "21", "25")
HERE = Path(__file__).resolve().parent
RAPL_PARSER = runpy.run_path(str(HERE / "compiled-elf.py"))["parse_rapl"]


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise ValueError(reason)


def checked_d12(value: int) -> int:
    require(type(value) is int and -2048 <= value <= 2047,
            "значення поза signed D12")
    return value


def _bits(value: int) -> list[int]:
    return [(value & 0xFFF) >> shift & 1 for shift in range(11, -1, -1)]


def _pack_trits(trits: list[int]) -> bytes:
    require(len(trits) % 5 == 0 and all(t in (0, 1, 2) for t in trits),
            "неповний або недопустимий T5M trit-потік")
    packed = bytearray()
    for start in range(0, len(trits), 5):
        value = 0
        for digit in trits[start:start + 5]:
            value = value * 3 + digit
        require(value < 243, "T5M байт поза base-243")
        packed.append(value)
    return bytes(packed)


def _unpack_trits(frame: bytes) -> list[int]:
    require(bool(frame) and all(byte < 243 for byte in frame),
            "порожній або некоректний фізичний T5M кадр")
    trits: list[int] = []
    for byte in frame:
        value = byte
        group = [0] * 5
        for index in range(4, -1, -1):
            group[index] = value % 3
            value //= 3
        require(value == 0, "байт не є п'ятьма канонічними тритами")
        trits.extend(group)
    return trits


def _signed(bits: list[int]) -> int:
    value = 0
    for bit in bits:
        require(bit in (0, 1), "D12 містить не двійковий трит")
        value = value * 2 + bit
    return value - 4096 if bits[0] else value


def encode_pair(left: int, right: int) -> bytes:
    """Пакувати два D12 у канонічну 30-тритну host-рамку."""
    left_bits, right_bits = _bits(checked_d12(left)), _bits(checked_d12(right))
    return _pack_trits(left_bits + [2] * 3 + right_bits + [2] * 3)


def decode_pair(frame: bytes) -> tuple[int, int]:
    """Зчитати лише повний фізичний W12+W12 кадр із роздільником."""
    require(len(frame) == 6, "очікується рівно шість T5M байтів")
    trits = _unpack_trits(frame)
    require(len(trits) == 30 and trits[12:15] == [2] * 3 and
            trits[27:] == [2] * 3,
            "неправильні межі слів або padding T5M")
    return _signed(trits[:12]), _signed(trits[15:27])


def encode_result(value: int) -> bytes:
    """Пакувати одне exact signed D12 у три канонічні T5M байти."""
    return _pack_trits(_bits(checked_d12(value)) + [2] * 3)


def decode_result(frame: bytes) -> int:
    require(len(frame) == 3, "очікується рівно три T5M байти результату")
    trits = _unpack_trits(frame)
    require(len(trits) == 15 and trits[12:] == [2] * 3,
            "неправильний padding вихідного D12")
    return _signed(trits[:12])


def quotient_d12(left: int, right: int) -> int:
    """Host expectation для перевірки, не SENS мовний oracle."""
    checked_d12(left)
    checked_d12(right)
    require(right != 0, "ділення на нуль")
    require(left % right == 0, "частка має ненульову остачу")
    result = abs(left) // abs(right)
    if (left < 0) != (right < 0):
        result = -result
    return checked_d12(result)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(argv: list[str], *, cwd: Path, input_data: bytes | None = None,
        timeout: int = 60, check_stderr: bool = True) -> bytes:
    completed = subprocess.run(argv, cwd=cwd, input=input_data,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               timeout=timeout, check=False)
    require(completed.returncode == 0,
            "команда відхилена: " + repr(argv) + " код=" +
            str(completed.returncode) + " stderr=" + repr(completed.stderr[:180]))
    if check_stderr:
        require(not completed.stderr, "успішна команда має stderr: " + repr(argv))
    return completed.stdout


def compile_fpc(root: Path, source: Path, name: str, output: Path,
                units: Path, *, checked: bool = True,
                heap_trace: bool = True) -> Path:
    flags = ["-B"]
    if checked:
        flags += ["-Cr", "-Co", "-Ci", "-gl"]
    if heap_trace:
        flags += ["-gh"]
    if not checked:
        flags += ["-O2"]
    completed = subprocess.run(
        ["fpc", *flags,
         "-Fu" + str(root / "src"), "-FU" + str(units),
         "-FE" + str(output), "-o" + name, str(source)],
        cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=240, check=False)
    require(completed.returncode == 0,
            "FPC збірка провалилась: " + str(source) + "\n" +
            completed.stdout.decode("utf-8", "replace")[-1600:])
    executable = output / name
    require(executable.is_file() and os.access(executable, os.X_OK),
            "FPC не створив виконуваний файл " + name)
    return executable


def compile_workers(root: Path, temp: Path) -> dict[str, Path]:
    output, units = temp / "bin", temp / "units"
    output.mkdir(exist_ok=True)
    units.mkdir(exist_ok=True)
    programs = root / "benchmarks/cross-language/quot"
    workers: dict[str, Path] = {}
    workers["c-gcc"] = output / "quot-c"
    completed = subprocess.run(
        ["gcc", "-O2", "-Wall", "-Wextra", "-Werror", "-o",
         str(workers["c-gcc"]), str(programs / "quot.c")],
        cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=120, check=False)
    require(completed.returncode == 0 and not completed.stderr,
            "GCC збірка провалилась: " + completed.stderr.decode("utf-8", "replace"))
    workers["rust"] = output / "quot-rust"
    completed = subprocess.run(
        ["rustc", "--edition=2021", "-C", "opt-level=2", "-C", "panic=abort",
         "-o", str(workers["rust"]), str(programs / "quot.rs")],
        cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=240, check=False)
    require(completed.returncode == 0 and not completed.stderr,
            "Rust збірка провалилась: " + completed.stderr.decode("utf-8", "replace"))
    workers["free-pascal"] = compile_fpc(
        root, programs / "quot.pas", "quot-fpc", output, units,
        checked=False, heap_trace=False)
    return workers


def prepare(root: Path, temp: Path) -> tuple[dict[str, Path], list[dict]]:
    require(platform.system() == "Linux" and platform.machine() == "x86_64",
            "потрібен Linux x86-64")
    require((root / "external/sens/contracts/language-contract-12.lisp").is_file(),
            "відсутній pinned SENS Contract 12.0")
    require(subprocess.run(["git", "-C", str(root / "external/sens"),
                            "rev-parse", "HEAD"], stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, timeout=10,
                           check=False).stdout.decode().strip() == PIN,
            "gitlink SENS не збігається з pinned Contract 12")
    oracle = root / "sens-oracle/target/debug/sens"
    require(oracle.is_file() and os.access(oracle, os.X_OK),
            "відсутній зібраний pinned SENS REPL sens-oracle/target/debug/sens")
    oracle_sha = subprocess.run(["git", "-C", str(root / "sens-oracle"),
                                 "rev-parse", "HEAD"], stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, timeout=10,
                                check=False).stdout.decode().strip()
    require(oracle_sha == PIN, "pinned SENS REPL має інший SHA")

    fixture_dir = temp / "physical"
    fixture_dir.mkdir()
    output, units = temp / "bin", temp / "units"
    output.mkdir()
    units.mkdir()
    generator = compile_fpc(root, root / "scripts/test-elfd12quotpotik.pas",
                            "test-elfd12quotpotik", output, units)
    generated = subprocess.run([str(generator), str(fixture_dir)], cwd=root,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               timeout=45, check=False)
    require(generated.returncode == 0 and b"positive=25" in generated.stdout and
            b"0 unfreed memory blocks" in generated.stderr,
            "не створено/не звільнено pinned фізичні свідки: " +
            generated.stderr.decode("utf-8", "replace")[-600:])
    compiler = compile_fpc(root, root / "src/sensd12quotpotikelf.lpr",
                           "sensd12quotpotikelf", output, units)
    workers = compile_workers(root, temp)
    elf = output / "quot-sens.elf"
    compiled_elf = subprocess.run(
        [str(compiler), "--зібрати-D5-частку-потік",
         str(fixture_dir / "anchor.sens"), str(elf)], cwd=root,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60, check=False)
    require(compiled_elf.returncode == 0 and
            b"stdin=2xT5M-D12 stdout=T5M-D12" in compiled_elf.stdout and
            (not compiled_elf.stderr or b"0 unfreed memory blocks" in compiled_elf.stderr),
            "FPC не створив чистий SENS ELF: " +
            compiled_elf.stderr.decode("utf-8", "replace")[-500:])
    require(elf.is_file() and os.access(elf, os.X_OK),
            "SENS компілятор не створив виконуваний ELF")
    workers["sens-elf"] = elf
    workers["pinned-sens-repl"] = oracle

    rows = []
    for line in (fixture_dir / "cases.tsv").read_text(encoding="utf-8").splitlines():
        label, left_text, right_text, result_text = line.split("\t")
        left, right, expected_value = map(int, (left_text, right_text, result_text))
        frame = (fixture_dir / (label + ".frame")).read_bytes()
        expected = (fixture_dir / (label + ".expected.sens")).read_bytes()
        source = fixture_dir / (label + ".sens")
        require(encode_pair(left, right) == frame and decode_pair(frame) ==
                (left, right), "host T5M кодек не збігається з FPC свідком " + label)
        require(quotient_d12(left, right) == expected_value and
                encode_result(expected_value) == expected and
                decode_result(expected) == expected_value,
                "не збігається фізичний D12 результат " + label)
        oracle_out = run([str(oracle), str(source)], cwd=root, timeout=90)
        require(oracle_out == (str(expected_value) + "\n").encode(),
                "незалежний pinned SENS REPL не підтвердив " + label)
        for language in LANGUAGES:
            result = subprocess.run([str(workers[language])], cwd=root,
                                    input=frame, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, timeout=10, check=False)
            require(result.returncode == 0 and not result.stderr and
                    result.stdout == expected,
                    "байтова parity провалилась: " + label + "/" + language +
                    " rc=" + str(result.returncode) +
                    " out=" + result.stdout.hex() +
                    " stderr=" + result.stderr[:100].decode("utf-8", "replace"))
        rows.append({"case": label, "left": left, "right": right,
                     "expected": expected_value, "frame": frame,
                     "result": expected, "source": source})

    negatives = [line.split("\t", 1)[0] for line in
                 (fixture_dir / "numeric-reject.tsv").read_text(encoding="utf-8").splitlines()]
    negatives += ["empty", "short1", "short5", "extra", "newline", "invalid243",
                  "badfirst", "badsecond", "badlast", "projection", "d1"]
    for label in negatives:
        frame = (fixture_dir / (label + ".frame")).read_bytes()
        for language in LANGUAGES:
            result = subprocess.run([str(workers[language])], cwd=root,
                                    input=frame, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, timeout=10, check=False)
            require(result.returncode != 0 and not result.stdout,
                    "негатив не відхилено без stdout: " + label + "/" + language)
    manifest = [{"виконавець": key, "sha256": digest(path.read_bytes()),
                 "ELF_байтів": path.stat().st_size}
                for key, path in workers.items() if key in LANGUAGES]
    return workers, [{**row, "виконувані": manifest,
                      "oracle_sha": oracle_sha, "anchor_sha256":
                      digest((fixture_dir / "anchor.sens").read_bytes())}
                     for row in rows]


def snapshot(rapl: Path, powercap: Path, root: Path) -> bytes:
    command = [str(rapl), "--знімок", str(powercap)]
    result = subprocess.run(command, cwd=root, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, timeout=10, check=False)
    if result.returncode != 0 or not result.stdout.startswith(b"RAPL1\n"):
        sudo = shutil.which("sudo")
        require(sudo is not None, "ENERGY_NOT_MEASURED: датчик недоступний і sudo відсутній")
        result = subprocess.run([sudo, "-n", *command], cwd=root,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=10, check=False)
    require(result.returncode == 0 and result.stdout.startswith(b"RAPL1\n") and
            not result.stderr,
            "ENERGY_NOT_MEASURED: немає фізичного читання RAPL: " +
            result.stderr.decode("utf-8", "replace")[:200])
    return result.stdout


def package_key(snapshot_bytes: bytes) -> str:
    found = []
    for line in snapshot_bytes.decode("utf-8").splitlines()[1:]:
        fields = line.split("\t")
        if len(fields) == 4 and fields[1] == "package-0":
            found.append(fields[0])
    require(len(found) == 1, "ENERGY_NOT_MEASURED: немає однієї зони package-0")
    return found[0]


def sample(root: Path, rapl: Path, powercap: Path, workers: dict[str, Path],
           frame: bytes | None, expected: bytes | None, language: str,
           repeats: int, idle_ms: int, max_watts: int) -> dict:
    with tempfile.TemporaryDirectory(prefix="sens-quot-rapl-") as folder:
        before_path, after_path = Path(folder) / "before.tsv", Path(folder) / "after.tsv"
        started = time.monotonic_ns()
        before = snapshot(rapl, powercap, root)
        before_path.write_bytes(before)
        if language == "idle":
            time.sleep(idle_ms / 1000)
        else:
            for _ in range(repeats):
                got = run([str(workers[language])], cwd=root, input_data=frame,
                          timeout=10)
                require(got == expected, "змінився результат під час RAPL вибірки")
        after = snapshot(rapl, powercap, root)
        elapsed_us = max(1, (time.monotonic_ns() - started + 999) // 1000)
        after_path.write_bytes(after)
        delta = run([str(rapl), "--різниця", str(before_path), str(after_path),
                     str(elapsed_us), str(max_watts)], cwd=root)
        zones = RAPL_PARSER(delta, elapsed_us, max_watts)
        return {"elapsed_us": elapsed_us, "zones_uj": zones,
                "випадків": repeats if language != "idle" else 0,
                "RAPL_DELTA1": delta.decode("utf-8")}


def publish_pair(report: Path, samples: Path, value: dict, rows: list[dict]) -> None:
    require(report.parent == samples.parent and report != samples and
            report.parent.is_dir(), "звіт і зразки мають бути в одній наявній теці")
    require(not report.exists() and not report.is_symlink() and
            not samples.exists() and not samples.is_symlink(),
            "ціль звіту вже існує, перезапис заборонено")
    report_data = (json.dumps(value, ensure_ascii=False, indent=2,
                              allow_nan=False) + "\n").encode("utf-8")
    sample_data = b"".join((json.dumps(row, ensure_ascii=False, separators=(",", ":"),
                                          allow_nan=False) + "\n").encode("utf-8")
                            for row in rows)
    temporary: list[Path] = []
    linked: list[Path] = []
    try:
        for target, data in ((report, report_data), (samples, sample_data)):
            with tempfile.NamedTemporaryFile(dir=target.parent, prefix=".sens-quot-",
                                             delete=False) as handle:
                temp_path = Path(handle.name)
                temporary.append(temp_path)
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
        os.link(temporary[0], report)
        linked.append(report)
        os.link(temporary[1], samples)
        linked.append(samples)
    except OSError:
        for path in linked:
            path.unlink(missing_ok=True)
        raise
    finally:
        for path in temporary:
            path.unlink(missing_ok=True)


def measure(root: Path, temp: Path, workers: dict[str, Path], rows: list[dict],
            report: Path, samples_path: Path, blocks: int, repeats: int,
            idle_ms: int, max_watts: int, seed: int) -> dict:
    require(blocks >= 30 and repeats >= 1 and repeats <= 100 and
            1 <= idle_ms <= 10000 and 1 <= max_watts <= 10000,
            "параметри: блоки>=30, повтори 1..100, idle 1..10000ms")
    powercap = Path("/sys/devices/virtual/powercap/intel-rapl")
    rapl = compile_fpc(root, root / "scripts/energy/sensrapl.lpr", "sensrapl",
                       temp / "bin", temp / "units", heap_trace=False)
    first = snapshot(rapl, powercap, root)
    package = package_key(first)
    by_case = {row["case"]: row for row in rows}
    rng = random.Random(seed)
    raw_rows: list[dict] = []
    for block in range(blocks):
        order = [(case, language) for case in CASES for language in LANGUAGES]
        rng.shuffle(order)
        order.append(("idle", "idle"))
        for case, language in order:
            selected = by_case.get(case)
            result = sample(root, rapl, powercap, workers,
                            selected["frame"] if selected else None,
                            selected["result"] if selected else None,
                            language, repeats, idle_ms, max_watts)
            require(package in result["zones_uj"],
                    "RAPL зона package-0 зникла з вибірки")
            raw_rows.append({"блок": block + 1, "випадок": case,
                             "виконавець": language, **result})
    summary = {}
    for language in LANGUAGES:
        values = [row["zones_uj"][package] / 1_000_000 / repeats
                  for row in raw_rows if row["виконавець"] == language]
        summary[language] = {
            "медіана_пакетних_Дж_на_холодний_виклик": statistics.median(values),
            "вибірок": len(values), "викликів_на_вибірку": repeats,
            "тлумачення": "CPU package interval / виклики; включає OS, cold-start і host I/O",
        }
    data = {
        "схема": "sens-d12-quotient-coldstart-rapl/1",
        "статус": "HARDWARE_RAPL_MEASURED", "pinned_SENS_SHA": PIN,
        "метод": "одна операція за запуск; фізичний T5M stdin/stdout; програми скомпільовані до виміру; package RAPL включає ОС і холодний старт; idle не віднімається",
        "блоки": blocks, "повторів_у_вибірці": repeats, "idle_ms": idle_ms,
        "seed": seed, "max_watts": max_watts,
        "hardware": {"platform": platform.platform(),
                     "processor": platform.processor(),
                     "cpu_count": os.cpu_count(),
                     "affinity": sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None,
                     "powercap": str(powercap.resolve()), "package_zone": package},
        "виконувані": rows[0]["виконувані"],
        "oracle_sha": rows[0]["oracle_sha"],
        "anchor_sha256": rows[0]["anchor_sha256"],
        "summary": summary,
        "обмеження": ["це не енергія PID", "це не рейтинг повних мов",
                      "одне вузьке точне D12-ділення", "компіляція не входить у runtime-вимір"],
    }
    serializable_rows = [{k: (v.hex() if isinstance(v, bytes) else str(v) if isinstance(v, Path) else v)
                          for k, v in row.items() if k not in ("виконувані",)}
                         for row in raw_rows]
    publish_pair(report, samples_path, data, serializable_rows)
    return data


def main() -> None:
    parser = argparse.ArgumentParser(description="SENS D12 quotient cold-start RAPL benchmark")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--samples", type=Path)
    parser.add_argument("--blocks", type=int, default=30)
    parser.add_argument("--repeats", type=int, default=12)
    parser.add_argument("--idle-ms", type=int, default=50)
    parser.add_argument("--max-watts", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=6176)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--verify", action="store_true")
    mode.add_argument("--measure", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        require(root.is_dir(), "корінь репозиторію відсутній")
        if args.measure:
            require(args.output is not None and args.samples is not None,
                    "для виміру потрібні --output і --samples")
            require(args.output.parent.resolve() == args.samples.parent.resolve(),
                    "звіти мусять бути в одній теці")
        with tempfile.TemporaryDirectory(prefix="sens-d12-quot-benchmark-") as folder:
            temp = Path(folder)
            workers, rows = prepare(root, temp)
            if args.verify:
                require(args.output is None and args.samples is None,
                        "--verify не публікує енергетичний звіт")
                print("D12-ЧАСТКА-ПЕРЕВІРЕНО: SENS/C/Rust/FPC=100/100 ",
                      "pinned-oracle=25 negatives=72 energy=ENERGY_NOT_MEASURED", sep="")
                return
            data = measure(root, temp, workers, rows, args.output.resolve(),
                           args.samples.resolve(), args.blocks, args.repeats,
                           args.idle_ms, args.max_watts, args.seed)
            print("D12-ЧАСТКА-RAPL-ГОТОВО: status=" + data["статус"] +
                  " blocks=" + str(args.blocks) + " languages=4")
    except (ValueError, OSError, subprocess.TimeoutExpired,
            json.JSONDecodeError) as error:
        print("D12-ЧАСТКА-БЛОКЕР: " + str(error), file=sys.stderr)
        raise SystemExit(2)


if __name__ == "__main__":
    main()
