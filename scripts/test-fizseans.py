#!/usr/bin/env python3
"""G5.59: незалежна byte-exact перевірка приватного host-протоколу."""
import struct
import subprocess
import sys
import tempfile

session, packer = sys.argv[1:3]
checks = 0

def demand(value, label):
    global checks
    checks += 1
    if not value:
        raise AssertionError(label)

def pack(words):
    # Чинний FPC senst5m приймає ім'я файла, а не stdin.
    # Тимчасова людська бітова таблиця — лише тестовий механічний вхід.
    with tempfile.NamedTemporaryFile(suffix=".words") as source:
        source.write((words + "\n").encode())
        source.flush()
        p = subprocess.run(
            [packer, "--пакувати-слова", source.name],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True
        )
    demand(p.returncode == 0 and p.stdout, "пакувальник T5M")
    return p.stdout

def packet(data):
    return struct.pack("<I", len(data)) + data

def exchange(data, expected_count):
    p = subprocess.run(
        [session, "--сеанс"], input=data, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=30
    )
    demand(p.returncode == 0, "живий сеанс: " + p.stderr.decode(errors="replace"))
    demand(not p.stderr, "зайве stderr успішного фізичного сеансу")
    pos = 0
    replies = []
    for _ in range(expected_count):
        demand(pos + 9 <= len(p.stdout), "обірвано відповідь")
        status, word, size = struct.unpack_from("<BII", p.stdout, pos)
        pos += 9
        demand(size > 0 and size <= 65536, "неправильна довжина відповіді")
        demand(pos + size <= len(p.stdout), "пошкоджена межа відповіді")
        payload = p.stdout[pos:pos+size]
        pos += size
        replies.append((status, word, payload))
    demand(pos == len(p.stdout), "зайві байти stdout або зсув кадру")
    return replies

def fatal(data, label, completed=b""):
    p = subprocess.run(
        [session, "--сеанс"], input=data, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=30
    )
    demand(p.returncode != 0, label+": не відхилено")
    demand(p.stdout == completed, label+": втрачено попередні або додано часткові кадри")
    demand("ФІЗИЧНИЙ-СЕАНС-ПОМИЛКА".encode() in p.stderr,
           label+": немає української діагностики")

yes = pack("1")
no = pack("0")
empty = pack("000")
quote = pack("10 001 1 01")
cons = pack("10 111 1 000 01")
expected_cons = pack("10 1 01")
bad_head = pack("10 000 000 01")
d7_data = pack("1111111")
two_roots = pack("1 0")
invalid_t5m = bytes([243])
requests = [yes, invalid_t5m, quote, bad_head, no, d7_data,
            empty, two_roots, cons, yes]
replies = exchange(b"".join(map(packet, requests)), len(requests))
for index, wanted in [(0,yes),(2,yes),(4,no),(6,empty),(8,expected_cons),(9,yes)]:
    demand(replies[index] == (0,0,wanted),
           "виконаний T5M не збігся байт-у-байт, пакет "+str(index))
for index, word in [(1,0),(3,None),(5,1),(7,2)]:
    status, at, diagnostic = replies[index]
    demand(status == 1, "не відхилено форму "+str(index))
    if word is not None:
        demand(at == word, "втрата фізичного індексу "+str(index))
    demand(diagnostic and not diagnostic.startswith(bytes([0])),
           "порожня діагностика")
demand(exchange(b"",0) == [], "чистий EOF без запитів")
demand(exchange(packet(yes),1) == [(0,0,yes)], "один host-кадр")
fatal(b"\x01\x00", "обірваний заголовок")
fatal(struct.pack("<I",5)+b"\x01", "обірване тіло")
fatal(struct.pack("<I",65537), "завеликий кадр")
fatal(struct.pack("<I",0), "порожній кадр")
fatal(packet(yes)+b"\x00", "пізній обірваний заголовок",
      struct.pack("<BII", 0, 0, len(yes)) + yes)
p = subprocess.run([session],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
demand(p.returncode == 64 and not p.stdout,"неявний режим")
print("ФІЗИЧНИЙ-СЕАНС-ГАРАЗД кадрів=10 результатів=6 "
      "відмов=4 відновлення=так T5M=байт-в-байт "
      "пошкоджений-EOF=відхилено перевірок="+str(checks))
print("ФІЗИЧНИЙ-СЕАНС-МЕЖА REPL=НЕ-ГОТОВИЙ "
      "Core4=НЕ-ВИКОНУЄТЬСЯ лексичні-визначення=НЕ-ДОВЕДЕНО")
