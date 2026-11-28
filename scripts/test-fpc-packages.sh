#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FPC_BIN="${FPC:-fpc}"
BUILD="$ROOT/build/fpc-packages"
BIN="$BUILD/bin"
BOOTSTRAP_UNITS="$BUILD/bootstrap-units"
TEST_UNITS="$BUILD/test-units"
STAGE="$BUILD/stage"

command -v "$FPC_BIN" >/dev/null 2>&1 || {
  echo "FPC-PACKAGES-FAIL compiler-not-found=$FPC_BIN" >&2
  exit 127
}
TARGET="$("$FPC_BIN" -iTP)-$("$FPC_BIN" -iTO)"

mkdir -p "$BIN" "$BOOTSTRAP_UNITS" "$TEST_UNITS" "$STAGE/units/$TARGET"

VERSION="$("$FPC_BIN" -iV)"
echo "FPC-PACKAGES compiler=$VERSION target=$TARGET"

# FPMake itself is ordinary Pascal code using the installed fpmkunit package.
FPMake="$BIN/fpmake"
timeout 120s "$FPC_BIN" -Mobjfpc \
  -FU"$BOOTSTRAP_UNITS" -FE"$BIN" "-o$FPMake" \
  "$ROOT/packages/fpmake.pp"

# Build both packages and install their compiled units into an isolated prefix.
# No root/system installation is performed by this test.
(
  cd "$ROOT"
  FPC="$FPC_BIN" timeout 180s "$FPMake" buildinstall \
    --prefix="$STAGE" --unitinstalldir="$STAGE/units/$TARGET" -v
)

INSTALL_UNITS="$STAGE/units/$TARGET"
test -n "$(find "$INSTALL_UNITS" -maxdepth 1 -name 'wsm.source.ppu' -print -quit)"
test -n "$(find "$INSTALL_UNITS" -maxdepth 1 -name 'wsm.domain.ppu' -print -quit)"

# A separate consumer sees only installed package outputs, not donor src/ or
# package-local build directories.
timeout 120s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$INSTALL_UNITS" \
  -FU"$TEST_UNITS" -FE"$BIN" \
  -otest-fpc-packages "$ROOT/packages/tests/test_fpc_packages.pas"

timeout 30s "$BIN/test-fpc-packages"
