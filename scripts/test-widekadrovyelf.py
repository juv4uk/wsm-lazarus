#!/usr/bin/env python3
"""G6.159: фізичний host-кадр не змінює SENS координату чи результат ELF."""
from __future__ import annotations

import os
import pathlib
import struct
import subprocess
import sys
import tempfile

LIMIT = 16
MODE = "--скомпілювати-фізичні-кадри"
SINGLE = "--скомпілювати-фізичну-форму"
PREFIX = "ШИРОКІ-КАДРИ-ВІДМОВА:".encode("utf-8")


def frame(payload: bytes) -> bytes:
    return struct.pack("<I", len(payload)) + payload


def invoke(exe: pathlib.Path, source: bytes) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run([str(exe), MODE], input=source, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=80, check=False)


def decode_frames(raw: bytes) -> list[bytes]:
    images: list[bytes] = []
    offset = 0
    while offset < len(raw):
        assert offset + 4 <= len(raw), "неповний заголовок вихідного ELF"
        size, = struct.unpack_from("<I", raw, offset)
        offset += 4
        assert 120 < size <= 1048576, "невалідна довжина ELF64"
        assert offset + size <= len(raw), "обірване вихідне ELF тіло"
        image = raw[offset:offset + size]
        assert image.startswith(b"\x7fELF"), "не ELF64"
        images.append(image)
        offset += size
    return images


def reject(exe: pathlib.Path, label: str, source: bytes) -> None:
    result = invoke(exe, source)
    assert result.returncode == 2, (label, result.returncode, result.stderr)
    assert result.stdout == b"", (label, "частковий stdout", len(result.stdout))
    assert PREFIX in result.stderr, (label, result.stderr)


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit("потрібні: багатокадровий CLI, одиночний CLI, каталог fixtures, readelf")
    executable = pathlib.Path(sys.argv[1]).resolve()
    single = pathlib.Path(sys.argv[2]).resolve()
    fixture = pathlib.Path(sys.argv[3]).resolve()
    readelf = sys.argv[4]
    cases = [f"{i:02d}" for i in range(1, LIMIT + 1)]
    source = [(fixture / f"{label}.sens").read_bytes() for label in cases]
    assert all(0 < len(item) <= 65536 for item in source)
    positive = b"".join(frame(item) for item in source)

    result = invoke(executable, positive)
    assert result.returncode == 0, (result.returncode, result.stderr)
    assert PREFIX not in result.stderr
    images = decode_frames(result.stdout)
    assert len(images) == LIMIT, f"вихідних ELF: {len(images)}"

    with tempfile.TemporaryDirectory(prefix="sens-kadrovy-") as directory:
        folder = pathlib.Path(directory)
        for label, image in zip(cases, images):
            source_path = fixture / f"{label}.sens"
            expected_path = fixture / f"{label}.expected.sens"
            outfile = folder / f"{label}.elf"
            single_result = subprocess.run(
                [str(single), SINGLE, str(source_path), str(outfile)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=45, check=False)
            assert single_result.returncode == 0, (label, single_result.stderr)
            assert outfile.read_bytes() == image, f"{label}: ELF не збігається з single CLI"
            os.chmod(outfile, 0o700)
            header = subprocess.run([readelf, "-h", str(outfile)],
                                    capture_output=True, timeout=10, check=True).stdout
            assert b"Advanced Micro Devices X86-64" in header, label
            assert b"DYN" in header, label
            segments = subprocess.run([readelf, "-l", str(outfile)],
                                      capture_output=True, timeout=10, check=True).stdout
            assert b"INTERP" not in segments and b"DYNAMIC" not in segments, label
            executed = subprocess.run([str(outfile)], capture_output=True, timeout=5, check=False)
            assert executed.returncode == 0, (label, executed.returncode, executed.stderr)
            assert executed.stderr == b"", (label, executed.stderr)
            assert executed.stdout == expected_path.read_bytes(), f"{label}: неправильні фізичні T5M байти"

    # 12 незалежних негативів; у тому числі пізня помилка — ні одного ELF.
    bad = [
        ("порожній", b""),
        ("короткий заголовок", b"\x01"),
        ("нульова довжина", struct.pack("<I", 0)),
        ("довжина 65537", struct.pack("<I", 65537)),
        ("довжина 0xffffffff", struct.pack("<I", 0xFFFFFFFF)),
        ("обірване тіло", struct.pack("<I", len(source[0]) + 1) + source[0]),
        ("другий обірваний заголовок", frame(source[0]) + b"\x01\x02"),
        ("не T5M", frame(b"\xff")),
        ("текст замість фізичних байтів", frame("(додати 1 2)\n".encode("utf-8"))),
        ("пізня T5M помилка", frame(source[0]) + frame(b"\xff")),
        ("пізня нульова довжина", frame(source[0]) + struct.pack("<I", 0)),
        ("сімнадцятий кадр", positive + frame(source[0])),
    ]
    for label, payload in bad:
        reject(executable, label, payload)

    # Той самий процес після помилки не залишається живим/зіпсованим;
    # новий запуск повторює повну фізичну відповідь байт-в-байт.
    recovered = invoke(executable, positive)
    assert recovered.returncode == 0, recovered.stderr
    assert recovered.stdout == result.stdout, "недетерміновані кадри ELF"
    one = invoke(executable, frame(source[0]))
    assert one.returncode == 0, one.stderr
    assert decode_frames(one.stdout) == images[:1]
    print("G6.159-БАГАТОКАДРОВИЙ-ELF-ГОТОВО позитиви=16 негативи=12 відновлення=2")


if __name__ == "__main__":
    main()
