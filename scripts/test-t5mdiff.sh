#!/usr/bin/env bash
# Справжній FPC → фізичні T5M → CLI → Lazarus/LCL GTK2/Xvfb.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
command -v fpc >/dev/null
command -v lazbuild >/dev/null
command -v xvfb-run >/dev/null
mkdir -p build/m0.2/t5mdiff/{bin,units} build/lcl-diff/{bin,units}
for target in test-t5mdiff sensriznytsia; do
  if [[ "$target" == test-t5mdiff ]]; then SRC=scripts/test-t5mdiff.pas
  else SRC=src/sensriznytsia.lpr; fi
  fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/t5mdiff/units" \
    -FE"$ROOT/build/m0.2/t5mdiff/bin" -o"$target" "$SRC"
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
timeout 30s build/m0.2/t5mdiff/bin/test-t5mdiff "$TMP"
BIN=build/m0.2/t5mdiff/bin/sensriznytsia
timeout 10s "$BIN" --порівняти "$TMP/left.sens" "$TMP/left.sens" > "$TMP/equal"
grep -Fx 'СЕНС-ФІЗИЧНО-РІВНІ' "$TMP/equal"
timeout 10s "$BIN" --порівняти "$TMP/left.sens" "$TMP/right.sens" > "$TMP/diff"
grep -F 'СЕНС-ФІЗИЧНА-ВІДМІННІСТЬ слово=2 ліворуч=W1:0' "$TMP/diff"
if timeout 10s "$BIN" --порівняти "$TMP/left.sens" "$TMP/bad.sens" \
  > "$TMP/badstdout" 2> "$TMP/badstderr"; then
  echo 'НЕБЕЗПЕКА: прийнято зіпсований T5M' >&2;exit 1
fi
test ! -s "$TMP/badstdout"
grep -F 'СЕНС-ПОРІВНЯННЯ-ПОМИЛКА' "$TMP/badstderr"
lazbuild --ws=gtk2 --build-all gui/sens-riznytsia.lpi
test -x build/lcl-diff/bin/sens-riznytsia
LC_ALL=C.UTF-8 timeout 30s xvfb-run -a \
  build/lcl-diff/bin/sens-riznytsia --самоперевірка \
  "$TMP/left.sens" "$TMP/right.sens" | tee "$TMP/lcl.log"
grep -F 'LCL-РІЗНИЦЯ-ГАРАЗД' "$TMP/lcl.log"
echo 'T5M-ПОРІВНЮВАЧ-ЗБІРКА-ГАРАЗД FPC=так Lazarus=так'
