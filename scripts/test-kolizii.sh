#!/usr/bin/env bash
# Реальний FPC та pinned шість поверхонь, пізня відмова без stdout.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN"
mkdir -p build/m0.2/kolizii/units build/m0.2/kolizii/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/kolizii/units" \
  -FE"$ROOT/build/m0.2/kolizii/bin" -osenskolizii \
  src/senskolizii.lpr
BIN="$ROOT/build/m0.2/kolizii/bin/senskolizii"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
timeout 20s "$BIN" external/sens > "$TMP/result"
grep -Fx 'Перевірено pinned D1–D10: координат=2046; D7=128; колонок=6' "$TMP/result"
grep -Fx 'ук: пар=0' "$TMP/result"
grep -Fx 'укр: пар=0' "$TMP/result"
grep -Fx 'san: пар=0' "$TMP/result"
grep -Fx 'en: пар=3; приклад=D6:101000 + D8:11000101' "$TMP/result"
grep -Fx 'LISP: пар=1; приклад=D6:101000 + D8:11000101' "$TMP/result"
grep -Fx 'sym: пар=14; приклад=D4:0000 + D6:000100' "$TMP/result"
test "$(wc -l < "$TMP/result")" -eq 7
if timeout 20s "$BIN" > "$TMP/out" 2>"$TMP/err"; then exit 1; fi
test ! -s "$TMP/out"
grep -F 'АУДИТ-ПРОЄКЦІЙ-ПОМИЛКА:' "$TMP/err" >/dev/null
if timeout 20s "$BIN" "$TMP/missing" > "$TMP/out" 2>"$TMP/err"; then exit 1; fi
test ! -s "$TMP/out"
grep -F 'АУДИТ-ПРОЄКЦІЙ-ПОМИЛКА:' "$TMP/err" >/dev/null
mkdir -p "$TMP/broken/lib/domains"
for d in {1..9}; do
  ln -s "$ROOT/external/sens/lib/domains/d$d.lisp" \
    "$TMP/broken/lib/domains/d$d.lisp"
done
printf '(domain-table-1\n)\n' > "$TMP/broken/lib/domains/d10.lisp"
if timeout 20s "$BIN" "$TMP/broken" > "$TMP/out" 2>"$TMP/err"; then exit 1; fi
test ! -s "$TMP/out"
grep -F 'АУДИТ-ПРОЄКЦІЙ-ПОМИЛКА:' "$TMP/err" >/dev/null
echo 'АУДИТ-ПРОЄКЦІЙ-ГАРАЗД D1-D10=2046 D7=128 колонок=6 негативних=3'
