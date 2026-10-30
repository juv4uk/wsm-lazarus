#!/usr/bin/env python3
"""G6.177 — реальний двомісний LRU кеш у FPC сеансі.

HOST LE32 кадри, не безперервний SENS потік. Усі мовні відповіді
порівнюємо лише з уже наявними canonical T5M свідками pinned SENS.
Нуль нових законів, жодного D7 dispatch або Core1 копіювання.
"""
from __future__ import annotations

import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

NORMAL = "--компілювати-фізичний-сеанс"
ONE = "--компілювати-фізичний-сеанс-кеш"
TWO = "--компілювати-фізичний-сеанс-кеш-2"


def frame(data: bytes) -> bytes:
    return struct.pack("<I", len(data)) + data


def request(exe: Path, mode: str, payloads: list[bytes],
            timeout: int = 100) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        [str(exe), mode],
        input=b"".join(frame(x) for x in payloads),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=timeout, check=False,
    )


def parse_reply(data: bytes) -> list[tuple[int, bytes]]:
    result: list[tuple[int, bytes]] = []
    pos = 0
    while pos < len(data):
        assert pos + 5 <= len(data), "неповний host-заголовок"
        status = data[pos]
        length = struct.unpack_from("<I", data, pos + 1)[0]
        pos += 5
        assert status in (0, 1) and 0 < length <= 1048576, "host-статус/розмір"
        assert pos + length <= len(data), "обірваний ELF/діагностика"
        result.append((status, data[pos:pos + length]))
        pos += length
    return result


def heap_clean(stderr: bytes) -> None:
    if b"unfreed memory blocks" in stderr:
        assert re.search(rb"(?:^|\s)0 unfreed memory blocks", stderr), stderr


def run_checked(exe: Path, mode: str, payloads: list[bytes],
                hits: int | None = None, misses: int | None = None
                ) -> list[tuple[int, bytes]]:
    p = request(exe, mode, payloads)
    assert p.returncode == 0, (mode, p.returncode, p.stderr[-1200:])
    heap_clean(p.stderr)
    if mode == NORMAL:
        assert "КЕШ-СЕАНС-ГОТОВО".encode() not in p.stderr
        assert "КЕШ-2-СЕАНС-ГОТОВО".encode() not in p.stderr
    elif mode == ONE:
        expected = f"КЕШ-СЕАНС-ГОТОВО hits={hits} misses={misses}".encode()
        assert expected in p.stderr, (expected, p.stderr)
        assert "КЕШ-2-СЕАНС-ГОТОВО".encode() not in p.stderr
    else:
        expected = f"КЕШ-2-СЕАНС-ГОТОВО hits={hits} misses={misses}".encode()
        assert expected in p.stderr, (expected, p.stderr)
    return parse_reply(p.stdout)


def main() -> None:
    assert len(sys.argv) == 3, "потрібні FPC exe й тека фізичних свідків"
    exe = Path(sys.argv[1]).resolve()
    fixtures = Path(sys.argv[2]).resolve()
    a = (fixtures / "01.sens").read_bytes()
    b = (fixtures / "02.sens").read_bytes()
    c = (fixtures / "15.sens").read_bytes()
    assert a and b and c and len({a, b, c}) == 3
    # Та сама фізична довжина, але різні D12 біти й D1 відповіді.
    assert len(a) == len(b), "недостатній доказ неколізійності довжини"

    # A/B alternating: 62 успішних компіляцій у старому режимі,
    # 62 misses в одноклітинному cache, тільки 2 miss у двомісному.
    # Негативи всередині кадрів мають залишити LRU стан незмінним.
    cases = [a if i % 2 == 0 else b for i in range(62)]
    cases.insert(15, b"\xff")
    cases.insert(48, b"")
    assert len(cases) == 64
    ordinary = run_checked(exe, NORMAL, cases)
    single = run_checked(exe, ONE, cases, hits=0, misses=62)
    double = run_checked(exe, TWO, cases, hits=60, misses=2)
    assert ordinary == single == double, "кеш змінив результати ELF/diagnostic"
    assert len(double) == 64
    good = sum(s == 1 for s, _ in double)
    bad = sum(s == 0 for s, _ in double)
    assert (good, bad) == (62, 2), (good, bad)

    # Реальне виконання обох незалежних PIE, не тільки магія ELF.
    with tempfile.TemporaryDirectory(prefix="sens-kesh2-") as tmp:
        for label, physical in (("01", a), ("02", b)):
            index = cases.index(physical)
            status, image = double[index]
            assert status == 1 and image.startswith(b"\x7fELF")
            # Кожен повторний кадр має повернути той самий готовий образ.
            assert all(double[i] == (1, image)
                       for i, src in enumerate(cases) if src == physical)
            elf = Path(tmp) / (label + ".elf")
            elf.write_bytes(image)
            elf.chmod(0o700)
            executed = subprocess.run([str(elf)], capture_output=True,
                                      timeout=8, check=False)
            expected = (fixtures / (label + ".expected.sens")).read_bytes()
            assert (executed.returncode == 0 and executed.stderr == b"" and
                    executed.stdout == expected), (label, executed)

    # Реальний LRU: [A,B,A,C,B,B,A] => hit у A і другому B,
    # а новий C мусить витіснити B; наступний B витісняє A.
    eviction = [a, b, a, b"\xff", c, b, b, a]
    old = run_checked(exe, NORMAL, eviction)
    two = run_checked(exe, TWO, eviction, hits=2, misses=5)
    assert old == two
    assert len(two) == 8 and sum(s == 0 for s, _ in two) == 1
    assert two[3][1], "негатив має дати непорожню діагностику"

    # Термінаційні відмови до першого результату не друкують stdout.
    malformed = [b"", b"\x01\x00",
                 struct.pack("<I", 4) + b"\x00",
                 struct.pack("<I", 65537)]
    for input_bytes in malformed:
        p = subprocess.run([str(exe), TWO], input=input_bytes,
                           capture_output=True, timeout=12, check=False)
        assert p.returncode == 2 and not p.stdout, (
            input_bytes, p.returncode, p.stderr)
        assert "ШИРОКИЙ-СЕАНС-ВІДМОВА".encode() in p.stderr
        heap_clean(p.stderr)

    unknown = subprocess.run([str(exe), "--невідомо"],
                             input=frame(a), capture_output=True,
                             timeout=12, check=False)
    assert unknown.returncode == 64 and not unknown.stdout
    print("G6.177-КЕШ-2-ПРОЙДЕНО frames=64 good=62 negative=2 "
          "one-hits=0 one-misses=62 two-hits=60 two-misses=2 "
          "evict-hits=2 evict-misses=5 executed=2 terminal=4 "
          "oracle=NOT-CHECKED energy=NOT-MEASURED")


if __name__ == "__main__":
    main()
