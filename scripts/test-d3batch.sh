#!/usr/bin/env bash
# G3.16 — справжнє native D3 batch, heaptrc і pinned domain gate.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'ПАКЕТ-D3-БЛОК: FPC відсутній' >&2; exit 127; }
mkdir -p build/d3batch/units build/d3batch/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/d3batch/units" -FE"$ROOT/build/d3batch/bin" \
  -otest-d3batch "$ROOT/scripts/test-d3batch.pas"
"$ROOT/build/d3batch/bin/test-d3batch" 2>&1 | tee build/d3batch/heaptrc.log
grep -Fq 'ПАКЕТ-D3-ГАРАЗД' build/d3batch/heaptrc.log
grep -Fq '0 unfreed memory blocks' build/d3batch/heaptrc.log
if grep -E '[1-9][0-9]* unfreed memory blocks' build/d3batch/heaptrc.log; then
  echo 'ПАКЕТ-D3-БЛОК: витік пам’яті' >&2
  exit 1
fi
