#!/usr/bin/env bash
# G2.49 — реальні FPC, фізичні T5M та pinned census голів D2/D10.
# Тільки структура, не доказ мовної викличності.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
: "${FPC:=fpc}"
./scripts/check-pin.sh
mkdir -p build/m0.2/bin build/m0.2/heads-units
"$FPC" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/heads-units" -FE"$ROOT/build/m0.2/bin" \
  -osensbinary "$ROOT/src/sensbinary.lpr"
"$FPC" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/heads-units" -FE"$ROOT/build/m0.2/bin" \
  -osenst5m "$ROOT/src/senst5m.lpr"
BIN="$ROOT/build/m0.2/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pack() {
  printf '%s\n' "$2" > "$TMP/$1.words"
  "$BIN/senst5m" --пакувати-слова "$TMP/$1.words" > "$TMP/$1.sens"
}
reject() {
  local mode=$1 file=$2 why=$3
  if "$BIN/sensbinary" "$mode" "$file" > "$TMP/відмова.out" 2> "$TMP/відмова.err"; then
    echo "ГОЛОВИ-Д10-ПОМИЛКА: прийнято $why" >&2
    exit 1
  fi
  if test -s "$TMP/відмова.out"; then
    echo "ГОЛОВИ-Д10-ПОМИЛКА: частковий stdout $why" >&2
    exit 1
  fi
  grep -Fq 'ДВІЙКОВЕ-ПОМИЛКА' "$TMP/відмова.err" || {
    cat "$TMP/відмова.err" >&2
    echo "ГОЛОВИ-Д10-ПОМИЛКА: немає української діагностики $why" >&2
    exit 1
  }
}

# Один зовнішній D2-список; D10 W10 з нулями, вкладена
# структура, D3:000 як структура, справді порожня голова,
# D7 SYN як НЕдруковані дані та окрема D1:0.
pack 'вісім' '10 10 0000000000 0 01 10 10 1 01 01 10 000 01 10 01 10 0010110 01 10 0 01 01'
"$BIN/sensbinary" --голови-д10 "$TMP/вісім.sens" > "$TMP/голови.txt"
grep -Fq 'номер=0 форма=0 стан=структурна вузол=1 домен=немає' "$TMP/голови.txt"
grep -Fq 'стан=точна вузол=2 слово=3 трити=[' "$TMP/голови.txt"
grep -Fq 'домен=D10 біти=0000000000' "$TMP/голови.txt"
grep -Fq 'домен=D1 біти=1 ук=так укр=так' "$TMP/голови.txt"
grep -Fq 'стан=структурна вузол=' "$TMP/голови.txt"
grep -Fq 'стан=немає вузол=-1 домен=немає проєкції=немає' "$TMP/голови.txt"
grep -Fq 'домен=D7 біти=0010110 ук=() укр=()' "$TMP/голови.txt"
grep -Fq 'домен=D1 біти=0 ук=ні укр=ні' "$TMP/голови.txt"
grep -Fq ' san=' "$TMP/голови.txt"
grep -Fq ' en=' "$TMP/голови.txt"
grep -Fq ' LISP=' "$TMP/голови.txt"
grep -Fq ' sym=' "$TMP/голови.txt"
grep -Fxq 'ГОЛОВИ-ПІДСУМОК списків=8 викличність=не-перевірено виконання=не-перевірено' "$TMP/голови.txt"
test "$(wc -l < "$TMP/голови.txt")" -eq 9
"$BIN/sensbinary" --голови-д10 "$TMP/вісім.sens" > "$TMP/повтор.txt"
cmp "$TMP/голови.txt" "$TMP/повтор.txt"

# Історичний вузький режим ніколи не розширюється до D10 мовчки.
reject --голови "$TMP/вісім.sens" 'D10 без явного перемикача'
pack 'малий' '10 10 1 01 10 01 01'
"$BIN/sensbinary" --голови "$TMP/малий.sens" > "$TMP/старий.txt"
"$BIN/sensbinary" --голови-д10 "$TMP/малий.sens" > "$TMP/широкий.txt"
cmp "$TMP/старий.txt" "$TMP/широкий.txt"
grep -Fxq 'ГОЛОВИ-ПІДСУМОК списків=3 викличність=не-перевірено виконання=не-перевірено' "$TMP/широкий.txt"

# D2 dotted pair — НЕ D2-список і НЕ автоматичний callable.
pack 'пара' '10 1 11 0 01'
"$BIN/sensbinary" --голови-д10 "$TMP/пара.sens" > "$TMP/пара.txt"
grep -Fxq 'ГОЛОВИ-ПІДСУМОК списків=0 викличність=не-перевірено виконання=не-перевірено' "$TMP/пара.txt"
pack 'пара-в-голові' '10 10 1 11 0 01 01'
"$BIN/sensbinary" --голови-д10 "$TMP/пара-в-голові.sens" > "$TMP/пара-в-голові.txt"
grep -Fq 'стан=структурна вузол=' "$TMP/пара-в-голові.txt"

pack 'w11' '00000000000'
pack 'w12' '000000000000'
pack 'пізня-w12' '10 1 00 000000000000 01'
pack 'незакритий' '10 1'
reject --голови-д10 "$TMP/w11.sens" 'W11'
reject --голови-д10 "$TMP/w12.sens" 'W12 не є автоматичним числом D12+'
reject --голови-д10 "$TMP/пізня-w12.sens" 'пізня W12 після валідного префікса'
reject --голови-д10 "$TMP/незакритий.sens" 'незакритий D2'
cp "$TMP/малий.sens" "$TMP/пізній-байт.sens"
printf '\363' >> "$TMP/пізній-байт.sens"
reject --голови-д10 "$TMP/пізній-байт.sens" 'пізній заборонений T5M'
: > "$TMP/порожній.sens"
reject --голови-д10 "$TMP/порожній.sens" 'порожній файл'
printf '(укр звичайна проєкція)\n' > "$TMP/проєкція.lisp"
reject --голови-д10 "$TMP/проєкція.lisp" '.lisp замість фізичного .sens'
reject --голови-д10 "$TMP/відсутній.sens" 'файл відсутній'
if (cd "$TMP" && "$BIN/sensbinary" --голови-д10 "$TMP/малий.sens" \
    > "$TMP/відмова.out" 2> "$TMP/відмова.err"); then
  echo 'ГОЛОВИ-Д10-ПОМИЛКА: прийнято відсутні pinned таблиці' >&2
  exit 1
fi
test ! -s "$TMP/відмова.out"
grep -Fq 'ДВІЙКОВЕ-ПОМИЛКА' "$TMP/відмова.err"

# Після відмови справжній reader/binder/голови знову працюють.
"$BIN/sensbinary" --голови-д10 "$TMP/малий.sens" > "$TMP/відновлений.txt"
cmp "$TMP/широкий.txt" "$TMP/відновлений.txt"
echo 'ГОЛОВИ-Д10-ГАРАЗД FPC=справжній T5M=канонічний preorder=перевірено W10=явний D7=SYN проєкцій=6 D12+=відхилено stdout=атомарний'
