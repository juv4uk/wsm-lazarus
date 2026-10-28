#!/usr/bin/env bash
# Фізична Lazarus/LCL панель широких слів; жодної числової арифметики.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'ШИРОКІ-LCL-БЛОК: немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'ШИРОКІ-LCL-БЛОК: немає xvfb-run' >&2; exit 127; }
./scripts/check-no-lcl.sh
./scripts/check-pin.sh
# Чинний фізичний механізм перевіряємо окремо: той самий, що живить GUI.
bash scripts/test-widespan.sh
mkdir -p build/lcl-shyroki/bin build/lcl-shyroki/units
lazbuild --widgetset=gtk2 --build-all gui/sens-shyroki.lpi
BIN="$ROOT/build/lcl-shyroki/bin/sens-shyroki"
[[ -x "$BIN" ]] || { echo 'ШИРОКІ-LCL-ПОМИЛКА: немає зібраного executable' >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PACK="$ROOT/build/m0.2/widespan-bin/senst5m"
printf '0 000000000001 01 0000000000000 10101010101 111111111111\n' > "$TMP/слова.txt"
"$PACK" --пакувати-слова "$TMP/слова.txt" > "$TMP/добрий.sens"
printf '000000000000 111111111111\n' > "$TMP/спільні.txt"
"$PACK" --пакувати-слова "$TMP/спільні.txt" > "$TMP/спільні.sens"
printf '0 1 10 01 1111111111 11111111111\n' > "$TMP/короткі.txt"
"$PACK" --пакувати-слова "$TMP/короткі.txt" > "$TMP/короткі.sens"
python3 - "$TMP/межа.txt" <<'PY'
import sys
with open(sys.argv[1], 'w', encoding='utf-8') as out:
    out.write(" ".join(["000000000000"] * 257) + "\n")
PY
"$PACK" --пакувати-слова "$TMP/межа.txt" > "$TMP/межа.sens"
printf '\363' > "$TMP/зіпсований.sens"
: > "$TMP/порожній.sens"
printf '(сполучити ні так)\n' > "$TMP/проєкція.lisp"
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x900x24' "$BIN" \
  --самоперевірка "$TMP/добрий.sens" "$TMP/спільні.sens" \
  "$TMP/короткі.sens" "$TMP/зіпсований.sens" "$TMP/порожній.sens" \
  "$TMP/межа.sens" "$TMP/проєкція.lisp" >"$TMP/лог" 2>"$TMP/помилки"
test ! -s "$TMP/помилки"
grep -F 'LCL-ШИРОКІ-ГАРАЗД' "$TMP/лог"
grep -F 'арифметика=НЕ-ДОВЕДЕНА' "$TMP/лог"
echo 'LAZARUS-ШИРОКІ-ЗБІРКА-ГАРАЗД LCL=GTK2 D12+=фізичні-слова укр=тільки-проєкція'
