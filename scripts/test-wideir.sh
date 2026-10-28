#!/usr/bin/env bash
# Справжня компіляція FPC і фізичні слова саме pinned кореневого SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
command -v git >/dev/null
command -v fpc >/dev/null
PIN=$(git -C external/sens rev-parse HEAD)
GITLINK=$(git ls-tree HEAD external/sens | awk '{print $3}')
test "$PIN" = "$GITLINK"
mkdir -p build/m0.2/wideir/bin build/m0.2/wideir/units
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/wideir/units" -FE"$ROOT/build/m0.2/wideir/bin" \
  -otest-wideir "$ROOT/scripts/test-wideir.pas"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
timeout 70s git -C external/sens cat-file -e "$PIN:tests/semantic/d5-d12-numberp-law.sens"
timeout 70s git -C external/sens show "$PIN:tests/semantic/d5-d12-numberp-law.sens" > "$TMP/pinned.sens"
test -s "$TMP/pinned.sens"
"$ROOT/build/m0.2/wideir/bin/test-wideir" "$TMP/pinned.sens"
