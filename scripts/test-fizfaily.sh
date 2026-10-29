#!/usr/bin/env bash
# G5.63. Реальні FPC 3.2.x процеси; жодного підставного evaluator.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'ФІЗИЧНІ-ФАЙЛИ-БЛОК: немає FPC' >&2; exit 127; }
command -v python3 >/dev/null
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
for entry in senst5m sensfizseans sensfizfaily; do
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
    -o"$entry" "$ROOT/src/$entry.lpr"
done
python3 - "$TMP" <<'PY'
import pathlib
import struct
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
cli = root / "bin/sensfizfaily"
server = root / "bin/sensfizseans"
packer = root / "bin/senst5m"
checks = 0

def demand(condition, message):
    global checks
    checks += 1
    if not condition:
        raise AssertionError(message)

def words(name, source):
    path = root / (name + ".words")
    path.write_text(source + "\n", encoding="ascii")
    packed = subprocess.run(
        [str(packer), "--пакувати-слова", str(path)],
        capture_output=True, timeout=30, check=True
    ).stdout
    demand(bool(packed), "пакувальник порожній")
    result = root / (name + ".sens")
    result.write_bytes(packed)
    return result, packed

def launch(paths, executable=server, option="--файли"):
    return subprocess.run(
        [str(cli), option, str(executable), *(str(p) for p in paths)],
        capture_output=True, timeout=60
    )

def frames(out, expected):
    pos, found = 0, []
    for _ in range(expected):
        demand(pos + 9 <= len(out), "обірваний host заголовок")
        status, index, length = struct.unpack_from("<BII", out, pos)
        pos += 9
        demand(status in (0, 1) and 1 <= length <= 65536,
               "невірна host геометрія")
        demand(pos + length <= len(out), "обірване фізичне тіло")
        found.append((status, index, out[pos:pos + length]))
        pos += length
    demand(pos == len(out), "зайві байти/текст на фізичному stdout")
    return found

yes, yes_bytes = words("так", "1")
no, no_bytes = words("ні", "0")
quote, _ = words("цитата", "10 001 1 01")
bad, _ = words("невиклична-голова", "10 000 000 01")
invalid = root / "пошкоджений.sens"
invalid.write_bytes(bytes([243]))
missing = root / "відсутній.sens"
empty = root / "порожній.sens"
empty.write_bytes(b"")
oversize = root / "завеликий.sens"
oversize.write_bytes(bytes(65537))
human = root / "людський.lisp"
human.write_text("(як-є 1)\n", encoding="utf-8")

p = launch([yes, quote, no, yes])
demand(p.returncode == 0 and not p.stderr, "4 реальні фізичні форми")
demand(frames(p.stdout, 4) ==
       [(0, 0, yes_bytes), (0, 0, yes_bytes),
        (0, 0, no_bytes), (0, 0, yes_bytes)],
       "вихід не тотожний FPC senst5m")

p = launch([yes, bad, invalid, quote, no])
demand(p.returncode == 2 and not p.stderr, "відмови й продовження PID")
r = frames(p.stdout, 5)
demand(r[0] == (0, 0, yes_bytes) and r[3] == (0, 0, yes_bytes)
       and r[4] == (0, 0, no_bytes), "втрата правильних байтів після відмови")
demand(r[1][0] == 1 and bool(r[1][2]), "невикличну голову прийнято")
demand(r[2][0] == 1 and r[2][1] == 0 and bool(r[2][2]),
       "неканонічний T5M прийнято/втрата WordIndex")

p = launch([yes] * 16)
demand(p.returncode == 0 and not p.stderr, "16 фізичних файлів")
demand(frames(p.stdout, 16) == [(0, 0, yes_bytes)] * 16,
       "змінено фізичний результат 16 кадрів")

for paths, description in (
    ([yes, missing], "відсутній пізній файл"),
    ([yes, human], "людська проєкція .lisp"),
    ([yes, empty], "порожній .sens"),
    ([yes, oversize], "надмірний .sens"),
):
    p = launch(paths)
    demand(p.returncode == 2 and not p.stdout and
           b"ПОМИЛКА-ФІЗИЧНІ-ФАЙЛИ" in p.stderr,
           "попередній fail-closed допуск: " + description)

p = launch([yes], executable=root / "немає-виконавця")
demand(p.returncode == 2 and not p.stdout and p.stderr,
       "недоступний дочірній FPC виконавець")
p = launch([yes] * 17)
demand(p.returncode == 64 and not p.stdout, "межа 16 файлів")
p = launch([yes], option="--невідомо")
demand(p.returncode == 64 and not p.stdout, "невідомий host режим")
p = subprocess.run([str(cli)], capture_output=True, timeout=30)
demand(p.returncode == 64 and not p.stdout, "неявний host режим")
print(f"ФІЗИЧНІ-ФАЙЛИ-ГАРАЗД перевірок={checks} FPC=справжній "
      "T5M=байт-в-байт D1/D3=виконано відмови=відновлення "
      "пізній-файл=атомарно-ніщо межа=16")
print("ФІЗИЧНІ-ФАЙЛИ-МЕЖА REPL=НЕ-ГОТОВИЙ "
      "лексичне-середовище=НЕ-ДОВЕДЕНО Core4=НЕ-ДОВЕДЕНО "
      "вихід=host-кадри-НЕ-.sens")
PY
