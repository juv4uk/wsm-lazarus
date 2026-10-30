#!/usr/bin/env bash
# Справжній Lazarus GTK2/LCL та віджетовий FPC smoke через Xvfb.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-GC-БЛОКЕР немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-GC-БЛОКЕР немає xvfb-run' >&2; exit 127; }
./scripts/check-no-lcl.sh
./scripts/check-pin.sh
mkdir -p build/lcl-gc/units
lazbuild --widgetset=gtk2 --build-all gui/gc-inspector.lpi
BIN="$ROOT/build/lcl-gc/gc-inspector"
if [[ ! -x "$BIN" ]]; then
  BIN="$ROOT/build/lcl-gc/units/gc-inspector"
fi
test -x "$BIN" || { echo 'LCL-GC-БЛОКЕР: нема скомпільованого GUI' >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка >"$TMP/вихід" 2>"$TMP/помилки"
cat "$TMP/вихід"
test ! -s "$TMP/помилки"
grep -F 'LCL-GC-ГАРАЗД' "$TMP/вихід"
grep -F 'reclaimed=2' "$TMP/вихід"
echo 'LCL-GC-ЗБІРКА-ГАРАЗД Lazarus=реальний GTK2=так негативні=так'
