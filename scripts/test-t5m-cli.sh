#!/usr/bin/env bash
# G1.4 physical transport CLI smoke, NOT language semantic parity.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FPC_BIN="${FPC:-fpc}"
BUILD="$ROOT/build/m0.2"
mkdir -p "$BUILD/bin" "$BUILD/t5mcli-units"
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" \
  -FU"$BUILD/t5mcli-units" -FE"$BUILD/bin" -osenst5m "$ROOT/src/senst5m.lpr"
CLI="$BUILD/bin/senst5m"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

printf '10 01\n' > "$tmp/input.words"
printf '\144' > "$tmp/expected.sens"
"$CLI" --pack-words "$tmp/input.words" > "$tmp/actual.sens"
cmp "$tmp/expected.sens" "$tmp/actual.sens"
"$CLI" --view "$tmp/expected.sens" > "$tmp/view.words"
cmp "$tmp/input.words" "$tmp/view.words"

printf '10 00 01\n' > "$tmp/multi.words"
printf '\143\263' > "$tmp/multi.sens"
"$CLI" --pack-words "$tmp/multi.words" > "$tmp/packed.sens"
cmp "$tmp/multi.sens" "$tmp/packed.sens"
"$CLI" --view "$tmp/packed.sens" > "$tmp/actual.words"
cmp "$tmp/multi.words" "$tmp/actual.words"

printf '000000000\n' > "$tmp/zeros.words"
"$CLI" --pack-words "$tmp/zeros.words" > "$tmp/zeros.sens"
"$CLI" --view "$tmp/zeros.sens" > "$tmp/zeros-recovered.words"
cmp "$tmp/zeros.words" "$tmp/zeros-recovered.words"

bad_case() {
  local title=$1 option=$2 input=$3
  if "$CLI" "$option" "$input" >"$tmp/fail.stdout" 2>"$tmp/fail.stderr"; then
    echo "T5M-CLI-FAIL accepted $title" >&2
    exit 1
  fi
  test ! -s "$tmp/fail.stdout" || { echo "T5M-CLI-FAIL partial stdout $title" >&2; exit 1; }
  grep -q 'SENST5M-FAIL' "$tmp/fail.stderr" || { echo "T5M-CLI-FAIL missing error $title" >&2; exit 1; }
}
printf '10  01\n' > "$tmp/double-space.words"
printf ' 10\n' > "$tmp/leading-space.words"
printf '10 \n' > "$tmp/trailing-space.words"
printf '10 01' > "$tmp/missing-lf.words"
printf '10 2\n' > "$tmp/trit.words"
printf '10\t01\n' > "$tmp/tab.words"
printf '10\r\n' > "$tmp/crlf.words"
printf '' > "$tmp/empty.words"
printf '\363' > "$tmp/bad-byte.sens"
printf '\242' > "$tmp/leading-separator.sens"
printf '\362' > "$tmp/only-padding.sens"

bad_case 'double space' --pack-words "$tmp/double-space.words"
bad_case 'leading space' --pack-words "$tmp/leading-space.words"
bad_case 'trailing space' --pack-words "$tmp/trailing-space.words"
bad_case 'missing LF' --pack-words "$tmp/missing-lf.words"
bad_case 'separator in bit word' --pack-words "$tmp/trit.words"
bad_case 'tab' --pack-words "$tmp/tab.words"
bad_case 'CRLF' --pack-words "$tmp/crlf.words"
bad_case 'empty input' --pack-words "$tmp/empty.words"
bad_case 'missing input' --pack-words "$tmp/does-not-exist.words"
bad_case 'forbidden byte 243' --view "$tmp/bad-byte.sens"
bad_case 'leading separator' --view "$tmp/leading-separator.sens"
bad_case 'only padding' --view "$tmp/only-padding.sens"
# G1.6: український інтерфейс, бінарний формат лишається першоджерелом.
"$CLI" --перегляд "$tmp/expected.sens" > "$tmp/ук-перегляд.words"
cmp "$tmp/input.words" "$tmp/ук-перегляд.words"
"$CLI" --пакувати-слова "$tmp/input.words" > "$tmp/ук-фізичний.sens"
cmp "$tmp/expected.sens" "$tmp/ук-фізичний.sens"

# Фізично перевірена D2: 10 OPEN, D1:1, 01 CLOSE.
printf '10 1 01\n' > "$tmp/список.words"
printf '\150\065' > "$tmp/список.sens"
"$CLI" --пакувати-слова "$tmp/список.words" > "$tmp/список-код.sens"
cmp "$tmp/список.sens" "$tmp/список-код.sens"
"$CLI" --перевірити-структуру "$tmp/список.sens" > "$tmp/структура.txt"
printf 'СТРУКТУРА-ГАРАЗД коренів=1 фізичних-байтів=2 двійкових-слів=3\n' > "$tmp/очікувана-структура.txt"
cmp "$tmp/очікувана-структура.txt" "$tmp/структура.txt"

# Корені D1:1 та D3:000 лишаються фізично відмінними.
printf '1 000\n' > "$tmp/два-корені.words"
"$CLI" --пакувати-слова "$tmp/два-корені.words" > "$tmp/два-корені.sens"
"$CLI" --перевірити-структуру "$tmp/два-корені.sens" > "$tmp/два-корені.txt"
grep -q '^СТРУКТУРА-ГАРАЗД коренів=2 ' "$tmp/два-корені.txt"

# Помилки D2 не створюють навіть часткового stdout.
printf '\065' > "$tmp/закрити-без-відкриття.sens"
bad_case 'передчасне D2 закриття' --перевірити-структуру "$tmp/закрити-без-відкриття.sens"
grep -Fq 'слово=1 байти=[0,1)' "$tmp/fail.stderr"

printf '\150' > "$tmp/незакритий-список.sens"
bad_case 'кінець файла без D2 закриття' --перевірити-структуру "$tmp/незакритий-список.sens"
grep -Fq 'слово=3 байти=[1,1)' "$tmp/fail.stderr"

printf '\206' > "$tmp/крапка.sens"
bad_case 'крапка поза списком' --перевірити-структуру "$tmp/крапка.sens"
grep -Fq 'слово=1 байти=[0,1)' "$tmp/fail.stderr"

printf '10 1 11 01\n' > "$tmp/без-хвоста.words"
"$CLI" --пакувати-слова "$tmp/без-хвоста.words" > "$tmp/без-хвоста.sens"
bad_case 'крапка без хвоста' --перевірити-структуру "$tmp/без-хвоста.sens"
grep -Fq 'слово=4 ' "$tmp/fail.stderr"

printf '0000000000\n' > "$tmp/непідтримана-ширина.words"
"$CLI" --пакувати-слова "$tmp/непідтримана-ширина.words" > "$tmp/непідтримана-ширина.sens"
bad_case 'непідтримана ширина структури' --перевірити-структуру "$tmp/непідтримана-ширина.sens"
grep -Fq 'слово=1 ' "$tmp/fail.stderr"

bad_case 'неправильний фізичний байт' --перевірити-структуру "$tmp/bad-byte.sens"

echo 'SENST5M-CLI-OK фізичні-вектори=2 обернені-перевірки=3 негативні=18 українські-команди=3 D2=структура-гаразд семантика=НЕ-ДОВЕДЕНА'

