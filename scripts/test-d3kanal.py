#!/usr/bin/env python3
"""G5.34 — механічні межі вже чинного Core4-host framing для справжнього D3.
Жодних SENS законів у Python: очікувані байти приходять із G3.17 fixtures.
"""
import os
import select
import struct
import subprocess
import sys
from pathlib import Path


def need(condition, message):
    if not condition:
        raise AssertionError(message)


def pack(payload):
    return struct.pack("<I", len(payload)) + payload


def read_exact(process, length):
    result = bytearray()
    while len(result) < length:
        readable, _, _ = select.select([process.stdout.fileno()], [], [], 12)
        need(bool(readable), "канал не відповів до закриття stdin")
        part = os.read(process.stdout.fileno(), length - len(result))
        need(bool(part), "канал обірвав фізичну відповідь")
        result.extend(part)
    return bytes(result)


def transact(process, payload, expected=None, error_piece=None):
    need(process.poll() is None, "процес завершився між кадрами")
    process.stdin.write(pack(payload))
    process.stdin.flush()
    header = read_exact(process, 5)
    status = header[0]
    size = struct.unpack("<I", header[1:])[0]
    need(0 < size <= 65536, "некоректна межа відповіді")
    answer = read_exact(process, size)
    if expected is not None:
        need(status == 0, f"несподівана D3 відмова: {answer!r}")
        need(answer == expected, "відповідь не тотожна фізичним T5M байтам")
    else:
        need(status == 1, "недопустимий D3 пакет виконався")
        need(bool(answer), "порожня діагностика")
        if error_piece is not None:
            need(error_piece in answer.decode("utf-8", "replace"),
                 "втрачено фізичну адресу D3 помилки")
    return status


def main():
    binary, fixtures, existing, root = sys.argv[1:]
    fixtures, existing = Path(fixtures), Path(existing)
    program = [binary, "--канал", "external/sens"]

    p = subprocess.Popen(program, cwd=root, stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         bufsize=0)
    pid = p.pid
    positives = ("one", "four", "64")
    try:
        for name in positives:
            payload = (fixtures / (name + ".sens")).read_bytes()
            answer = (fixtures / (name + "-answer.sens")).read_bytes()
            need(answer == (existing / (name + ".sens")).read_bytes(),
                 "наявні файловий D3 і fixtures розійшлися")
            transact(p, payload, expected=answer)
        negative = [
            ("late-bad", "форма=2 слово=2"),
            ("d12", None),
            ("65", None),
            ("bad-t5m", None),
        ]
        for name, diagnostic in negative:
            transact(p, (fixtures / (name + ".sens")).read_bytes(),
                     error_piece=diagnostic)
        transact(p, b"")
        # Відновлення після всіх п'яти семантичних відмов в тому самому PID.
        one = (fixtures / "one.sens").read_bytes()
        target = (fixtures / "one-answer.sens").read_bytes()
        transact(p, one, expected=target)
        need(p.pid == pid and p.poll() is None,
             "заміна процесу замість постійного каналу")
        p.stdin.close()
        p.wait(timeout=12)
        need(p.returncode == 2, "не збережено ознаку попередніх відмов")
        need(p.stdout.read() == b"", "зайві байти після останнього кадру")
        need(p.stderr.read() == b"", "неочікувана stderr-діагностика")
    finally:
        if p.poll() is None:
            p.kill()
            p.wait(timeout=8)

    malformed = [
        ("обірваний заголовок", b"\x01\x00"),
        ("обірвана T5M частина", struct.pack("<I", 6) + b"\x00"),
        ("понад межу", struct.pack("<I", 65537)),
    ]
    for label, request in malformed:
        x = subprocess.run(program, cwd=root, input=request,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           timeout=18, check=False)
        need(x.returncode != 0, "фатальний кадр помилково прийнятий: " + label)
        need(x.stdout == b"", "фатальний кадр опублікував байти: " + label)
        need("ПОМИЛКА-КАНАЛ-D3".encode("utf-8") in x.stderr,
             "немає stderr-повідомлення для " + label)

    # G5.49: інша ЯВНА host-назва потрібна чинному Batch=True
    # TCore4WireClient; той самий незалежний FPC D3 evaluator і кадри.
    paket = subprocess.Popen([binary, "--канал-пакет", "external/sens"],
                             cwd=root, stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             bufsize=0)
    try:
        packet_pid = paket.pid
        for name in ("one", "four", "64"):
            transact(paket, (fixtures / (name + ".sens")).read_bytes(),
                     expected=(fixtures / (name + "-answer.sens")).read_bytes())
        transact(paket, (fixtures / "late-bad.sens").read_bytes(),
                 error_piece="форма=2 слово=2")
        transact(paket, (fixtures / "four.sens").read_bytes(),
                 expected=(fixtures / "four-answer.sens").read_bytes())
        need(paket.pid == packet_pid and paket.poll() is None,
             "пакетний host-режим замінив PID замість відновлення")
        paket.stdin.close()
        paket.wait(timeout=12)
        need(paket.returncode == 2, "втрачено негативний завершальний статус")
        need(paket.stderr.read() == b"", "stderr забруднено пакетні кадри")
        need(paket.stdout.read() == b"", "пакетний канал має зайві байти")
    finally:
        if paket.poll() is None:
            paket.kill()
            paket.wait(timeout=8)

    print("КАНАЛ-D3-ГАРАЗД один-PID=так T5M=побайтово "
          "позитивних=4 відмовних-кадрів=5 "
          "фатальних-протокольних=3 відновлення=так "
          "Core4/REPL/D12+=НЕ-ДОВЕДЕНО")


if __name__ == "__main__":
    main()
