#!/usr/bin/env bash
# Реальне Lazarus/LCL GTK2 виконання через pinned SENS; без графічної семантики.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-ПОМИЛКА немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-ПОМИЛКА немає xvfb-run' >&2; exit 127; }
bash ./scripts/check-no-lcl.sh
bash ./scripts/check-pin.sh
mkdir -p build/lcl-vykonannia/units
lazbuild --widgetset=gtk2 --build-all gui/sens-vykonannia.lpi
BIN="$ROOT/build/lcl-vykonannia/sens-vykonannia"
if [[ ! -x "$BIN" ]]; then
  BIN="$ROOT/build/lcl-vykonannia/units/sens-vykonannia"
fi
test -x "$BIN" || { echo 'LCL-ПОМИЛКА не створено програму' >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf 'ні\n(атом? ())\n' > "$TMP/проєкція.lisp"
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка "$TMP/проєкція.lisp" | tee "$TMP/лог.txt"
grep -F 'LCL-ВИКОНАННЯ-ГАРАЗД' "$TMP/лог.txt"
grep -F 'повний-REPL=ні Core4=ні' "$TMP/лог.txt"
echo 'LAZARUS-ВИКОНАННЯ-ЗБІРКА-ГАРАЗД FPC=справжній LCL=справжні-віджети'
