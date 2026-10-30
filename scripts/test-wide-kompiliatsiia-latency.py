#!/usr/bin/env python3
"""G6.173: реальний 16-програмний компіляторний latency-профіль, НЕ ватметр.

Мовні закони визначає тільки pinned SENS; цей скрипт НЕ декодує семантику.
У всіх трьох шляхах машинний результат має бути побайтово тим самим.
"""
from __future__ import annotations

import hashlib
import itertools
import json
import os
from pathlib import Path
import platform
import statistics
import struct
import subprocess
import sys
import tempfile
import time

COUNT = 16
REPEATS = 6
PIN = "1f1bf676eeac605e065035d9dd2adaae807f1788"
SINGLE_MODE = "--скомпілювати-фізичну-форму"
BATCH_MODE = "--скомпілювати-фізичні-кадри"
SESSION_MODE = "--компілювати-фізичний-сеанс"
METHODS = ("окремі-процеси", "атомарний-пакет", "постійний-сеанс")


def demand(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def frame(data: bytes) -> bytes:
    return struct.pack("<I", len(data)) + data


def parse_batch(data: bytes, expected: int) -> list[bytes]:
    images, at = [], 0
    while at < len(data):
        demand(at + 4 <= len(data), "обірваний заголовок пакетного ELF")
        (size,) = struct.unpack_from("<I", data, at)
        at += 4
        demand(120 < size <= 1048576 and at + size <= len(data),
               "пошкоджений розмір пакетного ELF")
        images.append(data[at:at + size])
        at += size
    demand(at == len(data) and len(images) == expected,
           "неправильне число пакетних ELF")
    return images


def parse_session(data: bytes, expected: int) -> list[bytes]:
    images, at = [], 0
    for _ in range(expected):
        demand(at + 5 <= len(data), "обірваний host статус сеансу")
        status = data[at]
        (size,) = struct.unpack_from("<I", data, at + 1)
        at += 5
        demand(0 < size <= 1048576 and at + size <= len(data),
               "обірване тіло відповіді сеансу")
        payload = data[at:at + size]
        at += size
        demand(status == 1, "неправильний сеансовий статус: " +
               payload[:160].decode("utf-8", errors="replace"))
        images.append(payload)
    demand(at == len(data), "після 16 відповідей залишилися зайві байти")
    return images


def run(argv: list[str], data: bytes | None = None, timeout: int = 90):
    result = subprocess.run(argv, input=data, capture_output=True,
                            check=False, timeout=timeout)
    demand(result.returncode == 0,
           "компілятор повернув rc=" + str(result.returncode) +
           ": " + result.stderr[:240].decode("utf-8", errors="replace"))
    return result


def valid_image(image: bytes) -> None:
    demand(120 < len(image) <= 1048576, "розмір ELF поза фізичною квотою")
    demand(image[:4] == b"\x7fELF", "ELF магія зіпсована")
    demand(image[4] == 2 and image[5] == 1, "не ELF64 little-endian")
    demand(struct.unpack_from("<H", image, 16)[0] == 3, "не ET_DYN PIE")
    demand(struct.unpack_from("<H", image, 18)[0] == 62, "не x86-64")
    demand(struct.unpack_from("<Q", image, 24)[0] == 120,
           "не pinned точка входу")


def selftest() -> None:
    sample = bytearray(121)
    sample[0:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<H", sample, 16, 3)
    struct.pack_into("<H", sample, 18, 62)
    struct.pack_into("<Q", sample, 24, 120)
    original = bytes(sample)
    valid_image(original)
    demand(parse_batch(frame(original), 1) == [original], "batch good")
    demand(parse_session(b"\x01" + frame(original), 1) == [original],
           "session good")
    bad_cases = [
        ("batch-short", lambda: parse_batch(b"\x02", 1)),
        ("batch-count", lambda: parse_batch(frame(original), 2)),
        ("batch-oversize", lambda: parse_batch(struct.pack("<I", 1048577), 1)),
        ("batch-truncated", lambda: parse_batch(frame(original)[:-1], 1)),
        ("session-short", lambda: parse_session(b"\x01", 1)),
        ("session-empty", lambda: parse_session(b"\x01\x00\x00\x00\x00", 1)),
        ("session-error", lambda: parse_session(b"\x00" + frame(b"відмова"), 1)),
        ("session-trailing", lambda: parse_session(b"\x01" + frame(original) + b"x", 1)),
        ("elf-magic", lambda: valid_image(b"x" + original[1:])),
        ("elf-arch", lambda: valid_image(original[:18] + b"\x03" + original[19:])),
    ]
    for name, case in bad_cases:
        try:
            case()
        except ValueError:
            continue
        raise AssertionError(name + ": негатив не відхилено")
    print("G6.173-SELFTEST-OK negatives=10")


def compile_mode(method: str, cli: dict[str, Path],
                 physical: list[bytes], source: list[Path],
                 place: Path) -> list[bytes]:
    if method == METHODS[0]:
        images = []
        for index, path in enumerate(source):
            outfile = place / f"{index:02d}.elf"
            run([str(cli["single"]), SINGLE_MODE, str(path), str(outfile)])
            images.append(outfile.read_bytes())
        return images
    input_stream = b"".join(frame(x) for x in physical)
    if method == METHODS[1]:
        answer = run([str(cli["batch"]), BATCH_MODE], input_stream)
        return parse_batch(answer.stdout, COUNT)
    if method == METHODS[2]:
        answer = run([str(cli["session"]), SESSION_MODE], input_stream)
        return parse_session(answer.stdout, COUNT)
    raise ValueError("невідомий host-режим компілятора")


def verify_physical(images: list[bytes], reference: list[bytes]) -> None:
    demand(len(images) == COUNT, "повернуто не 16 ELF")
    for i, (image, baseline) in enumerate(zip(images, reference)):
        valid_image(image)
        demand(image == baseline,
               "нестале ELF на фізичному .sens #" + str(i + 1))


def verify_executables(reference: list[bytes], fixture: Path,
                       readelf: str, place: Path) -> None:
    for index, image in enumerate(reference, 1):
        executable = place / f"{index:02d}.elf"
        executable.write_bytes(image)
        header = run([readelf, "-h", str(executable)], timeout=10).stdout
        segments = run([readelf, "-l", str(executable)], timeout=10).stdout
        demand(b"DYN" in header and b"Advanced Micro Devices X86-64" in header,
               "машинний ELF64 PIE не підтверджено")
        demand(b"INTERP" not in segments and b"DYNAMIC" not in segments,
               "машинний ELF має неочікувану динамічну залежність")
        executable.chmod(0o700)
        result = run([str(executable)], timeout=5)
        expected = (fixture / f"{index:02d}.expected.sens").read_bytes()
        demand(result.stdout == expected, "машинні T5M байти не збіглись")


def verify_negative(cli: dict[str, Path], fixture: Path, folder: Path):
    source = (fixture / "bad-t5m.sens").read_bytes()
    demand(source, "відсутній хибний фізичний T5M-свідок")
    broken_batch = subprocess.run(
        [str(cli["batch"]), BATCH_MODE], input=frame(source),
        capture_output=True, check=False, timeout=20)
    demand(broken_batch.returncode == 2 and broken_batch.stdout == b"" and
           b"ВІДМОВА" in broken_batch.stderr,
           "пакет не відмовив fail-closed")
    broken_session = subprocess.run(
        [str(cli["session"]), SESSION_MODE], input=frame(source),
        capture_output=True, check=False, timeout=20)
    demand(broken_session.returncode == 0 and broken_session.stderr == b"" and
           broken_session.stdout.startswith(b"\x00"),
           "хибний T5M отримав успішний ELF або порушив сеанс")
    try:
        parse_session(broken_session.stdout, 1)
    except ValueError:
        pass
    else:
        raise AssertionError("помилковий ELF прийнято зі статусом 0")
    output = folder / "must-not-exist.elf"
    bad_source = fixture / "bad-t5m.sens"
    single = subprocess.run([str(cli["single"]), SINGLE_MODE,
                            str(bad_source), str(output)],
                            capture_output=True, check=False, timeout=20)
    demand(single.returncode == 2 and not output.exists(),
           "хибний single CLI опублікував файл")


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--самоперевірка":
        selftest()
        return
    if len(sys.argv) != 7:
        raise SystemExit("аргументи: одиночний, пакетний, сеанс, fixtures, readelf, JSON")
    demand(platform.system() == "Linux" and platform.machine() == "x86_64",
           "потрібен реальний Linux x86-64")
    cli = {k: Path(s).resolve() for k, s in
           zip(["single", "batch", "session"], sys.argv[1:4])}
    fixture = Path(sys.argv[4]).resolve()
    readelf = sys.argv[5]
    report = Path(sys.argv[6]).resolve()
    source = [fixture / f"{i:02d}.sens" for i in range(1, COUNT + 1)]
    physical = [p.read_bytes() for p in source]
    demand(all(0 < len(p) <= 65536 for p in physical),
           "пошкоджено фізичні fixture")
    source_hashes = [sha256(p) for p in physical]
    methods = list(METHODS)
    orders = [list(p) for p in itertools.permutations(methods)]
    demand(len(orders) == REPEATS, "невірний збалансований порядок")
    with tempfile.TemporaryDirectory(prefix="sens-kompiliatsiia-") as td:
        folder = Path(td)
        reference = compile_mode(methods[0], cli, physical, source,
                                 folder / "single-baseline")
        # Directory for single baseline must exist BEFORE running compiler.
        verify_physical(reference, reference)
        for method in methods[1:]:
            images = compile_mode(method, cli, physical, source, folder)
            verify_physical(images, reference)
        verify_executables(reference, fixture, readelf, folder)
        verify_negative(cli, fixture, folder)
        # Відокремлений непомірюваний прогрів усіх процесних шляхів.
        for method in methods:
            place = folder / ("warm-" + method)
            place.mkdir()
            verify_physical(compile_mode(method, cli, physical, source, place),
                            reference)
        samples = {name: [] for name in methods}
        measured = []
        for index, order in enumerate(orders):
            round_row = []
            for method in order:
                place = folder / f"measured-{index}-{method}"
                place.mkdir()
                begin = time.perf_counter_ns()
                images = compile_mode(method, cli, physical, source, place)
                elapsed = time.perf_counter_ns() - begin
                demand(elapsed > 0, "некоректний час")
                verify_physical(images, reference)
                samples[method].append(elapsed)
                round_row.append({"метод": method, "стіна_нс": elapsed})
            measured.append(round_row)
        result = {
            "схема": "sens-native-compiler-latency/1",
            "джерело_законів": "pinned-sens",
            "pin": PIN,
            "фізичні_програми": COUNT,
            "sha256_джерел": source_hashes,
            "sha256_машин": [sha256(x) for x in reference],
            "компілятори": {
                name: {"раунди_нс": samples[name],
                       "медіана_нс": int(statistics.median(samples[name])),
                       "мінімум_нс": min(samples[name]),
                       "максимум_нс": max(samples[name])}
                for name in methods
            },
            "порядок_раундів": measured,
            "прогрівів_на_метод": 1,
            "раундів_на_метод": REPEATS,
            "характеристика": "end-to-end host wall time: FPC startup/files/pipe/pinned admission/ELF",
            "попередження": "Різні host API мають різні файлові та pipe накладні витрати; це не швидкість виконання SENS.",
            "енергія": "NOT_MEASURED",
            "апаратний_RAPL": "NOT_MEASURED",
            "семантика": "16 реально виконаних ELF перевірено з pinned фізичними expected; окремий незалежний oracle не запускається тут",
        }
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text(json.dumps(result, ensure_ascii=False, indent=2,
                                     sort_keys=True) + "\n", encoding="utf-8")
        reread = json.loads(report.read_text(encoding="utf-8"))
        demand(reread["енергія"] == "NOT_MEASURED" and
               len(reread["порядок_раундів"]) == 6,
               "невалідний або неправдиво позначений звіт")
    print("G6.173-КОМПІЛЯТОР-ЧАС-ПЕРЕВІРЕНО cases=16 methods=3 rounds=6 "
          "machine=16 selftest=10 negatives=3 energy=NOT_MEASURED")


if __name__ == "__main__":
    main()
