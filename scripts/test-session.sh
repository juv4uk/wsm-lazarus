#!/usr/bin/env bash
# G5.1 physical FPC session mechanism test. NOT a SENS REPL/parity claim.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC_BIN=${FPC:-fpc}
UNITS="$ROOT/build/m0.2/session-units"
BIN="$ROOT/build/m0.2/bin"
mkdir -p "$UNITS" "$BIN"
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" \
  -otest-session "$ROOT/scripts/test-session.pas"
(cd "$ROOT" && "$BIN/test-session")

# G5.2 streaming form assembly, with synthetic callback only (not SENS REPL).
bash "$ROOT/scripts/test-lineinput.sh"
