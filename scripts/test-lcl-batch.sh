#!/usr/bin/env bash
# Фізична CLI-парність кількох ОКРЕМИХ .sens, реальні LCL/GTK2 віджети.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'ПАКЕТ-БЛОКЕР: немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'ПАКЕТ-БЛОКЕР: немає xvfb-run' >&2; exit 127; }
./scripts/check-no-lcl.sh
./scripts/check-pin.sh
bash ./scripts/test-binaryexec.sh
mkdir -p build/lcl-batch/units
lazbuild --widgetset=gtk2 --build-all gui/sens-batch.lpi
BIN="$ROOT/build/lcl-batch/sens-batch"
[[ -x "$BIN" ]] || BIN="$ROOT/build/lcl-batch/units/sens-batch"
[[ -x "$BIN" ]] || { echo 'ПАКЕТ-БЛОКЕР: немає графічної програми' >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Незалежний корінь D1:1 пакується в один реальний канонічний T5M byte 0xA1.
printf '\241' > "$TMP/істина.sens"
printf '\363' > "$TMP/зіпсований.sens"
GOOD2="$ROOT/build/m0.2/binaryexec-valid.sens"
BAD="$ROOT/build/m0.2/binaryexec-invalid.sens"
EXPECTED1=$("$ROOT/build/m0.2/bin/sensvykon" --виконати "$TMP/істина.sens")
EXPECTED2=$("$ROOT/build/m0.2/bin/sensvykon" --виконати "$GOOD2")
[[ "$EXPECTED1" == "1" && "$EXPECTED2" == "(1)" ]] || {
  echo 'ПАКЕТ-БЛОКЕР: не підтверджені два CLI результати' >&2; exit 1;
}
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' "$BIN" \
  --самоперевірка "$TMP/істина.sens" "$GOOD2" "$BAD" \
  "$TMP/зіпсований.sens" "$EXPECTED1" "$EXPECTED2" >"$TMP/лог" 2>"$TMP/помилки"
cat "$TMP/лог"
test ! -s "$TMP/помилки"
grep -F 'LCL-ПАКЕТ-ГАРАЗД' "$TMP/лог"
grep -F 'часткових-рядків=0' "$TMP/лог"
echo 'ПАКЕТ-LCL-ЗБІРКА-ГАРАЗД Lazarus=справжній GTK2=так CLI=байтова-тотожність'
