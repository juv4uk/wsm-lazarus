#!/usr/bin/env bash
# Справжня графічна перевірка Lazarus/LCL GTK2.
# Не містить альтернативного evaluator і не перевизначає SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || {
  echo 'LCL-ІНСПЕКТОР-БЛОКЕР: відсутній lazbuild' >&2
  exit 127
}
command -v xvfb-run >/dev/null || {
  echo 'LCL-ІНСПЕКТОР-БЛОКЕР: відсутній xvfb-run' >&2
  exit 127
}
./scripts/check-no-lcl.sh
./scripts/check-pin.sh
mkdir -p build/lcl/units
lazbuild --widgetset=gtk2 --build-all "$ROOT/gui/sens-inspector.lpi"
BIN="$ROOT/build/lcl/sens-inspector"
[[ -x "$BIN" ]] || { echo 'LCL-ІНСПЕКТОР-ПРОВАЛ: відсутній виконуваний GUI' >&2; exit 1; }
TMP=$(mktemp -d "$ROOT/build/lcl/test.XXXXXXXX")
trap 'rm -rf "$TMP"' EXIT

# Незалежні від Pascal золоті фізичні T5M байти:
# D1:0, D2:00, D3:000 -> 5-тритові байти [56,8].
printf '\070\010' > "$TMP/різні-домени.sens"
# D2:10, D3:000, D2:01 -> [99,59].
printf '\143\073' > "$TMP/список.sens"
printf '\377' > "$TMP/заборонений-байт.sens"
# D2:01 (зайве закриття), padding=222 -> [53].
printf '\065' > "$TMP/зайве-закриття.sens"

xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка \
  "$TMP/різні-домени.sens" "$TMP/заборонений-байт.sens" \
  "$TMP/список.sens" "$TMP/зайве-закриття.sens" > "$TMP/вихід"
cat "$TMP/вихід"
grep -q 'LCL-ІНСПЕКТОР-ГАРАЗД' "$TMP/вихід"
grep -q 'виконання=ні' "$TMP/вихід"
echo 'LCL-ЗБІРКА-ГАРАЗД GTK2=так xvfb=так фізичні-D1-D3=різні'
