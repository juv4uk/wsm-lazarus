#!/usr/bin/env bash
# G2.26. Один pinned source, exact word, шість непрограмних поверхонь.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN"
mkdir -p build/m0.2/projections/units build/m0.2/projections/bin
for entry in test-projections sensproekcii; do
  if [[ "$entry" == test-projections ]]; then src=scripts/test-projections.pas
  else src=src/sensproekcii.lpr; fi
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/projections/units" \
    -FE"$ROOT/build/m0.2/projections/bin" -o"$entry" "$src"
done
timeout 30s build/m0.2/projections/bin/test-projections external/sens
BIN="$ROOT/build/m0.2/projections/bin/sensproekcii"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
timeout 10s "$BIN" external/sens 0101001 > "$TMP/добре"
grep -Fx 'координата: D7:0101001' "$TMP/добре"
grep -Fx 'ук: ")"' "$TMP/добре"
grep -Fx 'LISP: ()' "$TMP/добре"
timeout 10s "$BIN" external/sens 001 > "$TMP/д3"
grep -Fx 'en: quote' "$TMP/д3"
for bits in 0012 01010x 00000000000; do
  if timeout 10s "$BIN" external/sens "$bits" > "$TMP/помилка-stdout" 2> "$TMP/помилка-stderr"; then
    echo 'ПОМИЛКА: прийнято некоректні біти або домен' >&2
    exit 1
  fi
  test ! -s "$TMP/помилка-stdout"
  grep -F 'ПРОЄКЦІЇ-ПОМИЛКА:' "$TMP/помилка-stderr" >/dev/null
done
echo 'ПРОЄКЦІЇ-CLI-ГАРАЗД FPC=реальний шість=точно stdout-при-відмові=порожньо'
