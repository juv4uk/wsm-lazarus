#!/usr/bin/env bash
# Core1.2 — механічний GC-зріз, а не SENS evaluator.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null || exit 127
command -v timeout >/dev/null
OUT="$ROOT/build/m0.2/core1gcbridge"
mkdir -p "$OUT/units" "$OUT/bin"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$OUT/units" -FE"$OUT/bin" -otest-core1gcbridge \
  "$ROOT/scripts/test-core1gcbridge.pas"
timeout 30s "$OUT/bin/test-core1gcbridge"
# Існуючі незалежні механічні GC/envframe регресії зберегти.
timeout 90s bash "$ROOT/scripts/test-gc.sh"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$OUT/units" -FE"$OUT/bin" -otest-envframe \
  "$ROOT/scripts/test-envframe.pas"
timeout 30s "$OUT/bin/test-envframe"
echo 'CORE1-GC-РЕГРЕСІЇ-ГАРАЗД native-FPC=так'
