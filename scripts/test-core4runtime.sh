#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'CORE4-RUNTIME-БЛОКЕР: немає FPC' >&2; exit 127; }
./scripts/check-pin.sh
mkdir -p build/m0.2/core4-runtime-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/core4-runtime-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-core4runtime "$ROOT/scripts/test-core4runtime.pas"
"$ROOT/build/m0.2/bin/test-core4runtime" "$ROOT"
