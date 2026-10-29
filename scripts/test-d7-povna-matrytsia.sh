#!/usr/bin/env bash
# G1.51. Реальний Free Pascal 3.2.x і канонічний D7/T5M, без SENS семантики у Python.
set -euo pipefail
export LANG=C.UTF-8
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
timeout 90 ./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
for need in "$FPC_BIN" python3 timeout git; do
  command -v "$need" >/dev/null || {
    echo "Д7-ПОВНА-МАТРИЦЯ-БЛОК: немає $need" >&2
    exit 127
  }
done
BIN="$ROOT/build/m0.2/d7-povna-matrytsia/bin"
mkdir -p "$BIN"
for program in sensproekcii sensriadkyd7 senst5m; do
  UNITS="$ROOT/build/m0.2/d7-povna-matrytsia/units-$program"
  mkdir -p "$UNITS"
  timeout 120 "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
    -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" -o"$program" \
    "$ROOT/src/$program.lpr"
  test -x "$BIN/$program"
done
timeout 120 python3 "$ROOT/scripts/test-d7-povna-matrytsia.py" "$BIN"
