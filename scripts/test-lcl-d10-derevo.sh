#!/usr/bin/env bash
# Графічний фізичний D10: лише чинні pinned закони й exact D2 дерево.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'Д10-LCL-БЛОК: немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'Д10-LCL-БЛОК: немає xvfb-run' >&2; exit 127; }
./scripts/check-no-lcl.sh
./scripts/check-pin.sh
# Справжній FPC двійковий пакувальник і його старі негативи.
bash scripts/test-t5m-cli.sh >/dev/null
mkdir -p build/lcl-d10-derevo/bin build/lcl-d10-derevo/units
lazbuild --widgetset=gtk2 --build-all gui/sens-d10-derevo.lpi
BIN="$ROOT/build/lcl-d10-derevo/bin/sens-d10-derevo"
PACK="$ROOT/build/m0.2/bin/senst5m"
[[ -x "$BIN" ]] || { echo 'Д10-LCL-ПОМИЛКА: немає executable' >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '10 0000000000 0010110 000 01 1111111111\n' > "$TMP/добрий.words"
"$PACK" --пакувати-слова "$TMP/добрий.words" > "$TMP/добрий.sens"
printf '00000000000\n' > "$TMP/w11.words"
"$PACK" --пакувати-слова "$TMP/w11.words" > "$TMP/w11.sens"
printf '000000000000\n' > "$TMP/w12.words"
"$PACK" --пакувати-слова "$TMP/w12.words" > "$TMP/w12.sens"
printf '10 0000000000\n' > "$TMP/незакрито.words"
"$PACK" --пакувати-слова "$TMP/незакрито.words" > "$TMP/незакрито.sens"
printf '\363' > "$TMP/зіпсовано.sens"
printf '(сполучити ні так)\n' > "$TMP/проєкція.lisp"
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x900x24' "$BIN" \
  --самоперевірка "$TMP/добрий.sens" "$TMP/w11.sens" \
  "$TMP/w12.sens" "$TMP/зіпсовано.sens" \
  "$TMP/незакрито.sens" "$TMP/проєкція.lisp" \
  > "$TMP/stdout" 2> "$TMP/stderr"
test ! -s "$TMP/stderr"
grep -Fq 'LCL-Д10-ДЕРЕВО-ГАРАЗД' "$TMP/stdout"
grep -Fq 'виконання=НЕ-ДОВЕДЕНО' "$TMP/stdout"
echo 'LAZARUS-Д10-ДЕРЕВО-ЗБІРКА-ГАРАЗД FPC=3.2.x LCL=GTK2 D2=точний'
