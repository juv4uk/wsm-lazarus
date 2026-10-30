#!/usr/bin/env bash
# G2.24: реальний компілятор FPC і pinned D1–D10, без дублювання SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'ДОМЕН-ШВИДКИЙ-БЛОКЕР: немає справжнього FPC' >&2
  exit 127
}
./scripts/check-pin.sh
mkdir -p build/m0.2/domain-fast-units build/m0.2/bin
for case in test-domain-fast test-domain test-bind; do
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
    -FU"$ROOT/build/m0.2/domain-fast-units" -FE"$ROOT/build/m0.2/bin" \
    -o"$case" "$ROOT/scripts/$case.pas"
  "$ROOT/build/m0.2/bin/$case"
done
echo 'ДОМЕН-ШВИДКИЙ-CI-ГАРАЗД FPC=3.2.2 pinned=D1-D10 старі-тести=збережено'
