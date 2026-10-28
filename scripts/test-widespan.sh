#!/usr/bin/env bash
# G1.8: реальні FPC ворота фізичної ширини D12+; НЕ числова арифметика.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
FPC_BIN=fpc
command -v "$FPC_BIN" >/dev/null || { echo 'ШИРОКІ-СЛОВА-БЛОК: потрібен FPC' >&2; exit 127; }
mkdir -p build/m0.2/widespan-units build/m0.2/widespan-bin
for target in test-widespan sensshyryna senst5m; do
  if [[ $target == test-widespan ]]; then src="scripts/$target.pas"; else src="src/$target.lpr"; fi
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$ROOT/build/m0.2/widespan-units" \
    -FE"$ROOT/build/m0.2/widespan-bin" -o"$target" "$src"
done
BIN="$ROOT/build/m0.2/widespan-bin"
"$BIN/test-widespan"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '0 000000000001 01 0000000000000 10101010101 111111111111\n' > "$TMP/слова.txt"
"$BIN/senst5m" --пакувати-слова "$TMP/слова.txt" > "$TMP/слова.sens"
"$BIN/sensshyryna" --широкі-слова "$TMP/слова.sens" > "$TMP/звіт.tsv"
"$BIN/sensshyryna" --широкі-слова "$TMP/слова.sens" > "$TMP/звіт-повтор.tsv"
cmp "$TMP/звіт.tsv" "$TMP/звіт-повтор.tsv"
{
  printf 'слово\tширина\tточні-біти\tтрити\tбайти\n'
  printf '2\tD12\t000000000001\t[2,14)\t[0,3)\n'
  printf '4\tD13\t0000000000000\t[18,31)\t[3,7)\n'
  printf '6\tD12\t111111111111\t[44,56)\t[8,12)\n'
} > "$TMP/еталон.tsv"
cmp "$TMP/звіт.tsv" "$TMP/еталон.tsv"
printf '0 1 10 01\n' > "$TMP/короткі.txt"
"$BIN/senst5m" --пакувати-слова "$TMP/короткі.txt" > "$TMP/короткі.sens"
"$BIN/sensshyryna" --широкі-слова "$TMP/короткі.sens" > "$TMP/порожній.tsv"
printf 'слово\tширина\tточні-біти\tтрити\tбайти\n' > "$TMP/тільки-заголовок.tsv"
cmp "$TMP/порожній.tsv" "$TMP/тільки-заголовок.tsv"
printf '\363' > "$TMP/поганий.sens"
: > "$TMP/нуль.sens"
printf '(укр (число 12))\n' > "$TMP/людський.lisp"
for input in "$TMP/поганий.sens" "$TMP/нуль.sens" \
             "$TMP/відсутній.sens" "$TMP/людський.lisp"; do
  if "$BIN/sensshyryna" --широкі-слова "$input" > "$TMP/невдала-відповідь" 2> "$TMP/помилка"; then
    echo "ШИРОКІ-СЛОВА-ТЕСТ-ПОМИЛКА: прийнято $input" >&2; exit 1
  fi
  test ! -s "$TMP/невдала-відповідь"
  test -s "$TMP/помилка"
done
if "$BIN/sensshyryna" --невідома "$TMP/слова.sens" >"$TMP/невдала-відповідь" 2>"$TMP/помилка"; then
  echo 'ШИРОКІ-СЛОВА-ТЕСТ-ПОМИЛКА: прийнято невідомий режим' >&2; exit 1
fi
test ! -s "$TMP/невдала-відповідь"
"$BIN/sensshyryna" --широкі-слова "$TMP/слова.sens" > "$TMP/відновлений.tsv"
cmp "$TMP/відновлений.tsv" "$TMP/еталон.tsv"
echo 'ШИРОКІ-СЛОВА-CLI-ГАРАЗД D12-D13=транспорт байти-трити=точні нулі=збережено укр=проєкція арифметика=НЕ-ДОВЕДЕНА'
