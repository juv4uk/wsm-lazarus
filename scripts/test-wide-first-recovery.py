#!/usr/bin/env python3
"""G6.188 — незалежна регресія відновлення після помилки між новими компіляціями.

Це тест host-сеансу, не читач SENS і не вимір часу. Фізичні packed .sens
програми породжує вже перевірений test-irwidefront.pas. Потік LE32
є виключно транспортом хоста. Ніяких текстових назв у semantic dispatch.
"""
from __future__ import annotations

import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

BASE = "--компілювати-фізичний-сеанс"
FAST = "--компілювати-фізичний-сеанс-швидкий-перший"
# 7 допустимих фізичних програм; 4 різні негативи В СЕРЕДИНІ сеансу.
# other-d5 — коректний фізичний T5M, але непідтримана виклична голова.
# bad-zero-arity — коректний T5M та підтримана голова, хибна арність.
# bad-t5m — неканонічні фізичні байти; empty — порожній host кадр.
SEQUENCE = (
    "01", "other-d5", "05", "bad-t5m", "03", "bad-zero-arity",
    "14", "16", "01", "empty", "05",
)
SUCCESS = (True, False, True, False, True, False, True, True, True, False, True)
assert len(SEQUENCE) == 11 and sum(SUCCESS) == 7


def pack(raw: bytes) -> bytes:
    """Borrowed raw bytes → new owned host packet (LE32 + фізичний T5M)."""
    return struct.pack("<I", len(raw)) + raw


def unpack(data: bytes, expected: int) -> list[tuple[int, bytes]]:
    """Fail-closed розбір host status і ELF/діагностики, без трактування SENS."""
    result: list[tuple[int, bytes]] = []
    offset = 0
    while offset < len(data):
        assert len(data) - offset >= 5, "обірваний host-заголовок відповіді"
        status, size = struct.unpack_from("<BI", data, offset)
        offset += 5
        assert status in (0, 1) and 0 < size <= 1048576, (status, size)
        assert offset + size <= len(data), "обірване host-тіло відповіді"
        result.append((status, data[offset:offset + size]))
        offset += size
    assert offset == len(data) and len(result) == expected, (
        "втрата/дублювання host-кадрів", len(result), expected
    )
    return result


def run(exe: Path, mode: str, frames: list[bytes]) -> list[tuple[int, bytes]]:
    call = subprocess.run(
        [str(exe), mode], input=b"".join(map(pack, frames)),
        capture_output=True, timeout=120, check=False,
    )
    assert call.returncode == 0, (mode, call.returncode, call.stderr[-1000:])
    assert call.stderr == b"", (mode, call.stderr[-1000:])
    return unpack(call.stdout, len(frames))


def execute_elf(image: bytes, expected: bytes, tmp: Path, label: str) -> None:
    """Owned ELF файл лише для механічного виконання; canonical stdout точний."""
    assert image.startswith(b"\x7fELF"), label
    path = tmp / (label + ".elf")
    path.write_bytes(image)
    path.chmod(0o700)
    outcome = subprocess.run([str(path)], capture_output=True,
                             timeout=10, check=False)
    assert outcome.returncode == 0 and outcome.stderr == b"", (
        label, outcome.returncode, outcome.stderr[-500:],
    )
    assert outcome.stdout == expected, "пошкоджено фізичний .sens stdout: " + label


def main() -> None:
    assert len(sys.argv) == 3, "потрібні FPC CLI та каталог фізичних свідків"
    exe, root = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    assert exe.is_file() and os.access(exe, os.X_OK)
    bodies = [(root / (name + ".sens")).read_bytes() for name in SEQUENCE]
    assert all(body or name == "empty" for name, body in zip(SEQUENCE, bodies))
    assert len(set(bodies)) == 9, "помилкова або дубльована fixture"
    baseline: list[tuple[int, bytes]] | None = None
    machine_runs = 0
    negatives = 0
    with tempfile.TemporaryDirectory(prefix="sens-vidnovlennia-pershoi-") as temp:
        directory = Path(temp)
        # Дві черговані пари сеансів: результати повинні лишатися однаковими
        # після повного перезапуску host-процесу, але без ELF-output cache.
        for round_index, order in enumerate(((BASE, FAST), (FAST, BASE))):
            for mode in order:
                answer = run(exe, mode, bodies)
                observed = tuple(status == 1 for status, _ in answer)
                assert observed == SUCCESS, (mode, observed)
                if baseline is None:
                    baseline = answer
                else:
                    assert answer == baseline, (
                        "fast-first повернув stale ELF або іншу діагностику", mode
                    )
                for index, ((status, image), name) in enumerate(
                    zip(answer, SEQUENCE)
                ):
                    if status == 0:
                        assert image and not image.startswith(b"\x7fELF")
                        negatives += 1
                        continue
                    expected = (root / (name + ".expected.sens")).read_bytes()
                    execute_elf(image, expected, directory,
                                f"{round_index}-{mode == FAST}-{index}")
                    machine_runs += 1

    assert machine_runs == 28 and negatives == 16
    print("ШВИДКИЙ-ПЕРШИЙ-ВІДНОВЛЕННЯ-PASS "
          "sessions=4 frames=44 success=28 negatives=16 "
          "machine=28 parity=byte-exact invalid-to-valid=yes "
          "oracle=NOT-CHECKED energy=NOT-MEASURED")


if __name__ == "__main__":
    main()
