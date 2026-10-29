#!/usr/bin/env bash
# Реальне Lazarus/LCL GTK2 виконання через pinned SENS; без графічної семантики.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-ПОМИЛКА немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-ПОМИЛКА немає xvfb-run' >&2; exit 127; }
bash ./scripts/check-no-lcl.sh
bash ./scripts/check-pin.sh
mkdir -p build/lcl-vykonannia/units build/lcl-vykonannia/t5m-units \
  build/lcl-vykonannia/bin
lazbuild --widgetset=gtk2 --build-all gui/sens-vykonannia.lpi
# Самі канонічні фізичні свідки створює чинний двійковий senst5m,
# а НЕ код нового вікна. Компілюється справжнім FPC у власні units.
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/lcl-vykonannia/t5m-units" \
  -FE"$ROOT/build/lcl-vykonannia/bin" \
  -osenst5m "$ROOT/src/senst5m.lpr" >/dev/null
BIN="$ROOT/build/lcl-vykonannia/sens-vykonannia"
if [[ ! -x "$BIN" ]]; then
  BIN="$ROOT/build/lcl-vykonannia/units/sens-vykonannia"
fi
test -x "$BIN" || { echo 'LCL-ПОМИЛКА не створено програму' >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf 'ні\n(атом? ())\n' > "$TMP/проєкція.lisp"
# Справжні фізичні слова, а не англійська чи українська проєкція.
printf '1\n' > "$TMP/д1.words"
printf '10 001 10 1 0 01 01\n' > "$TMP/цитата.words"
printf '10 0101 1 01\n' > "$TMP/недопущено-д4.words"
printf '1 0\n' > "$TMP/два-корені.words"
for variant in д1 цитата недопущено-д4 два-корені; do
  "$ROOT/build/lcl-vykonannia/bin/senst5m" --пакувати-слова \
    "$TMP/$variant.words" > "$TMP/$variant.sens"
done
printf '\363' > "$TMP/пошкоджено.sens"
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка "$TMP/проєкція.lisp" \
    "$TMP/д1.sens" "$TMP/цитата.sens" "$TMP/недопущено-д4.sens" \
    "$TMP/пошкоджено.sens" "$TMP/два-корені.sens" \
    | tee "$TMP/лог.txt"
grep -F 'LCL-ФІЗИЧНЕ-D3-ГАРАЗД' "$TMP/лог.txt"
grep -F 'LCL-ВИКОНАННЯ-ГАРАЗД' "$TMP/лог.txt"
grep -F 'повний-REPL=ні Core4=ні' "$TMP/лог.txt"
echo 'LAZARUS-ВИКОНАННЯ-ЗБІРКА-ГАРАЗД FPC=справжній LCL=справжні-віджети'
