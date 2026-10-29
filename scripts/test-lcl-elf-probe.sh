#!/usr/bin/env bash
# G6.34: нативний процес ELF64 + FPC та діюча кнопка GTK2/LCL.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in lazbuild fpc xvfb-run timeout readelf; do
  command -v "$tool" >/dev/null ||
    { echo "БЛОК: потрібен $tool" >&2; exit 127; }
done
[[ "$(uname -m)" == x86_64 ]] || { echo 'БЛОК: потрібен x86-64' >&2; exit 78; }
./scripts/check-pin.sh
# Не виключаємо попередні графічні/машинні докази: виконуємо їх.
bash ./scripts/test-lcl-elf-physical.sh
OUT="$ROOT/build/lcl-elf-probe"
mkdir -p "$OUT/bin" "$OUT/units"
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$OUT/units" -FE"$OUT/bin" -otest-elfprobe \
  "$ROOT/scripts/test-elfprobe.pas"
W="$ROOT/build/m0.2/elfcondt5m/witnesses"
"$OUT/bin/test-elfprobe" "$W"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '\363' > "$TMP/зіпсований.sens"
T5M="$ROOT/build/lcl-elf-physical/bin/senst5m"
printf '0\n' > "$TMP/д1.words"
"$T5M" --pack-words "$TMP/д1.words" > "$TMP/д1.sens"
printf '10 110 10 000000000000 1 01 01\n' > "$TMP/д12.words"
"$T5M" --pack-words "$TMP/д12.words" > "$TMP/д12.sens"
BIN="$ROOT/build/lcl-elf/bin/elf-inspector"
LC_ALL=C.UTF-8 timeout 40 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка-машина \
  "$W/істинна-одиниця.sens" \
  "$W/істинний-нуль.sens" \
  "$W/вичерпання.sens" \
  "$W/рівність-хиба.sens" \
  "$TMP/зіпсований.sens" \
  "$TMP/д1.sens" "$TMP/д12.sens" \
  > "$TMP/вивід.log" 2> "$TMP/помилки.log"
test ! -s "$TMP/помилки.log"
grep -F 'LCL-ELF-ВИКОНАННЯ-ГАРАЗД' "$TMP/вивід.log"
echo 'LCL-ELF-МАШИНА-CI-ГАРАЗД FPC=так Lazarus=GTK2/xvfb ELF=9 D12+=відхилено'
