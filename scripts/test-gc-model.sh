#!/usr/bin/env bash
# G3.42: вимірюваний deterministic model-based тест існуючого GC.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN="${FPC:-fpc}"
command -v "$FPC_BIN" >/dev/null || { echo 'GC-МОДЕЛЬ-БЛОК: немає fpc' >&2; exit 127; }
mkdir -p build/m0.2/gc-model/units build/m0.2/gc-model/bin
timeout 100 "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/gc-model/units" \
  -FE"$ROOT/build/m0.2/gc-model/bin" -otest-gc-model \
  "$ROOT/scripts/test-gc-model.pas"
timeout 100 "$ROOT/build/m0.2/gc-model/bin/test-gc-model" | tee build/m0.2/gc-model/звіт.txt
grep -F 'GC-МОДЕЛЬ-ГАРАЗД seeds=4 кроків=9600' build/m0.2/gc-model/звіт.txt
grep -F 'GC-МОДЕЛЬ-МЕЖА Core1=НЕ-ВИКОНУЄТЬСЯ' build/m0.2/gc-model/звіт.txt
