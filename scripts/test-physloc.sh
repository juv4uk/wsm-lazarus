#!/usr/bin/env bash
# G1.5: physical byte/trit spans for exact-word D2 errors, NOT SENS semantics.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo "PHYSLOC-BLOCKED fpc unavailable" >&2; exit 127; }
./scripts/check-pin.sh
mkdir -p build/m0.2/physloc-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/physloc-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-physloc "$ROOT/scripts/test-physloc.pas"
./build/m0.2/bin/test-physloc
echo 'PHYSLOC-WIDE-CI-ГАРАЗД FPC=справжній W192=opaque fail-closed=так heaptrc=увімкнено'
