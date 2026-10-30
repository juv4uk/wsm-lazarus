#!/usr/bin/env python3
"""G6.163 — перевірка справжнього постійного FPC→ELF host-сеансу."""
from __future__ import annotations

import os
from pathlib import Path
import select
import struct
import subprocess
import sys
import tempfile
import time

MODE = "--компілювати-фізичний-сеанс"
SINGLE = "--скомпілювати-фізичну-форму"
TERMINAL = "ШИРОКИЙ-СЕАНС-ВІДМОВА:".encode()


def input_frame(data: bytes) -> bytes:
    return struct.pack("<I", len(data)) + data


def read_exact(pipe, length: int) -> bytes:
    result = bytearray()
    end = time.monotonic() + 40
    while len(result) < length:
        remaining = end - time.monotonic()
        if remaining <= 0:
            raise AssertionError(f"зациклення host-сеансу: {len(result)}/{length}")
        ready, _, _ = select.select([pipe], [], [], remaining)
        assert ready, "компілятор не відповів на завершений кадр"
        data = os.read(pipe.fileno(), length - len(result))
        assert data, "компілятор передчасно завершив stdout"
        result.extend(data)
    return bytes(result)


def response(pipe) -> tuple[int, bytes]:
    head = read_exact(pipe, 5)
    code = head[0]
    size, = struct.unpack_from("<I", head, 1)
    assert code in (0, 1) and 0 < size <= 1048576, (code, size)
    if code == 0:
        assert size <= 4096
    return code, read_exact(pipe, size)


def oracle_case(binary: Path, human: Path, kind: str, a: str, b: str,
                expected: str) -> None:
    if kind == "zero":
        expression = f"(нуль? {a})"
    elif kind == "less":
        expression = f"(менше? {a} {b})"
    elif kind == "greater":
        expression = f"(більше? {a} {b})"
    elif kind == "abs":
        expression = f"(модуль {a})"
    else:
        raise AssertionError(kind)
    human.write_text(expression + "\n", encoding="utf-8")
    out = subprocess.run([str(binary), str(human)], capture_output=True,
                         timeout=70, check=False)
    assert out.returncode == 0 and not out.stderr, (kind, out.stderr)
    assert out.stdout == (expected + "\n").encode(), (kind, out.stdout)


def terminal_case(exe: Path, label: str, data: bytes, expected_code: int = 2):
    run = subprocess.run([str(exe), MODE], input=data,
                         capture_output=True, timeout=30, check=False)
    assert run.returncode == expected_code, (label, run.returncode, run.stderr)
    assert run.stdout == b"", (label, len(run.stdout))
    assert TERMINAL in run.stderr, (label, run.stderr)


def main():
    if len(sys.argv) != 5:
        raise SystemExit("потрібні сеанс-CLI, одиночний CLI, фізичні fixtures, readelf")
    exe, single, fixtures = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve()
    readelf = sys.argv[4]
    oracle = os.environ.get("SENS_ORACLE_BIN")
    oracle_exe = Path(oracle).resolve() if oracle else None
    rows = [(x.split("\t")) for x in (fixtures / "cases.tsv").read_text(encoding="utf-8").splitlines()]
    assert len(rows) == 16 and all(len(r) == 6 for r in rows)
    bad_names = [
        "bad-t5m", "two-roots", "unclosed", "root-atom",
        "dotted", "bad-zero-arity", "bad-zero-d1", "bad-zero-empty",
        "bad-less-arity", "bad-greater-arity", "bad-abs-arity", "bad-abs-d3",
    ]

    proc = subprocess.Popen([str(exe), MODE], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            bufsize=0)
    tested = 0
    rejected = 0
    with tempfile.TemporaryDirectory(prefix="sens-sesiia-elf-") as td:
        directory = Path(td)
        for index, row in enumerate(rows):
            label, kind, a, b, expected, width = row
            assert label == f"{index + 1:02d}"
            if index < len(bad_names):
                bad = (fixtures / (bad_names[index] + ".sens")).read_bytes()
                proc.stdin.write(input_frame(bad))
                proc.stdin.flush()
                status, message = response(proc.stdout)
                assert status == 0 and message, (bad_names[index], status)
                rejected += 1
            physical = fixtures / (label + ".sens")
            proc.stdin.write(input_frame(physical.read_bytes()))
            proc.stdin.flush()
            status, image = response(proc.stdout)
            assert status == 1, (label, image)
            assert image.startswith(b"\x7fELF"), label
            executable = directory / (label + ".elf")
            baseline = subprocess.run([str(single), SINGLE, str(physical),
                                       str(executable)], capture_output=True,
                                      timeout=30, check=False)
            assert baseline.returncode == 0, (label, baseline.stderr)
            assert executable.read_bytes() == image, "сеанс змінив ELF " + label
            sections = subprocess.run([readelf, "-h", str(executable)],
                                      capture_output=True, timeout=5, check=True)
            assert b"Advanced Micro Devices X86-64" in sections.stdout
            assert b"DYN" in sections.stdout
            os.chmod(executable, 0o700)
            machine = subprocess.run([str(executable)], capture_output=True,
                                     timeout=5, check=False)
            assert machine.returncode == 0 and not machine.stderr, (label, machine.stderr)
            assert machine.stdout == (fixtures / (label + ".expected.sens")).read_bytes(), label
            if oracle_exe:
                oracle_case(oracle_exe, directory / (label + ".lisp"),
                            kind, a, b, expected)
            tested += 1

        # Нульова host-довжина — відновлювана відмова, а не D3:000.
        proc.stdin.write(struct.pack("<I", 0))
        proc.stdin.flush()
        status, message = response(proc.stdout)
        assert status == 0 and "порожня".encode() in message, message
        rejected += 1
        # Далі знову компілюється справжня фізична програма того ж процесу.
        proc.stdin.write(input_frame((fixtures / "01.sens").read_bytes()))
        proc.stdin.flush()
        status, image = response(proc.stdout)
        assert status == 1 and image == (directory / "01.elf").read_bytes()
        tested += 1

    proc.stdin.close()
    tail = proc.stdout.read()
    err = proc.stderr.read()
    rc = proc.wait(timeout=30)
    assert rc == 0 and tail == b"", (rc, tail, err)
    assert TERMINAL not in err, err
    assert tested == 17 and rejected == 13

    # Некоректне host-кадрування відхиляємо термінально.
    terminal_case(exe, "порожній сеанс", b"")
    terminal_case(exe, "обірваний заголовок", b"\x01\x02")
    terminal_case(exe, "обірване фізичне тіло", struct.pack("<I", 4) + b"x")
    terminal_case(exe, "завелика фізична довжина", struct.pack("<I", 65537))
    terminal_case(exe, "переповнена довжина", struct.pack("<I", 0xffffffff))
    wrong = subprocess.run([str(exe)], capture_output=True, timeout=10, check=False)
    assert wrong.returncode == 64 and not wrong.stdout and TERMINAL in wrong.stderr

    print("G6.163-СЕАНС-ELF-OK machine=17 recoverable=13 terminal=6 oracle=" +
          ("16" if oracle_exe else "0"))


if __name__ == "__main__":
    main()
