#!/usr/bin/env bash
# Фізичні GTK2/Lazarus віджети: трити та межі слів, без семантики SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-ТРИТИ-БЛОКЕР: немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-ТРИТИ-БЛОКЕР: немає xvfb-run' >&2; exit 127; }
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
mkdir -p build/lcl-tritmap/bin build/lcl-tritmap/units build/lcl-tritmap/fpc-units
lazbuild --ws=gtk2 --build-all gui/trit-map.lpi
BIN="$ROOT/build/lcl-tritmap/bin/trit-map"
[[ -x "$BIN" ]] || { echo 'LCL-ТРИТИ-ПОМИЛКА: немає GUI виконуваного файла' >&2; exit 1; }
FPC_BIN=$(printenv FPC || printf fpc)
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$ROOT/build/lcl-tritmap/fpc-units" \
  -FE"$ROOT/build/lcl-tritmap/bin" -osenst5m "$ROOT/src/senst5m.lpr"
PACK="$ROOT/build/lcl-tritmap/bin/senst5m"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '10 111 00 1 000 01\n' > "$TMP/слова.words"
"$PACK" --pack-words "$TMP/слова.words" > "$TMP/слова.sens"
printf '\363' > "$TMP/зіпсований.sens"
awk 'BEGIN { for(i=1;i<=1021;i++) printf "0"; printf "\n" }' > "$TMP/завеликий.words"
"$PACK" --pack-words "$TMP/завеликий.words" > "$TMP/завеликий.sens"
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка "$TMP/слова.sens" "$TMP/зіпсований.sens" \
  "$TMP/завеликий.sens" | tee "$TMP/лог"
grep -F 'LCL-ТРИТИ-ГАРАЗД' "$TMP/лог"
echo 'LCL-ТРИТИ-ЗБІРКА-ГАРАЗД Lazarus=справжній GTK2=так Xvfb=так'
