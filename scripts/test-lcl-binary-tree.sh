#!/usr/bin/env bash
# Реальна Lazarus LCL/GTK2 GUI перевірка, не виконавча семантика SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-ДЕРЕВО-БЛОКЕР: немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-ДЕРЕВО-БЛОКЕР: немає xvfb-run' >&2; exit 127; }
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
mkdir -p build/lcl-tree/bin build/lcl-tree/units build/lcl-tree/fpc-units
lazbuild --ws=gtk2 --build-all gui/binary-tree.lpi
BIN="$ROOT/build/lcl-tree/bin/binary-tree"
[[ -x "$BIN" ]] || { echo 'LCL-ДЕРЕВО-ПОМИЛКА: немає GUI виконуваного файла' >&2; exit 1; }
FPC_BIN=$(printenv FPC || printf fpc)
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$ROOT/build/lcl-tree/fpc-units" \
  -FE"$ROOT/build/lcl-tree/bin" -osenst5m "$ROOT/src/senst5m.lpr"
PACK="$ROOT/build/lcl-tree/bin/senst5m"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '10 111 00 1 000 01\n' > "$TMP/список.words"
printf '10 1 11 0 01\n' > "$TMP/пара.words"
"$PACK" --pack-words "$TMP/список.words" > "$TMP/список.sens"
"$PACK" --pack-words "$TMP/пара.words" > "$TMP/пара.sens"
printf '\363' > "$TMP/зіпсований.sens"
awk 'BEGIN { for(i=1;i<=4100;i++) printf "%s1", (i==1?"":" 00 "); printf "\n" }' \
  > "$TMP/багато.words"
"$PACK" --pack-words "$TMP/багато.words" > "$TMP/багато.sens"
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка "$TMP/список.sens" "$TMP/пара.sens" \
  "$TMP/зіпсований.sens" "$TMP/багато.sens" | tee "$TMP/вихід.log"
grep -F 'LCL-ДЕРЕВО-ГАРАЗД' "$TMP/вихід.log"
echo 'LCL-ДЕРЕВО-ЗБІРКА-ГАРАЗД GTK2=так xvfb=так src_LCL=ні'
