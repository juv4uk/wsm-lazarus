#!/usr/bin/env bash
# G6.31 — дійсний Lazarus/GTK2 Canvas + canonical T5M, не REPL.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in lazbuild xvfb-run fpc readelf timeout; do
  command -v "$tool" >/dev/null ||
    { echo "БЛОК: потрібен $tool" >&2; exit 127; }
done
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -m)" == x86_64 ]] || { echo 'БЛОК: потрібен x86-64' >&2; exit 78; }
# Чинний native FPC gate вже запускає дев'ять машинних ELF64 і
# порівнює фізичний stdout, а не лише структуру/вигляд Canvas.
bash ./scripts/test-elfcondt5m.sh
mkdir -p build/lcl-elf/bin build/lcl-elf/units \
         build/lcl-elf-physical/units build/lcl-elf-physical/bin
lazbuild --widgetset=gtk2 --build-all gui/elf-inspector.lpi
BIN="$ROOT/build/lcl-elf/bin/elf-inspector"
test -x "$BIN"
# Лише фізичні test fixtures, без перетворення '0' у D12 числовий закон.
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/lcl-elf-physical/units" \
  -FE"$ROOT/build/lcl-elf-physical/bin" -osenst5m "$ROOT/src/senst5m.lpr"
T5M="$ROOT/build/lcl-elf-physical/bin/senst5m"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '0\n' > "$TMP/д1.words"
"$T5M" --pack-words "$TMP/д1.words" > "$TMP/д1.sens"
printf '10 110 10 000000000000 1 01 01\n' > "$TMP/д12.words"
"$T5M" --pack-words "$TMP/д12.words" > "$TMP/д12.sens"
printf '\363' > "$TMP/зіпсований.sens"
W="$ROOT/build/m0.2/elfcondt5m/witnesses"
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка-фізична-умова \
  "$W/істинна-одиниця.sens" \
  "$W/істинний-нуль.sens" \
  "$W/вичерпання.sens" \
  "$W/рівність-хиба.sens" \
  "$TMP/зіпсований.sens" "$TMP/д1.sens" "$TMP/д12.sens" \
  > "$TMP/вивід.log" 2> "$TMP/помилки.log"
test ! -s "$TMP/помилки.log"
grep -F 'LCL-ELF-ФІЗИЧНА-УМОВА-ГАРАЗД' "$TMP/вивід.log"
echo 'LCL-ELF-ФІЗИЧНИЙ-CI-ГАРАЗД GTK2=так ELF=9 T5M=канонічний D12+=відхилено'
