#!/usr/bin/env bash
# G3.41: справжній FPC перевіряє спільні GC/лексичні корені.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'GC-ЛЕКСИКА-БЛОКЕР: Free Pascal відсутній' >&2
  exit 127
}
bash scripts/check-pin.sh
mkdir -p build/m0.2/gclexical-units build/m0.2/gclexical-bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/gclexical-units" \
  -FE"$ROOT/build/m0.2/gclexical-bin" -otest-gclexical \
  "$ROOT/scripts/test-gclexical.pas"
timeout 90s "$ROOT/build/m0.2/gclexical-bin/test-gclexical"
# Без послаблення існуючих GC / envframe regression.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/gclexical-units" \
  -FE"$ROOT/build/m0.2/gclexical-bin" -otest-envframe \
  "$ROOT/scripts/test-envframe.pas"
timeout 90s "$ROOT/build/m0.2/gclexical-bin/test-envframe"
timeout 600s bash scripts/test-gc.sh
