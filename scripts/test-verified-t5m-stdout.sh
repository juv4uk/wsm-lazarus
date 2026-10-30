#!/usr/bin/env bash
# G1.58: лише host stdout у вже наявному фізичному CLI T5M/D2.
# Семантичний SENS oracle і фізичну енергію цей тест не вимірює.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FPC_BIN="${FPC:-fpc}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/units"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$tmp/units" -FE"$tmp" -osenst5m "$ROOT/src/senst5m.lpr" >"$tmp/fpc.log" 2>&1 || {
  cat "$tmp/fpc.log" >&2
  exit 1
}
CLI="$tmp/senst5m"

fail() { echo "VERIFIED-T5M-STDOUT-FAIL $*" >&2; exit 1; }
printf '10 01\n' >"$tmp/слова.words"
printf '\144' >"$tmp/слова.sens"
printf '10 1 01\n' >"$tmp/структура.words"
printf '\150\065' >"$tmp/структура.sens"

"$CLI" --view "$tmp/слова.sens" >"$tmp/позитив.words" 2>"$tmp/stderr"
cmp "$tmp/слова.words" "$tmp/позитив.words" || fail "змінені точні біти"
"$CLI" --pack-words "$tmp/слова.words" >"$tmp/позитив.sens" 2>"$tmp/stderr"
cmp "$tmp/слова.sens" "$tmp/позитив.sens" || fail "змінений канонічний T5M"
"$CLI" --перевірити-структуру "$tmp/структура.sens" >"$tmp/структура.out" 2>"$tmp/stderr"
grep -Fq 'коренів=1 фізичних-байтів=2 двійкових-слів=3' "$tmp/структура.out" ||
  fail "невірний D2 результат"

expect_write_fail() {
  local label="$1" operation="$2" input="$3"
  if "$CLI" "$operation" "$input" > /dev/full 2>"$tmp/помилка.stderr"; then
    fail "$label: /dev/full прийнято за успіх"
  fi
  grep -Fq 'SENST5M-FAIL' "$tmp/помилка.stderr" ||
    fail "$label: немає діагностики /dev/full"
  if "$CLI" "$operation" "$input" 1>&- 2>"$tmp/помилка.stderr"; then
    fail "$label: закритий stdout прийнято за успіх"
  fi
  grep -Fq 'SENST5M-FAIL' "$tmp/помилка.stderr" ||
    fail "$label: немає діагностики закритого stdout"
}
expect_write_fail перегляд --view "$tmp/слова.sens"
expect_write_fail пакування --pack-words "$tmp/слова.words"
expect_write_fail структура --перевірити-структуру "$tmp/структура.sens"

# Пізній недопустимий фізичний байт: жодного stdout до повного допуску.
printf '\144\363' >"$tmp/пошкоджено.sens"
if "$CLI" --view "$tmp/пошкоджено.sens" >"$tmp/відмова.out" 2>"$tmp/помилка.stderr"; then
  fail "пошкоджений T5M прийнято"
fi
test ! -s "$tmp/відмова.out" || fail "частковий stdout до фізичного допуску"
grep -Fq 'SENST5M-FAIL' "$tmp/помилка.stderr" ||
  fail "немає діагностики пошкодженого T5M"

# Відновлення після host-відмови тим самим виконуваним файлом.
"$CLI" --view "$tmp/слова.sens" >"$tmp/відновлено.words" 2>"$tmp/stderr"
cmp "$tmp/слова.words" "$tmp/відновлено.words"
"$CLI" --pack-words "$tmp/слова.words" >"$tmp/відновлено.sens" 2>"$tmp/stderr"
cmp "$tmp/слова.sens" "$tmp/відновлено.sens"
"$CLI" --перевірити-структуру "$tmp/структура.sens" >"$tmp/відновлено.d2" 2>"$tmp/stderr"
cmp "$tmp/структура.out" "$tmp/відновлено.d2"

echo 'VERIFIED-T5M-STDOUT-PASS positives=3 write-failures=6 corrupt=1 recoveries=3 oracle=NOT-RUN energy=NOT-MEASURED'
