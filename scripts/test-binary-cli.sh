#!/usr/bin/env bash
# G2.8: реальний FPC build та фізичні позитивні/негативні .sens.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null || { echo 'ПОМИЛКА: немає Free Pascal' >&2; exit 127; }
mkdir -p build/m0.2/bin build/m0.2/test-units
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/test-units" \
  -FE"$ROOT/build/m0.2/bin" -osensbinary "$ROOT/src/sensbinary.lpr"
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/test-units" \
  -FE"$ROOT/build/m0.2/bin" -osenst5m "$ROOT/src/senst5m.lpr"
BIN="$ROOT/build/m0.2/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf '10 111 00 1 000 01\n' > "$TMP/форма.words"
"$BIN/senst5m" --pack-words "$TMP/форма.words" > "$TMP/форма.sens"
"$BIN/sensbinary" --аналіз "$TMP/форма.sens" > "$TMP/вихід.txt"
grep -Fx 'ДВІЙКОВЕ-СЛОВО індекс=2 форма=0 домен=3 біти=111 порожнє=ні ук=сполучити' "$TMP/вихід.txt"
grep -Fx 'ДВІЙКОВЕ-СЛОВО індекс=4 форма=0 домен=1 біти=1 порожнє=ні ук=так' "$TMP/вихід.txt"
grep -Fx 'ДВІЙКОВЕ-СЛОВО індекс=5 форма=0 домен=3 біти=000 порожнє=так ук=немає' "$TMP/вихід.txt"
grep -Fx 'ДВІЙКОВЕ-ПІДСУМОК слів=3 викличність=не-перевірено виконання=не-перевірено' "$TMP/вихід.txt"
"$BIN/sensbinary" --аналіз "$TMP/форма.sens" > "$TMP/повтор.txt"
cmp "$TMP/вихід.txt" "$TMP/повтор.txt"

printf '0 00 000\n' > "$TMP/корені.words"
"$BIN/senst5m" --pack-words "$TMP/корені.words" > "$TMP/корені.sens"
"$BIN/sensbinary" --аналіз "$TMP/корені.sens" > "$TMP/корені.txt"
grep -F 'індекс=1 форма=0 домен=1 біти=0 порожнє=ні' "$TMP/корені.txt"
grep -F 'індекс=3 форма=1 домен=3 біти=000 порожнє=так' "$TMP/корені.txt"

# Відмова не повинна вивести жодного часткового результату у stdout.
must_reject() {
  local label=$1 path=$2
  if "$BIN/sensbinary" --аналіз "$path" > "$TMP/негатив.out" 2> "$TMP/негатив.err"; then
    echo "ДВІЙКОВЕ-ТЕСТ-ПОМИЛКА прийнято: $label" >&2; exit 1
  fi
  test ! -s "$TMP/негатив.out" || { echo "ДВІЙКОВЕ-ТЕСТ-ПОМИЛКА частковий stdout: $label" >&2; exit 1; }
  grep -F 'ДВІЙКОВЕ-ПОМИЛКА' "$TMP/негатив.err"
}
printf '\363' > "$TMP/байт.sens"
must_reject 'поганий байт T5M' "$TMP/байт.sens"
printf '10 111\n' > "$TMP/незакрито.words"
"$BIN/senst5m" --pack-words "$TMP/незакрито.words" > "$TMP/незакрито.sens"
must_reject 'незакритий D2' "$TMP/незакрито.sens"
grep -F 'слово=3:' "$TMP/негатив.err"
printf '1111111111\n' > "$TMP/ширина.words"
"$BIN/senst5m" --pack-words "$TMP/ширина.words" > "$TMP/ширина.sens"
must_reject 'непідтриманий D10' "$TMP/ширина.sens"
: > "$TMP/порожній.sens"
must_reject 'порожній файл' "$TMP/порожній.sens"
must_reject 'відсутній файл' "$TMP/немає.sens"
must_reject 'не двійковий вхід' "$TMP/форма.words"
truncate -s $((4*1024*1024+1)) "$TMP/завеликий.sens"
must_reject 'фізичний ліміт' "$TMP/завеликий.sens"
if (cd "$TMP" && "$BIN/sensbinary" --аналіз "$TMP/форма.sens" > "$TMP/негатив.out" 2> "$TMP/негатив.err"); then
  echo 'ДВІЙКОВЕ-ТЕСТ-ПОМИЛКА прийнято неприкріплені таблиці' >&2; exit 1
fi
test ! -s "$TMP/негатив.out"
grep -F 'ДВІЙКОВЕ-ПОМИЛКА' "$TMP/негатив.err"
echo 'ДВІЙКОВЕ-CLI-ГАРАЗД FPC=фізичний T5M=так D2=так координати=точні негативні=відхилено викличність=не-доведено'
