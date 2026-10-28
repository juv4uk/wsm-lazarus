#!/usr/bin/env bash
# G1.9: графічний Lazarus-огляд з точними фізичними джерелами SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
command -v lazbuild >/dev/null || { echo 'LCL-ШИРОКІ-БЛОК: немає Lazarus' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-ШИРОКІ-БЛОК: немає Xvfb' >&2; exit 127; }
mkdir -p build/lcl-wide/bin build/lcl-wide/units build/lcl-wide/fpc
lazbuild --widgetset=gtk2 --build-all gui/wide-inspector.lpi
BIN="$ROOT/build/lcl-wide/bin/wide-inspector"
test -x "$BIN"
FPC_BIN=$(printenv FPC || printf fpc)
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/lcl-wide/fpc" -FE"$ROOT/build/lcl-wide/bin" \
  -osenst5m "$ROOT/src/senst5m.lpr"
PACK="$ROOT/build/lcl-wide/bin/senst5m"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '0 000000000001 0000000000000 000000000000000000000001\n' \
  > "$TMP/точні-слова"
"$PACK" --пакувати-слова "$TMP/точні-слова" > "$TMP/широкі.sens"
printf '\363' > "$TMP/пошкоджений.sens"
: > "$TMP/порожній.sens"

# Не вигадуємо D12 числовий свідок; беремо три файли з того самого
# pinned Git SHA, навіть якщо sparse checkout виключає tests/semantic/.
git -C external/sens show HEAD:tests/semantic/d5-d12-numberp-law.sens \
  > "$TMP/кореневий.sens"
git -C external/sens show HEAD:tests/semantic/d5-d12-numberp-law \
  > "$TMP/кореневий-біти"
git -C external/sens show HEAD:tests/semantic/d5-d12-numberp-law.lisp \
  > "$TMP/кореневий.lisp"
# Звичайна українська Lisp-проєкція з реального SENS.
grep -F '(число? (частка 1 3))' "$TMP/кореневий.lisp"
# Копія побайтово відповідає лише фізичному бітовому поданню,
# а не текстовим описам закону чи десятковим літералам.
"$PACK" --пакувати-слова "$TMP/кореневий-біти" \
  > "$TMP/зворотний.sens"
cmp "$TMP/кореневий.sens" "$TMP/зворотний.sens"
test "$(wc -c < "$TMP/кореневий.sens")" = 17

# Нормативне джерело кореневого проекту — Contract 12; це не
# декларація числового закону в Pascal.
git -C external/sens show HEAD:contracts/language-contract-12.lisp \
  > "$TMP/мовний-закон.lisp"
grep -F 'D12 numeric-first decision' "$TMP/мовний-закон.lisp"

LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x850x24' \
  "$BIN" --самоперевірка "$TMP/широкі.sens" \
  "$TMP/кореневий.sens" "$TMP/пошкоджений.sens" \
  "$TMP/порожній.sens" "$TMP/кореневий.lisp" \
  > "$TMP/лог" 2> "$TMP/помилки"
test ! -s "$TMP/помилки"
grep -F 'LCL-ШИРОКІ-ГАРАЗД' "$TMP/лог"
echo 'LCL-ШИРОКІ-ЗБІРКА-ГАРАЗД Lazarus=справжній root=.sens+.lisp+bits pinned=так'
