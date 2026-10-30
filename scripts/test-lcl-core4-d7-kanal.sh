#!/usr/bin/env bash
# G5.33: реальний FPC процесний Core4, атомарний batch=3+4 у Lazarus.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-D7-КАНАЛ: немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-D7-КАНАЛ: немає xvfb-run' >&2; exit 127; }
./scripts/check-pin.sh
# Усі вже наявні downstream негативні тести каналу — не вимикати!
timeout 180 bash ./scripts/test-core4wireclient.sh
mkdir -p build/lcl-core4-d7-kanal/units
timeout 120 lazbuild --ws=gtk2 --build-all gui/core4-d7-kanal.lpi
GUI="$ROOT/build/lcl-core4-d7-kanal/core4-d7-kanal"
CHILD="$ROOT/build/m0.2/bin/senscore4kanal"
test -x "$GUI" && test -x "$CHILD"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LC_ALL=C.UTF-8 timeout 50 xvfb-run -a -s '-screen 0 1440x900x24' \
 "$GUI" --самоперевірка "$ROOT" "$CHILD" > "$TMP/out" 2>"$TMP/err" || {
  cat "$TMP/err" >&2; cat "$TMP/out" >&2; exit 1;
 }
cat "$TMP/out"
cat "$TMP/err" >&2
grep -Fq 'LCL-D7-ПОСТІЙНИЙ-КАНАЛ-ГАРАЗД' "$TMP/out"
grep -Fq 'LCL-D7-АТОМАРНИЙ-ПАКЕТ-ГАРАЗД Lazarus=GTK2 batch=3+4 W1/W24=побайтово' "$TMP/out"
grep -Fq 'remote-пізня-відмова=атомарно T5M-пошкодження=відхилено порожній=відхилено' "$TMP/out"
grep -Fq 'PID=незмінний відновлення=так D7=повний REPL=ні' "$TMP/out"
echo 'LCL-D7-КАНАЛ-CI-ГАРАЗД FPC=справжній Lazarus=GTK2 окремий-PID=так'
