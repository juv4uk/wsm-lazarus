#!/usr/bin/env bash
# G6.50: окремий реальний checked FPC gate для приватного EIR1.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'EIR1-ПОБІТОВО-БЛОК: Free Pascal не встановлено' >&2
  exit 127
}
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
# Існуючі позитиви/негативи лишаються обов'язковими.
bash ./scripts/test-exactir-wire.sh
mkdir -p build/m0.2/eir1-pobitovo-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/eir1-pobitovo-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-eir1-pobitovo "$ROOT/scripts/test-eir1-pobitovo.pas"
"$ROOT/build/m0.2/bin/test-eir1-pobitovo"
