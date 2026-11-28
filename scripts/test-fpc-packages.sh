#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FPC_BIN="${FPC:-fpc}"
BUILD="$ROOT/build/fpc-packages"
BIN="$BUILD/bin"
BOOTSTRAP_UNITS="$BUILD/bootstrap-units"
TEST_UNITS="$BUILD/test-units"

command -v "$FPC_BIN" >/dev/null 2>&1 || {
  echo "FPC-PACKAGES-FAIL compiler-not-found=$FPC_BIN" >&2
  exit 127
}
TARGET="$("$FPC_BIN" -iTP)-$("$FPC_BIN" -iTO)"

mkdir -p "$BIN" "$BOOTSTRAP_UNITS" "$TEST_UNITS" \
  "$BUILD/units/wsm-source/$TARGET" "$BUILD/units/wsm-domain/$TARGET"

VERSION="$("$FPC_BIN" -iV)"
echo "FPC-PACKAGES compiler=$VERSION target=$TARGET"

# FPMake itself is ordinary Pascal code using the installed fpmkunit package.
FPMake="$BIN/fpmake"
timeout 120s "$FPC_BIN" -Mobjfpc \
  -FU"$BOOTSTRAP_UNITS" -FE"$BIN" "-o$FPMake" \
  "$ROOT/packages/fpmake.pp"

# Run from the repository root: package directories in fpmake.pp are root-relative.
(
  cd "$ROOT"
  FPC="$FPC_BIN" timeout 180s "$FPMake" compile
)

SOURCE_UNITS="$BUILD/units/wsm-source/$TARGET"
DOMAIN_UNITS="$BUILD/units/wsm-domain/$TARGET"
test -n "$(find "$SOURCE_UNITS" -maxdepth 1 -name 'wsm.source.ppu' -print -quit)"
test -n "$(find "$DOMAIN_UNITS" -maxdepth 1 -name 'wsm.domain.ppu' -print -quit)"

# This consumer sees only package output paths, never the donor src/ directory.
timeout 120s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$SOURCE_UNITS" -Fu"$DOMAIN_UNITS" \
  -FU"$TEST_UNITS" -FE"$BIN" \
  -otest-fpc-packages "$ROOT/packages/tests/test_fpc_packages.pas"

timeout 30s "$BIN/test-fpc-packages"
