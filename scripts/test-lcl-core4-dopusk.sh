#!/usr/bin/env bash
# Реальний lazbuild/LCL свідок ТІЛЬКИ структурного pinned Core4 admission.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'CORE4-LCL-БЛОКЕР: немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'CORE4-LCL-БЛОКЕР: немає xvfb-run' >&2; exit 127; }
bash scripts/check-no-lcl.sh
bash scripts/check-pin.sh
mkdir -p build/lcl-core4/units
lazbuild --widgetset=gtk2 --build-all gui/core4-dopusk.lpi
BIN="$ROOT/build/lcl-core4/core4-dopusk"
if [[ ! -x "$BIN" ]]; then BIN="$ROOT/build/lcl-core4/units/core4-dopusk"; fi
[[ -x "$BIN" ]] || { echo 'CORE4-LCL-ПОМИЛКА: немає виконуваної GUI-програми' >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/некоректний-байт/external/sens/lib"
mkdir -p "$TMP/незакритий/external/sens/lib"
printf '(\300\257)' > "$TMP/некоректний-байт/external/sens/lib/core4.lisp"
printf '(незакритий' > "$TMP/незакритий/external/sens/lib/core4.lisp"
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' "$BIN" \
  --самоперевірка "$TMP/відсутній" "$TMP/некоректний-байт" "$TMP/незакритий" |
  tee "$TMP/лог"
grep -F 'LCL-CORE4-ДОПУСК-ГАРАЗД' "$TMP/лог"
grep -F 'Core4-виконання=НІ' "$TMP/лог"
echo 'LAZARUS-CORE4-ЗБІРКА-ГАРАЗД LCL=справжній pinned=так виконання=ні'
