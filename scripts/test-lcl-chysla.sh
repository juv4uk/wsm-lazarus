#!/usr/bin/env bash
# G3.29 — реальний FPC/GTK2 Lazarus з фізичними негативами.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v fpc >/dev/null || { echo 'Відсутній FPC' >&2; exit 127; }
command -v lazbuild >/dev/null || { echo 'Відсутній Lazarus' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'Відсутній Xvfb' >&2; exit 127; }
command -v timeout >/dev/null || { echo 'Відсутній timeout' >&2; exit 127; }
./scripts/check-pin.sh
# Фізична і математична ратифікація вже перевіряються цим чинним gate.
bash ./scripts/test-numericplane.sh
mkdir -p build/lcl/bin build/lcl/chysla-units
lazbuild --ws=gtk2 gui/sens-chysla-okno.lpi
test -x "$ROOT/build/lcl/bin/sens-chysla-okno"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LC_ALL=C.UTF-8 timeout --signal=TERM --kill-after=10s 180s \
  xvfb-run -a "$ROOT/build/lcl/bin/sens-chysla-okno" \
  --самоперевірка "$TMP" | tee "$ROOT/build/lcl/chysla-units/тест-числа.log"
grep -F 'ЛКЛ-ЧИСЛА-ГАРАЗД Lazarus=GTK2' \
  "$ROOT/build/lcl/chysla-units/тест-числа.log"
grep -F '.lisp-як-бінарний=відхилено відновлення=так' \
  "$ROOT/build/lcl/chysla-units/тест-числа.log"
echo 'ЛКЛ-ЧИСЛА-ЗБІРКА-ГАРАЗД FPC=так Lazarus=так Xvfb=так'
