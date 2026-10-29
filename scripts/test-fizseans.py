#!/usr/bin/env python3
"""G5.59: незалежна byte-exact перевірка приватного host-протоколу."""
import os
import select
import struct
import subprocess
import sys
import tempfile
import time

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

# G5.60: живі запити, НЕ один заздалегідь закритий stdin.
# Popen володіє PID та host-потоками; кожна відповідь — новий
# кадр status:u8 + word:u32le + size:u32le + фізичний T5M або UTF-8.
# select із deadline доводить публікацію ДО EOF, без безмежного wait.
# Питання: чому status=1 не означає D1:0?
# Чому фізична відповідь мусить надійти до закриття stdin?
# Хто звільняє stdin/stdout/stderr при помилці?
# Чому timeout не є семантичним законом SENS?
def live_read_exact(fd, count, deadline):
    data = bytearray()
    while len(data) < count:
        left = deadline - time.monotonic()
        demand(left > 0, "живий фізичний сеанс не відповів до EOF")
        readable, _, _ = select.select([fd], [], [], left)
        demand(bool(readable), "живий фізичний сеанс: очікування вичерпане")
        chunk = os.read(fd, count - len(data))
        demand(bool(chunk), "живий фізичний сеанс: обірвано відповідь")
        data.extend(chunk)
    return bytes(data)

def live_read_reply(process):
    deadline = time.monotonic() + 15
    descriptor = process.stdout.fileno()
    status, word, size = struct.unpack(
        "<BII", live_read_exact(descriptor, 9, deadline)
    )
    demand(status in (0, 1), "живий сеанс: недопустимий status")
    demand(0 < size <= 65536, "живий сеанс: надмірний payload")
    return status, word, live_read_exact(descriptor, size, deadline)

def test_live_session():
    process = subprocess.Popen(
        [session, "--сеанс"], stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0
    )
    original_pid = process.pid
    try:
        for physical, expected, label in (
            (yes, (0, 0, yes), "перша фізична D1:1"),
            (invalid_t5m, None, "фізична відмова T5M"),
            (quote, (0, 0, yes), "цитата D3:001 після відмови"),
            (no, (0, 0, no), "остання фізична D1:0"),
        ):
            demand(process.poll() is None and process.pid == original_pid,
                   label + ": процес завершився або змінив PID")
            process.stdin.write(packet(physical))
            process.stdin.flush()
            actual = live_read_reply(process)
            if expected is None:
                status, word, reason = actual
                demand(status == 1 and word == 0 and bool(reason),
                       label + ": очікувалася точна негативна відповідь")
            else:
                demand(actual == expected, label + ": змінено бітову відповідь")
            demand(process.poll() is None, label + ": сеанс закрився до EOF")
        readable, _, _ = select.select(
            [process.stdout.fileno()], [], [], 0.1
        )
        demand(not readable, "живий сеанс: зайва відповідь без запиту")
        process.stdin.close()
        demand(process.wait(timeout=20) == 0,
               "живий сеанс: вихід після чистого EOF невдалий")
        demand(process.stdout.read() == b"",
               "живий сеанс: зайві кадри після EOF")
        demand(process.stderr.read() == b"",
               "живий сеанс: зайва stderr-діагностика")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=20)
        for stream in (process.stdin, process.stdout, process.stderr):
            if stream is not None and not stream.closed:
                stream.close()

# G5.62: той самий FPC host-сеанс читає u32le + packed T5M
# частинами. Поки кадр неповний, stdout не має містити АБСОЛЮТНО
# ЖОДНОГО байта, навіть часткового заголовка відповіді.
# Права власності: Popen управляє stdin/stdout/stderr та PID, фізичні
# bytes — Python test fixtures від справжнього FPC senst5m. Це не
# другий reader, не Lisp проєкція і не семантичний REPL.
# Чому кожен короткий read мусить чекати відсутніх байтів?
# Чому частковий stdout до завершення рамки порушує host-протокол?
# Чому відмова status=1 не еквівалентна D1:0?
# Хто гарантовано закриває процес/канали при збої assertion?
def partial_frame_silent(process, context):
    demand(process.poll() is None, context + ": виконавець завершився до EOF")
    readable, _, _ = select.select([process.stdout.fileno()], [], [], 0.15)
    demand(not readable, context + ": відповідь з'явилася до завершення кадру")
    demand(process.poll() is None, context + ": PID загублено до EOF")

def test_fragmented_session():
    demand(len(quote) >= 2, "не можна розділити фізичний D3 T5M")
    process = subprocess.Popen(
        [session, "--сеанс"], stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0
    )
    original_pid = process.pid
    frame = packet(quote)
    half = max(1, len(quote) // 2)
    try:
        # 1/4 заголовка: ще неможливо визначити host довжину.
        process.stdin.write(frame[:1])
        process.stdin.flush()
        partial_frame_silent(process, "неповний u32le заголовок")
        # Увесь заголовок без тіла: ще неможливо допускати D3 форму.
        process.stdin.write(frame[1:4])
        process.stdin.flush()
        partial_frame_silent(process, "відсутнє фізичне T5M тіло")
        # Перша частина тіла: навіть валідний префікс НЕ є формою.
        process.stdin.write(quote[:half])
        process.stdin.flush()
        partial_frame_silent(process, "неповне фізичне T5M тіло")
        # Тільки тепер канонічна D3 цитата може виконатися.
        process.stdin.write(quote[half:])
        process.stdin.flush()
        demand(live_read_reply(process) == (0, 0, yes),
               "розбитий T5M кадр змінив фізичну D3 відповідь")
        demand(process.poll() is None and process.pid == original_pid,
               "розбитий кадр перезапустив фізичний сеанс")
        # Наступний кадр помилковий, але його обробляє ТОЙ САМИЙ PID.
        process.stdin.write(packet(invalid_t5m))
        process.stdin.flush()
        status, word, diagnostic = live_read_reply(process)
        demand(status == 1 and word == 0 and bool(diagnostic),
               "після часткового кадру втрачено адресу фізичної відмови")
        demand(process.poll() is None and process.pid == original_pid,
               "помилка після фрагментації закрила host-сеанс")
        process.stdin.write(packet(no))
        process.stdin.flush()
        demand(live_read_reply(process) == (0, 0, no),
               "після фрагментації/відмови не виконано фізичний D1:0")
        partial_frame_silent(process, "зайва відповідь без нового запиту")
        process.stdin.close()
        demand(process.wait(timeout=20) == 0,
               "завершення розбитого фізичного сеансу після EOF")
        demand(process.stdout.read() == b"",
               "зайві байти stdout після EOF розбитого кадру")
        demand(process.stderr.read() == b"",
               "зайва stderr діагностика розбитого host-сеансу")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=20)
        for stream in (process.stdin, process.stdout, process.stderr):
            if stream is not None and not stream.closed:
                stream.close()

test_live_session()
test_fragmented_session()
p = subprocess.run([session],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
demand(p.returncode == 64 and not p.stdout,"неявний режим")
print("ФІЗИЧНИЙ-СЕАНС-ГАРАЗД кадрів=10 результатів=6 "
      "відмов=4 відновлення=так T5M=байт-в-байт "
      "пошкоджений-EOF=відхилено живі-кадри=4 до-EOF=так "
      "фрагменти=3 ранній-вивід=ні відновлення-PID=так перевірок="+str(checks))
print("ФІЗИЧНИЙ-СЕАНС-МЕЖА REPL=НЕ-ГОТОВИЙ "
      "Core4=НЕ-ВИКОНУЄТЬСЯ лексичні-визначення=НЕ-ДОВЕДЕНО")
