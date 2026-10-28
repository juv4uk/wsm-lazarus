#!/usr/bin/env bash
# G5.5: реально виконуємо вузький D3 через вже pinned wsm.nativeeval.
# Ні full REPL, ні Core4, ні новий SENS-оракул тут не заявлено.
set -euo pipefail
KORIN=$(cd "$(dirname "$0")/.." && pwd)
FPC_BIN=${FPC:-fpc}
ODYN="$KORIN/build/m0.2/d3-session-units"
BIN="$KORIN/build/m0.2/bin"
mkdir -p "$ODYN" "$BIN"
"$FPC_BIN" -B -Mobjfpc -Fu"$KORIN/src" -FU"$ODYN" -FE"$BIN" \
  -otest-sensd3 "$KORIN/scripts/test-sensd3.pas"
"$FPC_BIN" -B -Mobjfpc -Fu"$KORIN/src" -FU"$ODYN" -FE"$BIN" \
  -osensd3 "$KORIN/src/sensd3.lpr"
(cd "$KORIN" && "$BIN/test-sensd3")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf "так\nні\n(сполучити так\n ні)\n" | "$BIN/sensd3" "$KORIN/external/sens" >"$TMP/вихід" 2>"$TMP/помилки"
printf "1\n0\n(1 . 0)\n" >"$TMP/еталон"
cmp "$TMP/вихід" "$TMP/еталон"
test ! -s "$TMP/помилки"
if printf "(перше ())\nтак\n" | "$BIN/sensd3" "$KORIN/external/sens" >"$TMP/вихід" 2>"$TMP/помилки"; then
  echo "D3-СЕСІЯ-ПОМИЛКА: хибно допущено невиконувану форму" >&2
  exit 1
fi
printf "1\n" >"$TMP/еталон"
cmp "$TMP/вихід" "$TMP/еталон"
grep -q "ПОМИЛКА D3" "$TMP/помилки"
grep -q "native selector requires nonempty pair" "$TMP/помилки"
echo "D3-ОБОЛОНКА-OK stdin=виконано помилка=відхилена продовження=працює повний-REPL=НІ"
