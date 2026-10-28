#!/usr/bin/env bash
# Справжня FPC + Lazarus/LCL фізична перевірка приватного образу WSMIMG1.
# Це не системний образ, не .sens транспорт і не семантика SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v fpc >/dev/null || { echo 'LCL-ОБРАЗ-БЛОКЕР: немає Free Pascal' >&2; exit 127; }
command -v lazbuild >/dev/null || { echo 'LCL-ОБРАЗ-БЛОКЕР: немає Lazarus' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-ОБРАЗ-БЛОКЕР: немає Xvfb' >&2; exit 127; }
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
mkdir -p build/lcl-imagecatalog/bin build/lcl-imagecatalog/units build/lcl-imagecatalog/fpc-units
fpc -B -Mobjfpc -Fu"$ROOT/src" -FU"$ROOT/build/lcl-imagecatalog/fpc-units" \
  -FE"$ROOT/build/lcl-imagecatalog/bin" -otest-imagecatalog \
  "$ROOT/scripts/test-imagecatalog.pas"
TEST="$ROOT/build/lcl-imagecatalog/bin/test-imagecatalog"
"$TEST"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
"$TEST" --створити-фікстуру "$TMP/лексичний_образ.wsmimg"
cp "$TMP/лексичний_образ.wsmimg" "$TMP/пошкоджений.wsmimg"
printf '\001' | dd of="$TMP/пошкоджений.wsmimg" bs=1 seek=15 count=1 conv=notrunc status=none
lazbuild --ws=gtk2 --build-all gui/image-catalog.lpi
BIN="$ROOT/build/lcl-imagecatalog/bin/image-catalog"
[[ -x "$BIN" ]] || { echo 'LCL-ОБРАЗ-ПОМИЛКА: немає графічної програми' >&2; exit 1; }
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' "$BIN" \
  --самоперевірка "$TMP/лексичний_образ.wsmimg" \
  "$TMP/пошкоджений.wsmimg" | tee "$TMP/вихід.txt"
grep -F 'LCL-ОБРАЗ-ГАРАЗД' "$TMP/вихід.txt"
echo 'LCL-ОБРАЗ-ЗБІРКА-ГАРАЗД real_FPC=так Lazarus=так GTK2=так Xvfb=так'
