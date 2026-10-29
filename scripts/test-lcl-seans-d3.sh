#!/usr/bin/env bash
# Реальні FPC та Lazarus/GTK2/Xvfb; лише вузька проєкція «ук» та D3.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v fpc >/dev/null || { echo "Не знайдено fpc" >&2; exit 127; }
command -v lazbuild >/dev/null || { echo "Не знайдено lazbuild" >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo "Не знайдено xvfb-run" >&2; exit 127; }
command -v timeout >/dev/null || { echo "Не знайдено timeout" >&2; exit 127; }
test -f external/sens/contracts/language-contract-12.lisp
./scripts/check-pin.sh
mkdir -p build/lcl/bin build/lcl/seans-d3-units build/m0.2/seans-d3-units build/m0.2/bin
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/seans-d3-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-sessiond3 "$ROOT/scripts/test-sessiond3.pas"
"$ROOT/build/m0.2/bin/test-sessiond3"
lazbuild --ws=gtk2 gui/sens-seans-d3.lpi
test -x "$ROOT/build/lcl/bin/sens-seans-d3"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LC_ALL=C.UTF-8 timeout --signal=TERM --kill-after=10s 180s \
  xvfb-run -a "$ROOT/build/lcl/bin/sens-seans-d3" \
  --самоперевірка "$ROOT/external/sens" "$TMP" \
  | tee "$ROOT/build/lcl/seans-d3-units/перевірка-ЛКЛ.log"
grep -F 'ЛКЛ-СЕАНС-Д3-ГАРАЗД Lazarus=GTK2' \
  "$ROOT/build/lcl/seans-d3-units/перевірка-ЛКЛ.log"
grep -F 'файл-ук=так .sens=відхилено відновлення=так' \
  "$ROOT/build/lcl/seans-d3-units/перевірка-ЛКЛ.log"
echo 'СЕАНС-Д3-ЛКЛ-ЗБІРКА-ГАРАЗД FPC=так Lazarus=так Xvfb=так'
