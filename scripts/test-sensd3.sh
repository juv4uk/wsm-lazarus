#!/usr/bin/env bash
# G5.5: реально виконуємо вузький D3 через вже pinned wsm.nativeeval.
# Ні full REPL, ні Core4, ні новий SENS-оракул тут не заявлено.
set -euo pipefail
КОРІНЬ=$(cd "$(dirname "$0")/.." && pwd)
FPC_BIN=${FPC:-fpc}
ОДИНИЦІ="$КОРІНЬ/build/m0.2/d3-session-units"
БІНАРНІ="$КОРІНЬ/build/m0.2/bin"
mkdir -p "$ОДИНИЦІ" "$БІНАРНІ"
"$FPC_BIN" -B -Mobjfpc -Fu"$КОРІНЬ/src" -FU"$ОДИНИЦІ" -FE"$БІНАРНІ" \
  -otest-sensd3 "$КОРІНЬ/scripts/test-sensd3.pas"
"$FPC_BIN" -B -Mobjfpc -Fu"$КОРІНЬ/src" -FU"$ОДИНИЦІ" -FE"$БІНАРНІ" \
  -osensd3 "$КОРІНЬ/src/sensd3.lpr"
(cd "$КОРІНЬ" && "$БІНАРНІ/test-sensd3")
ТИМЧАСОВО=$(mktemp -d)
trap 'rm -rf "$ТИМЧАСОВО"' EXIT
printf "так\nні\n(сполучити так\n ні)\n" | "$БІНАРНІ/sensd3" "$КОРІНЬ/external/sens" >"$ТИМЧАСОВО/вихід" 2>"$ТИМЧАСОВО/помилки"
printf "1\n0\n(1 . 0)\n" >"$ТИМЧАСОВО/еталон"
cmp "$ТИМЧАСОВО/вихід" "$ТИМЧАСОВО/еталон"
test ! -s "$ТИМЧАСОВО/помилки"
if printf "(перше ())\nтак\n" | "$БІНАРНІ/sensd3" "$КОРІНЬ/external/sens" >"$ТИМЧАСОВО/вихід" 2>"$ТИМЧАСОВО/помилки"; then
  echo "D3-СЕСІЯ-ПОМИЛКА: хибно допущено невиконувану форму" >&2
  exit 1
fi
printf "1\n" >"$ТИМЧАСОВО/еталон"
cmp "$ТИМЧАСОВО/вихід" "$ТИМЧАСОВО/еталон"
grep -q "ПОМИЛКА D3" "$ТИМЧАСОВО/помилки"
grep -q "native selector requires nonempty pair" "$ТИМЧАСОВО/помилки"
echo "D3-ОБОЛОНКА-OK stdin=виконано помилка=відхилена продовження=працює повний-REPL=НІ"
