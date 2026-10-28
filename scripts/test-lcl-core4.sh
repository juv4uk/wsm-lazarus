#!/usr/bin/env bash
# Справжній Lazarus Core4 виклик, без текстового семантичного dispatch.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
command -v lazbuild >/dev/null || { echo 'LCL-CORE4-БЛОКЕР: немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-CORE4-БЛОКЕР: немає xvfb-run' >&2; exit 127; }
bash ./scripts/test-core4runtime.sh
mkdir -p build/lcl-core4/bin build/lcl-core4/units
lazbuild --ws=gtk2 --build-all gui/core4-vykonannia.lpi
BIN="$ROOT/build/lcl-core4/bin/core4-vykonannia"
test -x "$BIN" || { echo 'LCL-CORE4-БЛОКЕР: немає виконуваного файлу' >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка "$ROOT" "$TMP" >"$TMP/звіт" 2>"$TMP/помилки"
test ! -s "$TMP/помилки"
grep -F 'LCL-CORE4-ГАРАЗД' "$TMP/звіт"
grep -F 'D24=точні-біти REPL=ні' "$TMP/звіт"
echo 'LCL-CORE4-ЗБІРКА-ГАРАЗД Lazarus=GTK2-Xvfb binary-Core4=виконано'
