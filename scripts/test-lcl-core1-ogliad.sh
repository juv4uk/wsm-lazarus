#!/usr/bin/env bash
# G1.49: справжній Lazarus GTK2 та реальний pinned сучасний Core1.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
command -v fpc >/dev/null || { echo 'CORE1-LCL-ПОМИЛКА: немає FPC' >&2; exit 127; }
command -v lazbuild >/dev/null || { echo 'CORE1-LCL-ПОМИЛКА: немає Lazarus' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'CORE1-LCL-ПОМИЛКА: немає Xvfb' >&2; exit 127; }
# Той самий pinned .sens/.lisp спершу перевіряє чинний FPC CLI Core1.1.
mkdir -p build/lcl-core1/bin build/lcl-core1/units build/lcl-core1/fpc-units
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/lcl-core1/fpc-units" \
  -FE"$ROOT/build/lcl-core1/bin" \
  "$ROOT/src/senscore1dopus.lpr"
build/lcl-core1/bin/senscore1dopus --допуск "$ROOT" > build/lcl-core1/bin/dopus.out
grep -Fq 'CORE1-ДОПУСК-ГАРАЗД' build/lcl-core1/bin/dopus.out
grep -Fq 'виконання=ні' build/lcl-core1/bin/dopus.out
lazbuild --ws=gtk2 gui/sens-core1-ogliad.lpi
test -x build/lcl-core1/bin/sens-core1-ogliad
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp external/sens/lib/core1.sens "$TMP/пошкоджений.sens"
printf '\377' >> "$TMP/пошкоджений.sens"
cp external/sens/lib/core1.lisp "$TMP/пошкоджений.lisp"
printf '\n)\n' >> "$TMP/пошкоджений.lisp"
( umask 000; LC_ALL=C.UTF-8 timeout 90s xvfb-run -a \
  build/lcl-core1/bin/sens-core1-ogliad \
  --самоперевірка \
  "$ROOT/external/sens/lib/core1.sens" \
  "$ROOT/external/sens/lib/core1.lisp" \
  "$TMP/пошкоджений.sens" \
  "$TMP/пошкоджений.lisp" "$TMP" > "$TMP/вікно.out" )
grep -Fq 'LCL-CORE1-ФІЗИЧНИЙ-ОГЛЯД-ГАРАЗД форм=96 перша-D4=0011' "$TMP/вікно.out"
grep -Fq 'відмова=очищено відновлення=так Core1-виконання=НЕ-ПЕРЕВІРЕНО' "$TMP/вікно.out"
# G1.50: Xvfb викликав два СПРАВЖНІ TEdit.OnChange (фізичний .sens
# та окремий український .lisp), перевірив очищення таблиці/мемо і
# повторний фізичний T5M+D2 admission після кожного з них.
grep -Fq 'редагування=2' "$TMP/вікно.out"
grep -Fq 'експорт=2 no-clobber=так не-лісп=так приватний-файл=0600' "$TMP/вікно.out"
test -s "$TMP/перший-корінь.sens"
test -s "$TMP/другий-корінь.sens"
# Справжній POSIX mkstemp: навіть коли umask=000, обидві цілі 0600.
test "$(stat -c '%a' "$TMP/перший-корінь.sens")" = 600
test "$(stat -c '%a' "$TMP/другий-корінь.sens")" = 600
test ! -e "$TMP/помилковий.lisp"
test ! -e "$TMP/застарілий.sens"
! cmp -s "$TMP/перший-корінь.sens" "$TMP/другий-корінь.sens"
# І на файловій межі обидва незалежно проходять канонічний T5M/D2.
build/lcl-core1/bin/senscore1dopus --допуск "$ROOT" >/dev/null

cat "$TMP/вікно.out"
echo 'CORE1-LCL-ЗБІРКА-ГАРАЗД Lazarus=GTK2 FPC=справжній pinned=12.0 експорт=2 no-clobber=так'
