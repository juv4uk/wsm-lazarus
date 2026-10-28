#!/usr/bin/env bash
# G5.12: справжній Lazarus/GTK2, три D1/D3 фізичні корені одного .sens.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'ФОРМИ-БЛОКЕР: немає Lazarus' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'ФОРМИ-БЛОКЕР: немає Xvfb' >&2; exit 127; }
./scripts/check-no-lcl.sh
./scripts/check-pin.sh
# Це також збирає real FPC CLI senspaket і три фізичні корені в одному файлі.
bash ./scripts/test-binarybatch.sh
mkdir -p build/lcl-formas/units
lazbuild --widgetset=gtk2 --build-all gui/sens-formas.lpi
BIN="$ROOT/build/lcl-formas/sens-formas"
[[ -x "$BIN" ]] || { echo 'ФОРМИ-БЛОКЕР: GUI не зібрано' >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
GOOD="build/m0.2/binarybatch-positive.sens"
BAD="build/m0.2/binarybatch-unsupported.sens"
UNCLOSED="build/m0.2/binarybatch-unclosed.sens"
CORRUPT="build/m0.2/binarybatch-corrupt.sens"
"$ROOT/build/m0.2/bin/senspaket" --пакет "$GOOD" > "$TMP/еталон.txt"
printf '1\n(1)\n0\n' > "$TMP/очікувано.txt"
cmp "$TMP/еталон.txt" "$TMP/очікувано.txt"
ONE=$(sed -n '1p' "$TMP/еталон.txt")
TWO=$(sed -n '2p' "$TMP/еталон.txt")
THREE=$(sed -n '3p' "$TMP/еталон.txt")
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' "$BIN" \
  --самоперевірка "$GOOD" "$BAD" "$UNCLOSED" "$CORRUPT" \
  "$ONE" "$TWO" "$THREE" \
  > "$TMP/GUI.txt" 2> "$TMP/помилки.txt" || {
    cat "$TMP/GUI.txt" >&2
    cat "$TMP/помилки.txt" >&2
    exit 1
  }
cat "$TMP/GUI.txt"
test ! -s "$TMP/помилки.txt" || { cat "$TMP/помилки.txt" >&2; exit 1; }
grep -F 'LCL-ФОРМИ-ГАРАЗД' "$TMP/GUI.txt"
grep -F 'точні-трити=так' "$TMP/GUI.txt"
echo 'LCL-ФОРМИ-ЗБІРКА-ГАРАЗД Lazarus=реальний GTK2=так CLI=точний D2=фізичний'
