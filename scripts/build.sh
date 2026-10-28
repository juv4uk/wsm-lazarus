#!/usr/bin/env bash
# M0.2 headless build. This proves only the FPC substrate/toolchain.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC_BIN=${FPC:-fpc}
BUILD_DIR="$ROOT/build/m0.2"
BIN_DIR="$BUILD_DIR/bin"
UNIT_DIR="$BUILD_DIR/units"

command -v "$FPC_BIN" >/dev/null 2>&1 || {
  echo "BUILD-FAIL fpc-not-found command=$FPC_BIN" >&2
  exit 127
}

compiler_version=$("$FPC_BIN" -iV)
rm -rf "$BUILD_DIR"
mkdir -p "$BIN_DIR" "$UNIT_DIR"

"$FPC_BIN"   -B   -Mobjfpc   -O1   -Fu"$ROOT/src"   -FU"$UNIT_DIR"   -FE"$BIN_DIR"   -owsm-headless   "$ROOT/src/wsm.headless.lpr"

[[ -x "$BIN_DIR/wsm-headless" ]] || {
  echo "BUILD-FAIL missing-binary path=$BIN_DIR/wsm-headless" >&2
  exit 1
}

# G3.1 isolated mechanical runtime smoke. No SENS evaluation is claimed.
# Keep this in the unclaimed build hook; test.sh/CI workflow belong to other agents.
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" \
  -otest-envframe "$ROOT/scripts/test-envframe.pas"
(cd "$ROOT" && "$BIN_DIR/test-envframe")

# G3.2: реальне обмежене виконання D3, окремо від frame storage.
bash "$ROOT/scripts/test-nativeeval.sh"

echo "BUILD-OK compiler=$compiler_version binary=$BIN_DIR/wsm-headless"
