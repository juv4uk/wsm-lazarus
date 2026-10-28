#!/usr/bin/env bash
# G5.2 source-line buffering: native FPC smoke with injected test executor only.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC_BIN=${FPC:-fpc}
UNITS="$ROOT/build/m0.2/lineinput-units"
BIN="$ROOT/build/m0.2/bin"
mkdir -p "$UNITS" "$BIN"
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" \
  -otest-lineinput "$ROOT/scripts/test-lineinput.pas"
(cd "$ROOT" && "$BIN/test-lineinput")
