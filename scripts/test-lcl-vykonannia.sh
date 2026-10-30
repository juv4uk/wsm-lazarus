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
# Окрема повна проєкція укр, незалежна від чинної короткої ук-сесії.
printf 'ні\nтак\n' > "$TMP/повна-укр.lisp"
# G5.42: парні укр/фізичні файли мають ОДНАКОВЕ ім'я до розширення.
# Правильні фізичні байти з окремого senst5m, НЕ з графічного GUI.
printf '0 1\n' > "$TMP/повна-укр.words"
printf 'ні\nтак\n' > "$TMP/пара-розбіжна.lisp"
printf 'ні\nтак\n' > "$TMP/пара-пошкоджена.lisp"
printf 'ні\nтак\n' > "$TMP/пара-без-фізичного.lisp"
printf 'так\n(як-є так ні)\n' > "$TMP/пара-пізня.lisp"
printf 'car\n' > "$TMP/пара-en.lisp"
printf '123\n' > "$TMP/пара-D12.lisp"
printf '\300\257' > "$TMP/пара-UTF8.lisp"
# Справжні фізичні слова, а не англійська чи українська проєкція.
printf '1\n' > "$TMP/д1.words"
printf '10 001 10 1 0 01 01\n' > "$TMP/цитата.words"
printf '10 0101 1 01\n' > "$TMP/недопущено-д4.words"
printf '1 0\n' > "$TMP/два-корені.words"
# Чотири незалежні справжні D3-форми, третя — фізична EQ.
printf '1 0 10 101 1 1 01 000\n' > "$TMP/пакет-4.words"
# Перша форма успішна, друга — D3:001 із зайвим аргументом.
printf '1 10 001 1 0 01\n' > "$TMP/пакет-пізня-відмова.words"
for variant in д1 цитата недопущено-д4 два-корені пакет-4 пакет-пізня-відмова повна-укр; do
  "$ROOT/build/lcl-vykonannia/bin/senst5m" --пакувати-слова \
    "$TMP/$variant.words" > "$TMP/$variant.sens"
done
printf '\363' > "$TMP/пошкоджено.sens"
# Canonical, але неправильний фізичний порядок — це теж жорстка відмова.
cp "$TMP/два-корені.sens" "$TMP/пара-розбіжна.sens"
cp "$TMP/пошкоджено.sens" "$TMP/пара-пошкоджена.sens"
cp "$TMP/пакет-пізня-відмова.sens" "$TMP/пара-пізня.sens"
for mode in en D12 UTF8; do
  cp "$TMP/повна-укр.sens" "$TMP/пара-$mode.sens"
done
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка "$TMP/проєкція.lisp" \
    "$TMP/д1.sens" "$TMP/цитата.sens" "$TMP/недопущено-д4.sens" \
    "$TMP/пошкоджено.sens" "$TMP/два-корені.sens" \
    "$TMP/пакет-4.sens" "$TMP/пакет-пізня-відмова.sens" \
    "$TMP/повна-укр.lisp" \
    | tee "$TMP/лог.txt"
grep -F 'LCL-УКР-ПАРА-ГАРАЗД .lisp+.sens=побайтово' "$TMP/лог.txt"
grep -F 'LCL-УКР-ФІЗИЧНО-ГАРАЗД укр=повна pinned=T5M' "$TMP/лог.txt"
grep -F 'LCL-ПАКЕТ-D3-ГАРАЗД форми=4' "$TMP/лог.txt"
grep -F 'LCL-ФІЗИЧНЕ-D3-ГАРАЗД' "$TMP/лог.txt"
grep -F 'LCL-ВИКОНАННЯ-ГАРАЗД' "$TMP/лог.txt"
grep -F 'повний-REPL=ні Core4=ні' "$TMP/лог.txt"
echo 'LAZARUS-ВИКОНАННЯ-ЗБІРКА-ГАРАЗД FPC=справжній LCL=справжні-віджети'
