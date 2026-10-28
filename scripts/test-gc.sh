#!/usr/bin/env bash
# G7.1: mechanically test Pascal mark/sweep only, NOT SENS semantic laws.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC_BIN=${FPC:-fpc}
UNIT_DIR="$ROOT/build/m0.2/gc-units"
BIN_DIR="$ROOT/build/m0.2/bin"
mkdir -p "$UNIT_DIR" "$BIN_DIR"
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" \
  -otest-gc "$ROOT/scripts/test-gc.pas"
(cd "$ROOT" && "$BIN_DIR/test-gc")
