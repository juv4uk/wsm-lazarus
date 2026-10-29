#!/usr/bin/env bash
# Два незалежні реальні механічні докази: FPC loader та Lazarus LCL grid.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v fpc >/dev/null || { echo "Немає fpc" >&2; exit 127; }
command -v lazbuild >/dev/null || { echo "Немає lazbuild" >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo "Немає xvfb-run" >&2; exit 127; }
mkdir -p build/lcl/bin build/lcl/proektsii-units build/m0.2/bin build/m0.2/proektsii-units
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/proektsii-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-proektsii "$ROOT/scripts/test-proektsii.pas"
"$ROOT/build/m0.2/bin/test-proektsii"
lazbuild --ws=gtk2 gui/sens-proektsii.lpi
test -x build/lcl/bin/sens-proektsii
# Справжні фізичні .sens створює FPC selftest лише у власному TMP.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LC_ALL=C.UTF-8 xvfb-run -a "$ROOT/build/lcl/bin/sens-proektsii" \
  --selftest "$ROOT/external/sens" "$TMP" | tee "$ROOT/build/lcl/proektsii-units/шіст-проєкцій.log"
grep -F 'LCL-ШІСТЬ-ПРОЄКЦІЙ-ПОШУК-ГАРАЗД' \
  "$ROOT/build/lcl/proektsii-units/шіст-проєкцій.log"
grep -F 'LCL-ПРОЄКЦІЇ-ГАРАЗД' \
  "$ROOT/build/lcl/proektsii-units/шіст-проєкцій.log"
grep -F 'LCL-Д7-ФАЙЛ-ПРОЄКЦІЇ-ГАРАЗД Lazarus=GTK2 T5M=канонічно слів=3' \
  "$ROOT/build/lcl/proektsii-units/шіст-проєкцій.log"
grep -F 'W1-пізній=відхилено 129=відхилено помилки=атомарні відновлення=так' \
  "$ROOT/build/lcl/proektsii-units/шіст-проєкцій.log"
echo "ПРОЄКЦІЇ-ЗБІРКА-ГАРАЗД FPC=так Lazarus=так Xvfb=так шість-проєкцій=пошук"
