#!/usr/bin/env python3
"""G5.63: межі приватного host-кадру реального FPC, не закон SENS."""
import os
import select
import struct
import subprocess
import sys
import tempfile
import time

if len(sys.argv) != 3:
    raise SystemExit("виклик: test-fizseans-mezhi.py sensfizseans senst5m")
SESSION, PACKER = sys.argv[1:]
LIMIT = 65536
CHECKS = 0

def require(value, explanation):
    global CHECKS
    CHECKS += 1
    if not value:
        raise AssertionError(explanation)

def physical_yes():
    # .words — лише тестова проєкція для наявного FPC-пакувальника.
    with tempfile.NamedTemporaryFile(suffix=".words") as f:
        f.write(b"1\n")
        f.flush()
        p = subprocess.run(
            [PACKER, "--пакувати-слова", f.name],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
    require(p.returncode == 0 and bool(p.stdout), "немає фізичного D1:1")
    require(not p.stderr, "пакувальник має зайву діагностику")
    return p.stdout

def frame(data):
    return struct.pack("<I", len(data)) + data

def read_exact(fd, count, deadline):
    out = bytearray()
    while len(out) < count:
        remaining = deadline - time.monotonic()
        require(remaining > 0, "час очікування живого сеансу вичерпано")
        ready, _, _ = select.select([fd], [], [], remaining)
        require(bool(ready), "не отримано відповіді до EOF")
        chunk = os.read(fd, count - len(out))
        require(bool(chunk), "обірвано відповідь фізичного host-кадру")
        out.extend(chunk)
    return bytes(out)

def reply(process):
    fd = process.stdout.fileno()
    deadline = time.monotonic() + 25
    status, at_word, size = struct.unpack("<BII", read_exact(fd, 9, deadline))
    require(status in (0, 1), "помилковий статус")
    require(0 < size <= LIMIT, "некоректна довжина відповіді")
    return status, at_word, read_exact(fd, size, deadline)

def same_process(p, pid, where):
    require(p.poll() is None and p.pid == pid, where + ": втрачено PID")

def test_exact_boundary(yes):
    # 0xF3 — заборонений фізичний T5M; 65536 байтів допустимі
    # тільки як ДОВЖИНА приватного host-кадру, не як мовна форма.
    bad_t5m = bytes([243]) * LIMIT
    p = subprocess.Popen(
        [SESSION, "--сеанс"], stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0
    )
    pid = p.pid
    try:
        p.stdin.write(frame(yes))
        p.stdin.flush()
        require(reply(p) == (0, 0, yes), "перший канонічний D1:1")
        same_process(p, pid, "до межі")
        p.stdin.write(frame(bad_t5m))
        p.stdin.flush()
        status, word, diagnosis = reply(p)
        require(status == 1 and word == 0, "гранична T5M-відмова убила host-сеанс")
        require(bool(diagnosis) and b"T5M" in diagnosis, "неповний provenance T5M")
        same_process(p, pid, "після межі")
        p.stdin.write(frame(yes))
        p.stdin.flush()
        require(reply(p) == (0, 0, yes), "немає відновлення після фізичної помилки")
        same_process(p, pid, "після відновлення")
        ready, _, _ = select.select([p.stdout.fileno()], [], [], 0.15)
        require(not ready, "зайвий/частковий stdout")
        p.stdin.close()
        require(p.wait(timeout=20) == 0, "невдале завершення за EOF")
        require(p.stdout.read() == b"", "зайві байти після EOF")
        require(p.stderr.read() == b"", "зайва stderr-діагностика")
    finally:
        if p.poll() is None:
            p.kill()
            p.wait(timeout=20)
        for stream in (p.stdin, p.stdout, p.stderr):
            if stream is not None and not stream.closed:
                stream.close()

def test_fatal_after_good(yes, broken, diagnostic, label):
    expected = struct.pack("<BII", 0, 0, len(yes)) + yes
    p = subprocess.run(
        [SESSION, "--сеанс"], input=frame(yes) + broken,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    require(p.returncode == 2, label + ": немає фатальної host-відмови")
    require(p.stdout == expected, label + ": частковий або втрачений stdout")
    require("ФІЗИЧНИЙ-СЕАНС-ПОМИЛКА".encode() in p.stderr,
            label + ": немає українського діагнозу")
    require(diagnostic.encode() in p.stderr, label + ": не та помилка")

# Типи: bytes є тимчасові фізичні T5M; Popen володіє PID/каналами,
# reply повертає tuple(status:u8, word:u32le, payload:bytes).
# Питання: чому status не D1? Чому межа кадру не закон SENS?
# Хто володіє stdout після EOF? Чому попередня відповідь зберігається?
# Чому незмінний PID доводить безперервність host-сеансу?
yes = physical_yes()
test_exact_boundary(yes)
test_fatal_after_good(yes, struct.pack("<I", LIMIT + 1),
                      "довжина", "65537 байтів")
test_fatal_after_good(yes, struct.pack("<I", LIMIT) + bytes([243]) * (LIMIT - 1),
                      "обірвано", "недописаний граничний кадр")
test_fatal_after_good(yes, struct.pack("<I", 0),
                      "довжина", "нульовий кадр")
print(f"ФІЗИЧНИЙ-СЕАНС-МЕЖІ-ГАРАЗД перевірок={CHECKS} "
      "межа=65536 відновлення=так частковий-stdout=ні")
