#!/usr/bin/env bash
# Фізична перевірка справжнього Lazarus/LCL Canvas і Xvfb.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-СПЕКТР-ПОМИЛКА: немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-СПЕКТР-ПОМИЛКА: немає xvfb-run' >&2; exit 127; }
mkdir -p build/lcl/bin build/lcl/spectrum-units build/m0.2/bin build/m0.2/spectrum-units
lazbuild --ws=gtk2 gui/domain-spectrum.lpi
test -x build/lcl/bin/domain-spectrum
FPC_BIN=$(printenv FPC || echo fpc)
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/spectrum-units" -FE"$ROOT/build/m0.2/bin" \
  -osenst5m "$ROOT/src/senst5m.lpr"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Підтверджений фізичний T5M: D3:111, D1:1, D3:000 у D2 списку.
printf '10 111 00 1 000 01\n' > "$TMP/позитив.words"
"$ROOT/build/m0.2/bin/senst5m" --pack-words "$TMP/позитив.words" > "$TMP/позитив.sens"
# Окремий реальний D4:0101 із pinned двома РІЗНИМИ назвами:
#   ук  = порожнє?; укр = порожній?. Не переводити у числа.
printf '10 111 00 1 000 01 0101\n' > "$TMP/повна-укр.words"
"$ROOT/build/m0.2/bin/senst5m" --pack-words "$TMP/повна-укр.words" > "$TMP/повна-укр.sens"
# Неканонічний байт за T5M та окремо валідний T5M із відкритим D2.
printf '\363' > "$TMP/поганий-t5m.sens"
printf '10 111 00 1 000\n' > "$TMP/поганий-d2.words"
"$ROOT/build/m0.2/bin/senst5m" --pack-words "$TMP/поганий-d2.words" > "$TMP/поганий-d2.sens"
LC_ALL=C.UTF-8 xvfb-run -a "$ROOT/build/lcl/bin/domain-spectrum" \
  --selftest "$TMP/позитив.sens" "$TMP/поганий-t5m.sens" \
  "$TMP/поганий-d2.sens" "$TMP/повна-укр.sens" | tee "$TMP/перевірка.log"
grep -F 'LCL-СПЕКТР-ГАРАЗД' "$TMP/перевірка.log"
grep -F 'LCL-УК-ПОШУК-ГАРАЗД' "$TMP/перевірка.log"
grep -F 'LCL-ПОВНА-УКР-ГАРАЗД' "$TMP/перевірка.log"
grep -F 'LCL-ТОЧНА-КООРДИНАТА-ГАРАЗД' "$TMP/перевірка.log"
grep -F 'LCL-ФІЗИЧНІ-МЕЖІ-ГАРАЗД W2=[3,6) W4=[10,11) W5=[12,15) W7=[19,23)' "$TMP/перевірка.log"
echo 'LCL-СПЕКТР-ПЕРЕВІРКА-ГАРАЗД Lazarus=збудовано Xvfb=виконано графіка=справжня ук=точний-пошук семантика=не-дубльована'
