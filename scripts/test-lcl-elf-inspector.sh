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
# Незалежний чинний native gate доводить усі 4 справжні CMP/SETE ELF
# та рівність виконаного ELF із FPC sensvykon (НЕ тільки графіку).
bash ./scripts/test-elfeq.sh
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка-eq \
  "$ROOT/build/m0.2/elfeq/тотожні-нулі.sens" \
  "$ROOT/build/m0.2/elfeq/нуль-один.sens" \
  "$ROOT/build/m0.2/elfd1/0.sens" \
  "$TMP/зіпсований.sens" \
  > "$TMP/лог-eq" 2> "$TMP/помилки-eq"
test ! -s "$TMP/помилки-eq"
grep -F 'LCL-ELF-EQ-ГАРАЗД' "$TMP/лог-eq"
# Реальні D3:110 ELF на x86-64 із чинним pinned T5M/D2/binder.
# Ця перевірка збирає 22 фізичні програми, запускає кожний ELF
# та порівнює stdout із чинним sensvykon; GUI не є oracle.
bash ./scripts/test-elfcond.sh
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка-умова \
  "$ROOT/build/m0.2/elfcond/одна-істинна.sens" \
  "$ROOT/build/m0.2/elfcond/рівність-00.sens" \
  "$ROOT/build/m0.2/elfcond/рівність-01.sens" \
  "$ROOT/build/m0.2/elfcond/тридцять-дві-рівності.sens" \
  "$ROOT/build/m0.2/elfeq/тотожні-нулі.sens" \
  "$ROOT/build/m0.2/elfd1/0.sens" \
  "$TMP/зіпсований.sens" \
  > "$TMP/лог-умова" 2> "$TMP/помилки-умова"
test ! -s "$TMP/помилки-умова"
grep -F 'LCL-ELF-УМОВА-ГАРАЗД' "$TMP/лог-умова"
echo 'LCL-МАШИННИЙ-ELF-ЗБІРКА-ГАРАЗД Lazarus=GTK2 Xvfb=так ELF64=машинно-виконаний'
echo 'LCL-ELF-EQ-ЗБІРКА-ГАРАЗД Lazarus=GTK2 D3:101=машинне-CMP-SETE негативні=відхилено'
echo 'LCL-ELF-УМОВА-ЗБІРКА-ГАРАЗД Lazarus=GTK2 D3:110=машинне-CMP/JNE вкладене-EQ=машинне-CMP/SETE 22-виконання=так'\n