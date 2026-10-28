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
# Runtime stack-root scope admission remains a purely mechanical FPC check.
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" \
  -otest-gc-scopes "$ROOT/scripts/test-gc-scopes.pas"
(cd "$ROOT" && "$BIN_DIR/test-gc-scopes")

# G7.3 independent native debugger frame/backtrace mechanism smoke.
# Does not execute SENS syntax or assert language semantics.
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" \
  -otest-debugtrace "$ROOT/scripts/test-debugtrace.pas"
(cd "$ROOT" && "$BIN_DIR/test-debugtrace")

# G7.6 physical debugger exception snapshot: captured frames must survive
# nested try/finally unwinding without claiming any SENS error semantics.
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" \
  -otest-faulttrace "$ROOT/scripts/test-faulttrace.pas"
(cd "$ROOT" && "$BIN_DIR/test-faulttrace")
