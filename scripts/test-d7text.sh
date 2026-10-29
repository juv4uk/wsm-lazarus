#!/usr/bin/env bash
# G1.22: явний український D7 v2 ↔ фізичний T5M, не SENS-програма.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
mkdir -p build/m0.2/d7text/units build/m0.2/d7text/bin
for target in test-d7text sensd7text; do
  if [[ "$target" == test-d7text ]]; then src=scripts/test-d7text.pas
  else src=src/sensd7text.lpr; fi
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/d7text/units" \
    -FE"$ROOT/build/m0.2/d7text/bin" -o"$target" "$src"
done
timeout 30s build/m0.2/d7text/bin/test-d7text "$ROOT"
BIN="$ROOT/build/m0.2/d7text/bin/sensd7text"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf 'Це 0() №Їґ' > "$TMP/текст.txt"
timeout 10s "$BIN" --кодувати-укр "$ROOT" "$TMP/текст.txt" "$TMP/текст.sens" > "$TMP/код-звіт"
test -s "$TMP/текст.sens"
timeout 10s "$BIN" --читати-укр "$ROOT" "$TMP/текст.sens" "$TMP/обернений.txt" > "$TMP/декод-звіт"
cmp "$TMP/текст.txt" "$TMP/обернений.txt"
# Зайнятий вихід, зокрема dangling symlink, не можна заміняти.
printf 'незмінно' > "$TMP/зайнятий.sens"
printf 'незмінно' > "$TMP/еталон"
ln -s "$TMP/неіснуючий-файл" "$TMP/висячий.sens"
for out in "$TMP/зайнятий.sens" "$TMP/висячий.sens"; do
  if timeout 10s "$BIN" --кодувати-укр "$ROOT" "$TMP/текст.txt" "$out" \
      > "$TMP/погано" 2> "$TMP/відмова"; then
    echo 'Д7-ПОМИЛКА: перезаписано зайнятий файл' >&2;exit 1
  fi
  test ! -s "$TMP/погано"
  grep -F 'Д7-ПРОЄКЦІЯ-ПОМИЛКА' "$TMP/відмова" >/dev/null
done
cmp "$TMP/зайнятий.sens" "$TMP/еталон"
test -L "$TMP/висячий.sens"
test ! -e "$TMP/неіснуючий-файл"
printf 'i' > "$TMP/латинська.txt"
printf '\\363' > "$TMP/хибний.sens"
for case in latin invalid wrongext; do
  if [[ "$case" == latin ]]; then
    mode=--кодувати-укр; input="$TMP/латинська.txt"; output="$TMP/lat.sens"
  elif [[ "$case" == invalid ]]; then
    mode=--читати-укр; input="$TMP/хибний.sens"; output="$TMP/invalid.txt"
  else
    mode=--кодувати-укр; input="$TMP/текст.txt"; output="$TMP/wrong.lisp"
  fi
  if timeout 10s "$BIN" "$mode" "$ROOT" "$input" "$output" \
      > "$TMP/погано" 2> "$TMP/відмова"; then
    echo 'Д7-ПОМИЛКА: некоректну проєкцію прийнято' >&2;exit 1
  fi
  test ! -e "$output"
done
echo 'Д7-CLI-ГАРАЗД ukr-T5M=байтово-точно зайнятий=збережено dangling=збережено негативні=так'
