#!/usr/bin/env bash
# G2.27: CLI тільки над pinned G2.26 каталогом; не другий парсер.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN"
mkdir -p build/m0.2/projections/units build/m0.2/projections/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/projections/units" \
  -FE"$ROOT/build/m0.2/projections/bin" -osensproekcii \
  src/sensproekcii.lpr
BIN="$ROOT/build/m0.2/projections/bin/sensproekcii"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
timeout 15s "$BIN" external/sens 001 > "$TMP/д3"
grep -Fx 'координата: D3:001' "$TMP/д3"
grep -Fx 'ук: як-є' "$TMP/д3"
grep -Fx 'LISP: QUOTE' "$TMP/д3"
timeout 15s "$BIN" external/sens 0101001 > "$TMP/д7"
grep -Fx 'координата: D7:0101001' "$TMP/д7"
grep -Fx 'ук: ")"' "$TMP/д7"
grep -Fx 'LISP: ()' "$TMP/д7"
timeout 15s "$BIN" external/sens 0010110 > "$TMP/син"
grep -Fx 'ук: ()' "$TMP/син"
timeout 15s "$BIN" external/sens 0000000110 > "$TMP/д10"
grep -Fx 'координата: D10:0000000110' "$TMP/д10"
grep -Fx 'ук: якщо' "$TMP/д10"
grep -Fx 'en: if' "$TMP/д10"
for bits in 0012 01010x 00000000000; do
  if timeout 15s "$BIN" external/sens "$bits" > "$TMP/помилка-stdout" 2> "$TMP/помилка-stderr"; then
    echo 'ПОМИЛКА: прийнято некоректні біти або домен' >&2
    exit 1
  fi
  test ! -s "$TMP/помилка-stdout"
  grep -F 'ПРОЄКЦІЇ-ПОМИЛКА:' "$TMP/помилка-stderr" >/dev/null
done
# Відсутній pinned authority directory не може надати успішний результат.
if timeout 15s "$BIN" "$TMP/немає" 001 > "$TMP/помилка-stdout" 2> "$TMP/помилка-stderr"; then
  echo 'ПОМИЛКА: відсутню таблицю допущено' >&2
  exit 1
fi
test ! -s "$TMP/помилка-stdout"
grep -F 'ПРОЄКЦІЇ-ПОМИЛКА:' "$TMP/помилка-stderr" >/dev/null
echo 'ПРОЄКЦІЇ-CLI-ГАРАЗД FPC=реальний G2.26=повторно-використано D3-D7-D10=пройдено негативні=так'
