#!/usr/bin/env bash
# G1.8 — справжній Free Pascal і CLI файл-на-файл.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null 2>&1 || {
  echo 'УК-РАУНДТРИП-БЛОК: Free Pascal недоступний' >&2
  exit 127
}
mkdir -p build/m0.2/ukroundtrip/units build/m0.2/ukroundtrip/bin
for target in test-ukroundtrip sensukrlisp; do
  if [[ "$target" == test-ukroundtrip ]]; then
    source=scripts/test-ukroundtrip.pas
  else
    source=src/sensukrlisp.lpr
  fi
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$ROOT/build/m0.2/ukroundtrip/units" \
    -FE"$ROOT/build/m0.2/ukroundtrip/bin" \
    -o"$target" "$source"
done
./build/m0.2/ukroundtrip/bin/test-ukroundtrip
BIN="$ROOT/build/m0.2/ukroundtrip/bin/sensukrlisp"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$BIN" --вивести-ук build/m0.2/ukroundtrip/valid.sens \
  "$TMP/звичайна.lisp" >"$TMP/result"
cmp "$TMP/звичайна.lisp" build/m0.2/ukroundtrip/valid.expected.lisp
grep -F 'УКРАЇНСЬКА-ПРОЄКЦІЯ-ГАРАЗД' "$TMP/result" >/dev/null
"$BIN" --пакувати-ук "$TMP/звичайна.lisp" "$TMP/повернено.sens" >"$TMP/result"
cmp "$TMP/повернено.sens" build/m0.2/ukroundtrip/valid.sens
grep -F 'УКРАЇНСЬКЕ-ПАКУВАННЯ-ГАРАЗД' "$TMP/result" >/dev/null

"$BIN" --пакувати-ук build/m0.2/ukroundtrip/valid.input.lisp \
  "$TMP/людський.sens" >"$TMP/result"
cmp "$TMP/людський.sens" build/m0.2/ukroundtrip/valid.sens

printf 'збережений файл\n' >"$TMP/існуючий.lisp"
printf 'збережений файл\n' >"$TMP/очікуваний"
if "$BIN" --вивести-ук build/m0.2/ukroundtrip/valid.sens \
  "$TMP/існуючий.lisp" >"$TMP/bad.out" 2>"$TMP/bad.err"; then
  echo 'УК-РАУНДТРИП-ПОМИЛКА: вихід перезаписано' >&2
  exit 1
fi
cmp "$TMP/існуючий.lisp" "$TMP/очікуваний"
test ! -s "$TMP/bad.out"

for label in ambiguous separator dotted invalid; do
  if "$BIN" --вивести-ук "build/m0.2/ukroundtrip/$label.sens" \
      "$TMP/відхилено.lisp" >"$TMP/bad.out" 2>"$TMP/bad.err"; then
    echo 'УК-РАУНДТРИП-ПОМИЛКА: неоднозначна фізична проєкція прийнята' >&2
    exit 1
  fi
  test ! -e "$TMP/відхилено.lisp"
  test ! -s "$TMP/bad.out"
  grep -F 'УКРАЇНСЬКА-ПРОЄКЦІЯ-ПОМИЛКА' "$TMP/bad.err" >/dev/null
done
for label in invalid missing; do
  if "$BIN" --пакувати-ук "build/m0.2/ukroundtrip/$label.lisp" \
      "$TMP/відхилено.sens" >"$TMP/bad.out" 2>"$TMP/bad.err"; then
    echo 'УК-РАУНДТРИП-ПОМИЛКА: пошкоджений український вхід прийнято' >&2
    exit 1
  fi
  test ! -e "$TMP/відхилено.sens"
  test ! -s "$TMP/bad.out"
  grep -F 'УКРАЇНСЬКА-ПРОЄКЦІЯ-ПОМИЛКА' "$TMP/bad.err" >/dev/null
done
if "$BIN" --вивести-ук build/m0.2/ukroundtrip/valid.input.lisp \
    "$TMP/хибне.lisp" >"$TMP/bad.out" 2>"$TMP/bad.err"; then
  echo 'УК-РАУНДТРИП-ПОМИЛКА: текст удав двійковий вхід' >&2
  exit 1
fi
test ! -e "$TMP/хибне.lisp"
test ! -s "$TMP/bad.out"
grep -F 'ПОМИЛКА: потрібні вхід.sens' "$TMP/bad.err" >/dev/null

"$BIN" --вивести-ук build/m0.2/ukroundtrip/valid.sens \
  "$TMP/повтор.lisp" >"$TMP/result"
cmp "$TMP/повтор.lisp" "$TMP/звичайна.lisp"
echo 'УК-РАУНДТРИП-CLI-ГАРАЗД .sens=двійковий .lisp=звичайна-ук атомарно=так roundtrip=байт-у-байт'
