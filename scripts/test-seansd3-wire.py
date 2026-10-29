#!/usr/bin/env python3
"""G5.55: справжній живий FPC/D3 процес, без нових законів SENS.
На вході приватний кадр u32le + UTF-8 «ук», не canonical .sens.
Вихід — u32le count, повтор status/u64 form/u32 позиції/u32 довжина/UTF-8.
Очікування D3 нижче — з уже злитого scripts/test-sessiond3.pas.
"""
import os
import select
import struct
import subprocess
import sys
from pathlib import Path


def need(condition, why):
    if not condition:
        raise AssertionError(why)


def pack(data):
    return struct.pack("<I", len(data)) + data


def read_exact(process, length):
    out = bytearray()
    while len(out) < length:
        ready, _, _ = select.select([process.stdout.fileno()], [], [], 10)
        need(bool(ready), "не отримано повний результат живого D3-сеансу")
        part = os.read(process.stdout.fileno(), length - len(out))
        need(bool(part), "потік закрився посеред відповіді")
        out.extend(part)
    return bytes(out)


def transact(process, text):
    need(process.poll() is None, "сеанс завершився до наступного запиту")
    process.stdin.write(pack(text))
    process.stdin.flush()
    count = struct.unpack("<I", read_exact(process, 4))[0]
    need(count <= 4096, "завелика відповідь host-протоколу")
    rows = []
    for _ in range(count):
        status, form, offset, line, column, size = struct.unpack(
            "<BQIIII", read_exact(process, 25)
        )
        need(status in (0, 1) and size <= 65536, "пошкоджена структура host-відповіді")
        payload = read_exact(process, size)
        rows.append((status, form, offset, line, column, payload))
    return rows


def matched(row, value, form):
    need(row[0] == 0 and row[1] == form and row[5] == value,
         f"точна D3 відповідь відрізняється: {row!r}")


def test_live(binary, root):
    process = subprocess.Popen(
        [str(binary), "external/sens"],
        cwd=root, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, bufsize=0,
    )
    try:
        first = transact(process, "так ні (сполучити так ())".encode())
        need(len(first) == 3, "втрачено кілька форм в одному host-кадрі")
        matched(first[0], b"1", 1)
        matched(first[1], b"0", 2)
        matched(first[2], b"(1)", 3)

        second = transact(process, "(невідома ()) ні".encode("utf-8"))
        need(len(second) == 2 and second[0][0] == 1 and
             second[0][1] == 4 and bool(second[0][5]),
             "не отримано діагностики невідомої форми")
        need(second[0][2:5] == (2, 1, 2),
             "втрачено точну позицію помилки")
        matched(second[1], b"0", 5)

        quoted = transact(process, "(як-є кіт)".encode("utf-8"))
        need(len(quoted) == 1, "втрата української D7-проєкції")
        matched(quoted[0], b"(1110010 1110011 1101110)", 6)

        need(transact(process, b"") == [], "порожній запит створив виклик")
        matched(transact(process, "ні".encode())[0], b"0", 7)

        malformed = transact(process, b"\xc0")
        need(len(malformed) == 1 and malformed[0][0] == 1 and
             malformed[0][1] == 7 and bool(malformed[0][5]),
             "некоректний UTF-8 не відхилено без обнулення сеансу")
        matched(transact(process, "так".encode())[0], b"1", 8)

        # Реальні 128 окремих запросів не повинні заповнювати FIFO,
        # бо кожна відповідь негайно читається через Drain.
        for index in range(128):
            expected = b"1" if index % 2 == 0 else b"0"
            rows = transact(process, b"\xd1\x82\xd0\xb0\xd0\xba" if index % 2 == 0
                            else b"\xd0\xbd\xd1\x96")
            need(len(rows) == 1, "розійшлася кількість відповідей")
            matched(rows[0], expected, 9 + index)

        process.stdin.close()
        need(process.wait(timeout=10) == 0, "чистий EOF закрив сеанс із помилкою")
        need(process.stdout.read() == b"", "зайві байти після останнього host-кадру")
        need(process.stderr.read() == b"", "помилка в stderr успішного сеансу")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=10)
    print("СЕАНС-Д3-ЖИВИЙ-ГАРАЗД кадри=135 форми=136 відмови=2 позиції=так D7=ук")


def test_rejections(binary, root):
    bad = [
        ("неповний заголовок", b"\x04\x00"),
        ("неповне тіло", struct.pack("<I", 5) + b"\xd1\x82"),
        ("перевищення 65536", struct.pack("<I", 65537)),
    ]
    for name, data in bad:
        result = subprocess.run(
            [str(binary), "external/sens"], input=data, cwd=root,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=12,
            check=False,
        )
        need(result.returncode == 2 and result.stdout == b"" and
             "СЕАНС-Д3-ПОМИЛКА:".encode() in result.stderr,
             f"негативний host-кадр прийнятий або дав stdout: {name}")
    noargs = subprocess.run([str(binary)], cwd=root, capture_output=True,
                            timeout=10, check=False)
    need(noargs.returncode == 64 and noargs.stdout == b"",
         "помилковий виклик без pinned root допущено")
    print("СЕАНС-Д3-НЕГАТИВИ-ГАРАЗД неповний-заголовок неповне-тіло межа=65536")


if __name__ == "__main__":
    root = Path(sys.argv[2]).resolve()
    binary = Path(sys.argv[1]).resolve()
    test_live(binary, root)
    test_rejections(binary, root)
