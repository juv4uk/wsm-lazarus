#!/usr/bin/env bash
# G1.49: справжній Lazarus GTK2 та реальний pinned сучасний Core1.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
command -v fpc >/dev/null || { echo 'CORE1-LCL-ПОМИЛКА: немає FPC' >&2; exit 127; }
command -v lazbuild >/dev/null || { echo 'CORE1-LCL-ПОМИЛКА: немає Lazarus' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'CORE1-LCL-ПОМИЛКА: немає Xvfb' >&2; exit 127; }
# Той самий pinned .sens/.lisp спершу перевіряє чинний FPC CLI Core1.1.
mkdir -p build/lcl-core1/bin build/lcl-core1/units build/lcl-core1/fpc-units
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/lcl-core1/fpc-units" \
  -FE"$ROOT/build/lcl-core1/bin" \
  "$ROOT/src/senscore1dopus.lpr"
build/lcl-core1/bin/senscore1dopus --допуск "$ROOT" > build/lcl-core1/bin/dopus.out
grep -Fq 'CORE1-ДОПУСК-ГАРАЗД' build/lcl-core1/bin/dopus.out
grep -Fq 'виконання=ні' build/lcl-core1/bin/dopus.out
lazbuild --ws=gtk2 gui/sens-core1-ogliad.lpi
test -x build/lcl-core1/bin/sens-core1-ogliad
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp external/sens/lib/core1.sens "$TMP/пошкоджений.sens"
printf '\377' >> "$TMP/пошкоджений.sens"
cp external/sens/lib/core1.lisp "$TMP/пошкоджений.lisp"
printf '\n)\n' >> "$TMP/пошкоджений.lisp"
LC_ALL=C.UTF-8 timeout 90s xvfb-run -a \
  build/lcl-core1/bin/sens-core1-ogliad \
  --самоперевірка \
  "$ROOT/external/sens/lib/core1.sens" \
  "$ROOT/external/sens/lib/core1.lisp" \
  "$TMP/пошкоджений.sens" \
  "$TMP/пошкоджений.lisp" > "$TMP/вікно.out"
grep -Fq 'LCL-CORE1-ФІЗИЧНИЙ-ОГЛЯД-ГАРАЗД форм=96 перша-D4=0011' "$TMP/вікно.out"
grep -Fq 'відмова=очищено відновлення=так Core1-виконання=НЕ-ПЕРЕВІРЕНО' "$TMP/вікно.out"
cat "$TMP/вікно.out"
echo 'CORE1-LCL-ЗБІРКА-ГАРАЗД Lazarus=GTK2 FPC=справжній pinned=12.0'
