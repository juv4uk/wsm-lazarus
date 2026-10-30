#!/usr/bin/env bash
# G6.63 — фактичні ELF64 і фізичні T5M відповіді, без вигаданих джоулів.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo 'ЕЛЬФ-ПАСПОРТ-БЛОК: Linux x86-64' >&2; exit 127
fi
FPC_BIN=$(printenv FPC || echo fpc)
for command_name in "$FPC_BIN" python3 stat readelf cmp dd truncate timeout; do
  command -v "$command_name" >/dev/null || {
    echo "ЕЛЬФ-ПАСПОРТ-БЛОК: відсутній $command_name" >&2; exit 127;
  }
done

# Зберігаємо чинні emitter-регресії: 8 позитивних та 11 негативних.
timeout 240s bash ./scripts/test-sensmashyna.sh
DIR="$ROOT/build/m0.2/elfpasport"
mkdir -p "$DIR/bin" "$DIR/units"
timeout 120s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$DIR/units" -FE"$DIR/bin" \
  -osenselfpasport "$ROOT/src/senselfpasport.lpr"
PASSPORT="$DIR/bin/senselfpasport"
COMPILER="$ROOT/build/m0.2/mashyna/bin/sensmashyna"
TEST="$ROOT/build/m0.2/mashyna/bin/test-sensmashyna"
test -x "$PASSPORT" && test -x "$COMPILER" && test -x "$TEST"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/свідки" "$TMP/ельф"
timeout 30s "$TEST" "$ROOT/external/sens" "$TMP/свідки"
TABLE="$TMP/метрики.tsv"
: > "$TABLE"
count=0
for pair in \
  'цитата:цитата-д7' 'цитата:цитата-список' \
  'атом:атом-один' 'атом:атом-пара' \
  'тотожність:тотожні-00' 'тотожність:тотожні-01' \
  'тотожність:тотожні-10' 'тотожність:тотожні-11'; do
  mode=$(printf '%s' "$pair" | cut -d: -f1)
  label=$(printf '%s' "$pair" | cut -d: -f2)
  source_file="$TMP/свідки/$label.sens"
  expected_file="$TMP/свідки/$label.expected.sens"
  image="$TMP/ельф/$label.elf"
  timeout 15s "$COMPILER" "--$mode" "$ROOT/external/sens" \
    "$source_file" "$image" > "$TMP/компілятор.out"
  test -x "$image" && test -s "$image"
  timeout 10s "$image" > "$TMP/виконане.sens"
  cmp "$TMP/виконане.sens" "$expected_file"
  timeout 10s "$PASSPORT" --геометрія "$image" > "$TMP/$label.паспорт"
  grep -Fq 'ЕЛЬФ-ПАСПОРТ-ГАРАЗД' "$TMP/$label.паспорт"
  readelf -h "$image" > "$TMP/$label.elf-заголовок"
  grep -Fq 'ELF64' "$TMP/$label.elf-заголовок"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$label" "$mode" "$source_file" "$expected_file" "$image" >> "$TABLE"
  count=$((count+1))
done
test "$count" -eq 8

negatives=0
reject() {
  local path=$1
  if timeout 10s "$PASSPORT" --геометрія "$path" \
    > "$TMP/помилка.out" 2> "$TMP/помилка.err"; then
    echo "ЕЛЬФ-ПАСПОРТ-ПОМИЛКА: недійсний ELF прийнято: $path" >&2
    exit 1
  fi
  test ! -s "$TMP/помилка.out"
  grep -Fq 'ЕЛЬФ-ПАСПОРТ-ПОМИЛКА:' "$TMP/помилка.err"
  negatives=$((negatives+1))
}
BASE="$TMP/ельф/тотожні-00.elf"
: > "$TMP/порожній.elf"
reject "$TMP/порожній.elf"
head -c 119 "$BASE" > "$TMP/обрізаний.elf"
reject "$TMP/обрізаний.elf"
printf 'це не ELF' > "$TMP/не-ельф.elf"
reject "$TMP/не-ельф.elf"
cp "$BASE" "$TMP/підроблений.lisp"
reject "$TMP/підроблений.lisp"
cp "$BASE" "$TMP/хибна-магія.elf"
printf '\000' | dd of="$TMP/хибна-магія.elf" bs=1 seek=1 \
  conv=notrunc status=none
reject "$TMP/хибна-магія.elf"
cp "$BASE" "$TMP/хибний-розмір.elf"
printf '\000' | dd of="$TMP/хибний-розмір.elf" bs=1 seek=96 \
  conv=notrunc status=none
reject "$TMP/хибний-розмір.elf"
cp "$BASE" "$TMP/хибний-вхід.elf"
printf '\000' | dd of="$TMP/хибний-вхід.elf" bs=1 seek=24 \
  conv=notrunc status=none
reject "$TMP/хибний-вхід.elf"
cp "$BASE" "$TMP/хибний-abi.elf"
printf '\004' | dd of="$TMP/хибний-abi.elf" bs=1 seek=16 \
  conv=notrunc status=none
reject "$TMP/хибний-abi.elf"
cp "$BASE" "$TMP/надмірний.elf"
truncate -s 1048577 "$TMP/надмірний.elf"
reject "$TMP/надмірний.elf"
test "$negatives" -eq 9

# Звіт записується лише ПІСЛЯ 8 справжніх виконань і 9 відмов.
python3 - "$ROOT" "$TMP" "$TABLE" "$DIR/паспорт.json" <<'PY'
import hashlib
import json
import os
import platform
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

root, tmp, table, dest = map(Path, sys.argv[1:])
pin = "2c498b35af53c085450eac6f51b87facf7f9aa47"
current_pin = subprocess.check_output(
    ["git", "-C", str(root / "external/sens"), "rev-parse", "HEAD"],
    text=True, timeout=10
).strip()
assert current_pin == pin, "помилковий закріплений контракт"
rows = []
pattern = re.compile(
    r"ЕЛЬФ-ПАСПОРТ-ГАРАЗД тип=(2|3) байтів=(\d+) "
    r"код-байтів=(\d+) точка-входу=(\d+)\n"
)
for line in table.read_text(encoding="utf-8").splitlines():
    label, mode, source, expected, image = line.split("\t")
    source, expected, image = map(Path, (source, expected, image))
    matched = pattern.fullmatch(
        (tmp / (label + ".паспорт")).read_text(encoding="utf-8")
    )
    assert matched, "неповна точна геометрія для " + label
    kind, size, code, entry = map(int, matched.groups())
    assert kind in (2, 3) and size == image.stat().st_size
    assert code == size - 120 and 0 < code < size
    assert entry == (0x400000 + 120 if kind == 2 else 120)
    proc = subprocess.run([str(image)], capture_output=True,
                          timeout=10, check=False)
    assert proc.returncode == 0 and proc.stderr == b""
    assert proc.stdout == expected.read_bytes()
    assert image.is_file() and os.access(image, os.X_OK)
    def sha256(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()
    rows.append({
        "свідок": label, "явний_host_профіль": mode,
        "джерело_SHA256": sha256(source),
        "результат_SHA256": sha256(expected),
        "ELF_SHA256": sha256(image),
        "ELF_host_тип": kind,
        "ELF_байтів": size, "машинний_RX_код_байтів": code,
        "entry_адреса": entry,
        "запуск_ELF_і_T5M_cmp": "пройдено",
    })
assert len(rows) == 8 and len({v["свідок"] for v in rows}) == 8
report = {
    "схема": "паспорт-компілятора-sens/1",
    "дата_utc": datetime.now(timezone.utc).isoformat(),
    "машина": platform.platform(),
    "процесор": platform.processor() or "невідомий",
    "SENS_pin": pin,
    "джерело_main_або_PR_SHA": subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        text=True, timeout=10
    ).strip(),
    "межа": "статична геометрія ELF та точне виконання; "
             "без RAPL, без енергії процесу, без нормалізованих джоулів; "
             "цей host паспорт не є доказом незалежного REPL parity",
    "фізичних_виконаних_форм": len(rows),
    "негативних_тестів": 9,
    "форми": rows,
}
dest.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8")
print("ЕЛЬФ-ПАСПОРТ-ЗВІТ-ГАРАЗД фізичних=8 негативних=9 "
      "виконання=справжнє геометрія=перевірена енергія=НЕ-ВИМІРЯНО")
PY
test -s "$DIR/паспорт.json"
echo 'ЕЛЬФ-ПАСПОРТ-FPC-ГАРАЗД ELF=8 негативні=9 JSON=збережено'
