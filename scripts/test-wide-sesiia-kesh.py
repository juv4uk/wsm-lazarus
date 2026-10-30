#!/usr/bin/env python3
"""G6.168: точнобайтовий кеш уже перевіреного ELF у постійному FPC-сеансі.
Жодного семантичного оракула: baseline = той самий non-cache WideIR.
Підсумкові фізичні T5M результати — чинні pinned fixture.
"""
from __future__ import annotations

import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path


def frame(data: bytes) -> bytes:
    return struct.pack("<I", len(data)) + data


def run(exe: Path, mode: str, data: bytes) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        [str(exe), mode], input=data, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=180, check=False,
    )


def parse(data: bytes) -> list[tuple[int, bytes]]:
    result: list[tuple[int, bytes]] = []
    pos = 0
    while pos < len(data):
        assert pos + 5 <= len(data), "обірвана host-відповідь"
        status = data[pos]
        length = struct.unpack_from("<I", data, pos + 1)[0]
        pos += 5
        assert status in (0, 1), "невідомий host-статус"
        assert 0 < length <= 1024 * 1024, "неприпустима довжина ELF/діагностики"
        assert pos + length <= len(data), "обірвана відповідь"
        result.append((status, data[pos:pos + length]))
        pos += length
    return result


def expect_heap_clean(log: bytes) -> None:
    if b"unfreed memory blocks" in log:
        assert re.search(rb"(?:^|\s)0 unfreed memory blocks", log), log


def main() -> None:
    assert len(sys.argv) == 3, "потрібні шлях до ELF-компілятора та фізичних fixtures"
    exe = Path(sys.argv[1]).resolve()
    fixtures = Path(sys.argv[2]).resolve()
    a = (fixtures / "01.sens").read_bytes()
    b = (fixtures / "02.sens").read_bytes()
    c = (fixtures / "03.sens").read_bytes()
    assert len({a, b, c}) == 3, "джерела мають бути фізично різними"

    # 13 host-кадрів: 11 успіхів, 2 відмови; 7 точних збігів із останнім
    # успішним кадром, 4 miss (01/02/03/01); відмови НЕ витісняють.
    sources = [a, a, b, b, b, b"\xff", b, c, c, a, b"", a, a]
    assert len(sources) == 13
    requests = b"".join(frame(source) for source in sources)

    old = run(exe, "--компілювати-фізичний-сеанс", requests)
    cached = run(exe, "--компілювати-фізичний-сеанс-кеш", requests)
    assert old.returncode == 0, (old.returncode, old.stderr)
    assert cached.returncode == 0, (cached.returncode, cached.stderr)
    expect_heap_clean(old.stderr)
    expect_heap_clean(cached.stderr)
    assert "КЕШ-СЕАНС-ГОТОВО".encode("utf-8") not in old.stderr
    expected_stats = "КЕШ-СЕАНС-ГОТОВО hits=7 misses=4".encode("utf-8")
    assert expected_stats in cached.stderr, cached.stderr
    assert old.stdout == cached.stdout, "opt-in кеш змінив host-протокол/ELF"
    replies = parse(cached.stdout)
    assert len(replies) == len(sources), "втрачено фізичний кадр"
    positives = 0
    negatives = 0
    with tempfile.TemporaryDirectory(prefix="sens-kesh-") as tmp:
        for i, ((status, payload), source) in enumerate(zip(replies, sources)):
            if source in (b"", b"\xff"):
                assert status == 0 and payload, ("відмову перетворено на успіх", i)
                negatives += 1
                continue
            assert status == 1 and payload.startswith(b"\x7fELF"), (i, status)
            positives += 1
            # Кожне з трьох фізичних тіл запускаємо як Linux x86-64 ELF64.
            if source not in (a, b, c) or source != sources[i]:
                raise AssertionError("втрачено точні фізичні байти")
        for i, (source, tag) in enumerate(((a, "01"), (b, "02"), (c, "03"))):
            indices = [j for j, item in enumerate(sources) if item == source]
            output = replies[indices[0]][1]
            assert all(replies[j][1] == output for j in indices)
            elf = Path(tmp) / f"{tag}.elf"
            elf.write_bytes(output)
            elf.chmod(0o700)
            completed = subprocess.run(
                [str(elf)], capture_output=True, timeout=5, check=False,
            )
            assert completed.returncode == 0 and completed.stderr == b"", (
                tag, completed.returncode, completed.stderr,
            )
            expected = (fixtures / f"{tag}.expected.sens").read_bytes()
            assert completed.stdout == expected, f"{tag}: ELF != canonical T5M"
    assert positives == 11 and negatives == 2, (positives, negatives)

    # Terminal host-протокол не може видати навіть фрагмент результату.
    bad_frames = [
        b"", b"\x01\x00", struct.pack("<I", 4) + b"\x11",
        struct.pack("<I", 65537),
    ]
    for bad in bad_frames:
        for mode in ("--компілювати-фізичний-сеанс",
                     "--компілювати-фізичний-сеанс-кеш"):
            rejected = run(exe, mode, bad)
            assert rejected.returncode == 2 and rejected.stdout == b"", (
                mode, bad, rejected.returncode, rejected.stderr,
            )
            assert "ШИРОКИЙ-СЕАНС-ВІДМОВА".encode("utf-8") in rejected.stderr
            expect_heap_clean(rejected.stderr)

    wrong = run(exe, "--невідомий-режим", frame(a))
    assert wrong.returncode == 64 and wrong.stdout == b"", wrong.stderr
    print("G6.168-КЕШ-СЕАНС-PASS frames=13 successful=11 negative=2 "
          "hits=7 misses=4 executed=3 terminal=8 oracle=NOT-CHECKED "
          "energy=NOT-MEASURED")


if __name__ == "__main__":
    main()
