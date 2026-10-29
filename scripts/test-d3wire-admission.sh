#!/usr/bin/env bash
# G5.40 — незалежний механічний FPC допуск D2 відповіді (без oracle заяв).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN="${FPC:-fpc}"
command -v "$FPC_BIN" >/dev/null
mkdir -p build/d3-wire-admission/bin build/d3-wire-admission/units
timeout 90 "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/d3-wire-admission/units" \
  -FE"$ROOT/build/d3-wire-admission/bin" -otest-d3wire-admission \
  scripts/test-d3wire-admission.pas
if ! timeout 20 "$ROOT/build/d3-wire-admission/bin/test-d3wire-admission" \
  >build/d3-wire-admission/доказ.txt 2>build/d3-wire-admission/купа.txt; then
  cat build/d3-wire-admission/доказ.txt >&2
  cat build/d3-wire-admission/купа.txt >&2
  exit 1
fi
grep -Fx 'Д3-КАНАЛ-ДОПУСК-ГАРАЗД FPC=так позитиви=6 негативи=10 W24=непрозоро D2=повністю' \
  build/d3-wire-admission/доказ.txt
grep -q '0 unfreed memory blocks' build/d3-wire-admission/купа.txt
echo 'Д3-КАНАЛ-ПЕРЕВІРЕНО pinned=так FPC=так витоки=0'
