#!/usr/bin/env bash
# G6.9 — реальний Lazarus GUI для перевіреного машинного x86-64 backend.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-ELF-БЛОК: немає Lazarus' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-ELF-БЛОК: немає Xvfb' >&2; exit 127; }
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
mkdir -p build/lcl-elf/bin build/lcl-elf/units
lazbuild --widgetset=gtk2 --build-all gui/elf-inspector.lpi
BIN="$ROOT/build/lcl-elf/bin/elf-inspector"
test -x "$BIN"
# Цей чинний тест дійсно запускає машинні ELF64 на Linux x86-64 і
# порівнює їхні байти з існуючим SENS-виконавцем. Не підмінюємо його GUI.
bash ./scripts/test-elfd1.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '\363' > "$TMP/зіпсований.sens"
: > "$TMP/порожній.sens"
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка \
  "$ROOT/build/m0.2/elfd1/0.sens" \
  "$ROOT/build/m0.2/elfd1/1.sens" \
  "$TMP/зіпсований.sens" \
  "$ROOT/build/m0.2/elfd1/quote.sens" \
  "$TMP/порожній.sens" \
  > "$TMP/лог" 2> "$TMP/помилки"
test ! -s "$TMP/помилки"
grep -F 'LCL-МАШИННИЙ-ELF-ГАРАЗД' "$TMP/лог"
echo 'LCL-МАШИННИЙ-ELF-ЗБІРКА-ГАРАЗД Lazarus=GTK2 Xvfb=так ELF64=машинно-виконаний'
