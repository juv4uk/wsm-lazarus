#!/usr/bin/env bash
# Доводить реальний Lazarus/LCL плюс тотожність результату чинному CLI.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-ВИКОНАННЯ-БЛОК: відсутній lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-ВИКОНАННЯ-БЛОК: відсутній xvfb-run' >&2; exit 127; }
./scripts/check-no-lcl.sh
./scripts/check-pin.sh
# Фізичні fixtures і виконавчий CLI проходять власні незалежні FPC тести.
bash ./scripts/test-binaryexec.sh
# Той самий реальний FPC адаптер координат — без GUI-власного decoder.
bash ./scripts/test-execfault.sh
mkdir -p build/lcl-runner/units
lazbuild --widgetset=gtk2 --build-all gui/sens-runner.lpi
BIN="$ROOT/build/lcl-runner/sens-runner"
[[ -x "$BIN" ]] || { echo 'LCL-ВИКОНАННЯ-БЛОК: немає GUI-бінарника' >&2; exit 1; }
GOOD="build/m0.2/binaryexec-valid.sens"
BAD="build/m0.2/binaryexec-invalid.sens"
NESTED="build/m0.2/execfault-nested.sens"
EOF_FILE="build/m0.2/execfault-eof.sens"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '\363' > "$TMP/пошкоджений.sens"
EXPECTED=$(./build/m0.2/bin/sensvykon --виконати "$GOOD")
[[ "$EXPECTED" == '(1)' ]] || { echo 'LCL-ВИКОНАННЯ-БЛОК: неочікуваний CLI результат' >&2; exit 1; }
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' "$BIN" \
  --самоперевірка "$GOOD" "$BAD" "$NESTED" "$EOF_FILE" \
  "$TMP/пошкоджений.sens" "$EXPECTED" | tee "$TMP/лог"
grep -F 'LCL-ФІЗИЧНА-ПОМИЛКА-ГАРАЗД' "$TMP/лог"
echo 'LCL-ВИКОНАННЯ-ЗБІРКА-ГАРАЗД Lazarus=справжній екран=GTK2 результат=CLI адреси=трит-байт'
