#!/usr/bin/env python3
"""G5.67: механічний байтовий доказ реального FPC Core1 host-сеансу.

Вхід і вихід кадровані лише для host; усередині — ті самі фізичні
T5M байти, що вже виконуються самостійним TCore1FirstRuntime.
"""
from __future__ import annotations

import argparse
import struct
import subprocess
from pathlib import Path


def frame(data: bytes) -> bytes:
    return struct.pack('<I', len(data)) + data


def call(binary: Path, root: Path, data: bytes, *, args=None, expected_rc=0) -> tuple[bytes, bytes]:
    command = [str(binary), '--сеанс-core1', str(root)] if args is None else [str(binary), *args]
    result = subprocess.run(command, input=data, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=60, check=False)
    assert result.returncode == expected_rc, (
        f'неочікуваний код {result.returncode} != {expected_rc}; '
        f'stderr={result.stderr.decode("utf8", errors="replace")}')
    # FPC heaptrc іноді друкує 0-блоковий звіт у stderr.
    if b'unfreed memory blocks' in result.stderr:
        assert b'0 unfreed memory blocks' in result.stderr, result.stderr
    return result.stdout, result.stderr


def replies(data: bytes) -> list[tuple[int, bytes]]:
    result = []
    at = 0
    while at < len(data):
        assert len(data) - at >= 5, 'обірвана відповідь Core1'
        status = data[at]
        size = struct.unpack_from('<I', data, at + 1)[0]
        at += 5
        assert status in (0, 1) and 1 <= size <= 65536
        assert len(data) - at >= size, 'обірване T5M/діагностика'
        result.append((status, data[at:at + size]))
        at += size
    return result


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument('binary', type=Path)
    p.add_argument('root', type=Path)
    p.add_argument('fixtures', type=Path)
    args = p.parse_args()
    good = (args.fixtures / 'one.sens').read_bytes()
    expected = (args.fixtures / 'one.expected.sens').read_bytes()
    bad_t5m = good + bytes([243])
    bad_lisp = (args.root / 'external/sens/lib/core1.lisp').read_bytes()
    assert good and expected and bad_lisp

    # 32 справжніх виклики у ЄДИНОМУ FPC процесі із тим самим runtime.
    # Між чотирма блоками вклинено три різні відмови окремої форми.
    payloads = [good] * 8 + [bad_t5m] + [good] * 8 + [bad_lisp]
    payloads += [good] * 8 + [bytes([255])] + [good] * 8
    out, _ = call(args.binary, args.root, b''.join(map(frame, payloads)))
    observed = replies(out)
    assert len(observed) == len(payloads), (len(observed), len(payloads))
    positives = errors = 0
    for item, (status, answer) in zip(payloads, observed):
        if item == good:
            assert status == 0 and answer == expected, (status, answer, expected)
            positives += 1
        else:
            assert status == 1 and answer, (status, answer)
            answer.decode('utf-8', errors='strict')
            errors += 1
    assert positives == 32 and errors == 3

    # Чистий EOF успішний. Неправильне кадрування — фатальне,
    # ніякої часткової відповіді за НЕЗАВЕРШЕНИЙ кадр.
    out, _ = call(args.binary, args.root, b'')
    assert out == b''
    fatal = [b'\0\0\0\0', struct.pack('<I', 65537), b'\x01',
             struct.pack('<I', len(good) + 1) + good]
    for invalid in fatal:
        out, err = call(args.binary, args.root, invalid, expected_rc=2)
        assert out == b'' and 'CORE1-СЕАНС-ПОМИЛКА:'.encode() in err, err

    # Раніше завершений кадр залишається видимим, але після fatal
    # некоректного другого заголовка НОВОЇ відповіді вже немає.
    out, err = call(args.binary, args.root, frame(good) + b'\x01', expected_rc=2)
    assert replies(out) == [(0, expected)] and b'CORE1-' in err

    out, err = call(args.binary, args.root, frame(good),
                    args=['--невідомий-режим', str(args.root)], expected_rc=64)
    assert out == b'' and 'Використання:'.encode() in err
    print('CORE1-СЕАНС-ГАРАЗД FPC=реальний кадри=35 успіхи=32 '
          'відмови-форм=3 фатальні-кадри=5 runtime=один '
          'відновлення=так stdout=T5M-побайтово')


if __name__ == '__main__':
    main()
