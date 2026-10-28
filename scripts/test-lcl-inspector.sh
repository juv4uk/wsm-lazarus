#!/usr/bin/env bash
# Справжня Lazarus/LCL компіляція і фізичне створення віджетів через Xvfb.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-ПОМИЛКА немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-ПОМИЛКА немає xvfb-run' >&2; exit 127; }
mkdir -p build/lcl/bin build/lcl/units build/m0.2/bin build/m0.2/test-units
lazbuild --ws=gtk2 gui/sens-inspector.lpi
test -x build/lcl/bin/sens-inspector
FPC_BIN=$(printenv FPC || echo fpc)
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/test-units" \
  -FE"$ROOT/build/m0.2/bin" -osenst5m "$ROOT/src/senst5m.lpr"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '10 111 00 1 000 01\n' > "$TMP/приклад.words"
"$ROOT/build/m0.2/bin/senst5m" --pack-words "$TMP/приклад.words" > "$TMP/приклад.sens"
printf '\363' > "$TMP/зіпсований.sens"
printf '10 1 00 0 11 10 1 01 01\n' > "$TMP/пара.words"
"$ROOT/build/m0.2/bin/senst5m" --pack-words "$TMP/пара.words" > "$TMP/пара.sens"
LC_ALL=C.UTF-8 xvfb-run -a "$ROOT/build/lcl/bin/sens-inspector" \
  --самоперевірка "$TMP/приклад.sens" "$TMP/зіпсований.sens" "$TMP/пара.sens" | tee "$TMP/лог.txt"
grep -F 'LCL-ДЕРЕВО-ГАРАЗД' "$TMP/лог.txt"
echo 'LCL-ПЕРЕВІРКА-ГАРАЗД Lazarus=справжній GUI=запущено'
