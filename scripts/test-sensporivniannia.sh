#!/usr/bin/env bash
# G1.37: фізична рівність/відмінність двох T5M, НЕ мовний oracle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FPC_BIN="${FPC:-fpc}"
command -v "$FPC_BIN" >/dev/null || {
  echo 'ПОРІВНЯННЯ-ТЕСТ-ПОМИЛКА: відсутній Free Pascal' >&2
  exit 127
}
mkdir -p build/m0.2/porivniannia-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/porivniannia-units" -FE"$ROOT/build/m0.2/bin" \
  -osensporivniannia "$ROOT/src/sensporivniannia.lpr"
CLI="$ROOT/build/m0.2/bin/sensporivniannia"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Канонічні T5M-вектори: 10 01 => 10201_3 = 100_10.
printf '\144' > "$tmp/однаковий.sens"
cp "$tmp/однаковий.sens" "$tmp/копія.sens"
printf '\143' > "$tmp/інший-біт.sens"    # 10 00 => 10200_3
printf '\143\241' > "$tmp/інша-ширина.sens" # 10 001
printf '\143\263' > "$tmp/більше-слів.sens" # 10 00 01
printf '\363' > "$tmp/заборонений-байт.sens"   # byte 243
printf '\242' > "$tmp/початковий-роздільник.sens"
: > "$tmp/порожній.sens"

"$CLI" "$tmp/однаковий.sens" "$tmp/копія.sens" > "$tmp/добре.txt"
grep -Fq 'ТОТОЖНІ фізичні-файли; слів=2; байтів=1' "$tmp/добре.txt"

different() {
  local description="$1" other="$2" expected="$3" rc=0
  if "$CLI" "$tmp/однаковий.sens" "$other" > "$tmp/відмінність.txt" 2> "$tmp/помилка.txt"; then
    echo "ПОРІВНЯННЯ-ТЕСТ-ПОМИЛКА: прийнято як рівні: $description" >&2
    exit 1
  else
    rc=$?
  fi
  test "$rc" -eq 1 || { echo "Помилковий код відмінності $rc: $description" >&2; exit 1; }
  test ! -s "$tmp/помилка.txt"
  grep -Fq 'ВІДМІННІ фізичні-файли; перший-байт=0' "$tmp/відмінність.txt"
  grep -Fq "$expected" "$tmp/відмінність.txt"
}
different 'той самий W2, інший біт' "$tmp/інший-біт.sens" 'праворуч=W2: 00'
different 'інша ширина W3' "$tmp/інша-ширина.sens" 'праворуч=W3: 001'
different 'інша кількість слів' "$tmp/більше-слів.sens" 'слів-праворуч=3'

invalid() {
  local description="$1" other="$2" rc=0
  if "$CLI" "$tmp/однаковий.sens" "$other" > "$tmp/частковий.stdout" 2> "$tmp/відмова.stderr"; then
    echo "ПОРІВНЯННЯ-ТЕСТ-ПОМИЛКА: прийнято недопустиме: $description" >&2
    exit 1
  else
    rc=$?
  fi
  test "$rc" -eq 2 || { echo "Помилковий код відмови $rc: $description" >&2; exit 1; }
  test ! -s "$tmp/частковий.stdout" || {
    echo "ПОРІВНЯННЯ-ТЕСТ-ПОМИЛКА: частковий stdout: $description" >&2
    exit 1
  }
  grep -Fq 'ФІЗИЧНЕ-ПОРІВНЯННЯ-ПОМИЛКА:' "$tmp/відмова.stderr"
}
invalid 'неприпустимий байт 243' "$tmp/заборонений-байт.sens"
invalid 'роздільник на початку' "$tmp/початковий-роздільник.sens"
invalid 'порожній файл' "$tmp/порожній.sens"
invalid 'відсутній файл' "$tmp/немає.sens"
# Застосовується preflight до першого виділення вмісту >4 МіБ.
head -c $((4 * 1024 * 1024 + 1)) /dev/zero > "$tmp/завеликий.sens"
invalid 'понад 4 МіБ' "$tmp/завеликий.sens"
# Транзакційність також при пошкодженні ПЕРШОГО файлу.
if "$CLI" "$tmp/заборонений-байт.sens" "$tmp/однаковий.sens" \
    > "$tmp/частковий.stdout" 2> "$tmp/відмова.stderr"; then
  echo 'ПОРІВНЯННЯ-ТЕСТ-ПОМИЛКА: хибний лівий вхід прийнято' >&2
  exit 1
else
  rc=$?
fi
test "$rc" -eq 2
test ! -s "$tmp/частковий.stdout"

echo 'ФІЗИЧНЕ-ПОРІВНЯННЯ-ТЕСТ-ГАРАЗД тотожні=1 різні=3 відмови=6 семантика=НЕ-ДОВЕДЕНА'
