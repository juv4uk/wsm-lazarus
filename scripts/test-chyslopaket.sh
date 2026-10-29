#!/usr/bin/env bash
# Пакетний D12+ перегляд реальних фізичних .sens, не арифметика SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
# Попередній числовий gate залишається обов'язковим.
bash ./scripts/test-numericplane.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'Немає Free Pascal' >&2; exit 127; }
mkdir -p build/m0.2/chyslopaket-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/chyslopaket-units" \
  -FE"$ROOT/build/m0.2/bin" -osenschyslopaket "$ROOT/src/senschyslopaket.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/chyslopaket-units" \
  -FE"$ROOT/build/m0.2/bin" -osenst5m "$ROOT/src/senst5m.lpr"
BIN="$ROOT/build/m0.2/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
reject() {
  if "$BIN/senschyslopaket" "$@" >"$TMP/відмова.out" 2>"$TMP/відмова.err"; then
    echo 'ПОМИЛКА: прийнято недопустимий числовий пакет' >&2; exit 1
  fi
  test ! -s "$TMP/відмова.out"
  test -s "$TMP/відмова.err"
}
printf '100000000000 011111111111 000000000000\n' > "$TMP/три.txt"
"$BIN/senst5m" --пакувати-слова "$TMP/три.txt" > "$TMP/три.sens"
"$BIN/senschyslopaket" --перегляд-пакета D12 "$TMP/три.sens" > "$TMP/фактичний.tsv"
{
  printf 'слово\tдомен\tукр\tточні-біти\tтрити\tбайти\n'
  printf '1\tD12\t-2048\t100000000000\t[0,12)\t[0,3)\n'
  printf '2\tD12\t2047\t011111111111\t[13,25)\t[2,5)\n'
  printf '3\tD12\t0\t000000000000\t[26,38)\t[5,8)\n'
} > "$TMP/очікуваний.tsv"
cmp "$TMP/очікуваний.tsv" "$TMP/фактичний.tsv"
for width in 24 48 96 192; do
  printf -v zeros '%*s' "$width" ''
  zeros=${zeros// /0}
  ones=${zeros//0/1}
  printf '%s %s\n' "$ones" "$zeros" > "$TMP/пара.txt"
  "$BIN/senst5m" --пакувати-слова "$TMP/пара.txt" > "$TMP/пара.sens"
  "$BIN/senschyslopaket" --перегляд-пакета "D$width" "$TMP/пара.sens" > "$TMP/широкий.tsv"
  grep -Fq "$(printf '1\tD%s\t-1\t%s\t[0,%s)' "$width" "$ones" "$width")" "$TMP/широкий.tsv"
  grep -Fq "$(printf '2\tD%s\t0\t%s\t[%s,%s)' "$width" "$zeros" "$((width+1))" "$((2*width+1))")" "$TMP/широкий.tsv"
done
printf '100000000000 0\n' > "$TMP/змішані.txt"
"$BIN/senst5m" --пакувати-слова "$TMP/змішані.txt" > "$TMP/змішані.sens"
reject --перегляд-пакета D12 "$TMP/змішані.sens"
reject --перегляд-пакета D24 "$TMP/три.sens"
reject --перегляд-пакета D10 "$TMP/три.sens"
reject --перегляд-пакета D12 "$TMP/відсутній.sens"
printf 'число\n' > "$TMP/текст.lisp"
reject --перегляд-пакета D12 "$TMP/текст.lisp"
cp "$TMP/три.sens" "$TMP/пізня.sens"
printf '\363' >> "$TMP/пізня.sens"
reject --перегляд-пакета D12 "$TMP/пізня.sens"
head -c 65537 /dev/zero > "$TMP/завеликий.sens"
reject --перегляд-пакета D12 "$TMP/завеликий.sens"
for ((i=0;i<1025;i++)); do
  if ((i>0)); then printf ' '; fi
  printf '000000000000'
done > "$TMP/багато.txt"
printf '\n' >> "$TMP/багато.txt"
"$BIN/senst5m" --пакувати-слова "$TMP/багато.txt" > "$TMP/багато.sens"
reject --перегляд-пакета D12 "$TMP/багато.sens"
"$BIN/senschyslopaket" --перегляд-пакета D12 "$TMP/три.sens" > "$TMP/відновлення.tsv"
cmp "$TMP/очікуваний.tsv" "$TMP/відновлення.tsv"
echo 'ЧИСЛОВИЙ-ПАКЕТ-ГАРАЗД D12-D192=явний T5M=канонічний трити-байти=точні відмови=атомарні'
