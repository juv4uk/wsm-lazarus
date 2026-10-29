#!/usr/bin/env bash
# G2.26: pinned D1..D10, справжня FPC і Lazarus GTK2/Xvfb.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
command -v lazbuild >/dev/null
command -v xvfb-run >/dev/null
command -v fpc >/dev/null
# У поточному sparse authority усі 10 нормативних domain файлів мають бути присутні.
for d in {1..10}; do test -s "external/sens/lib/domains/d$d.lisp"; done
mkdir -p build/lcl-projections/bin build/m0.2/projectioncatalog/bin \
  build/m0.2/projectioncatalog/units
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/projectioncatalog/units" \
  -FE"$ROOT/build/m0.2/projectioncatalog/bin" \
  -otest-projectioncatalog "$ROOT/scripts/test-projectioncatalog.pas"
LC_ALL=C.UTF-8 timeout 60s "$ROOT/build/m0.2/projectioncatalog/bin/test-projectioncatalog" \
  "$ROOT" 2>&1 | tee build/m0.2/projectioncatalog/result.log
grep -E 'rows=2046 .*negatives=10' build/m0.2/projectioncatalog/result.log

lazbuild --ws=gtk2 gui/projection-catalog.lpi
test -x build/lcl-projections/bin/projection-catalog
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LC_ALL=C.UTF-8 timeout 65s xvfb-run -a \
  "$ROOT/build/lcl-projections/bin/projection-catalog" --selftest "$ROOT" \
  > "$TMP/gui.log" 2>&1
cat "$TMP/gui.log"
grep -F 'LCL-ПРОЄКЦІЇ-ГАРАЗД D1-D10=2046 колонки=6' "$TMP/gui.log"
echo 'ПРОЄКЦІЇ-FPC-LAZARUS-ГАРАЗД exact=2046 поверхні=6 GTK2=Xvfb негативи=10'
