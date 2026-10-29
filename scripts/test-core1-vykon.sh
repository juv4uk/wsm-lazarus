#!/usr/bin/env bash
# Core1.3: механізм виконання фізичного pinned Core1 через спільний D4.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for bin in fpc python3 git timeout; do
 command -v "$bin" >/dev/null || { echo "CORE1-БЛОК: бракує $bin" >&2; exit 127; }
done
./scripts/check-pin.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
test -x sens-oracle/target/debug/sens || { echo "CORE1-БЛОК: бракує oracle" >&2; exit 127; }
# Sparse upstream PR #475 не перетинаємо; файл беремо з незмінного git blob.
if [[ ! -s external/sens/lib/core1.sens ]]; then
 mkdir -p external/sens/lib
 timeout 90s git -C external/sens show HEAD:lib/core1.sens > external/sens/lib/core1.sens
fi
timeout 180s bash scripts/test-core4runtime.sh >/dev/null
mkdir -p build/m0.2/core1-vykon-units build/m0.2/core1-vykon-bin
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
 -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/core1-vykon-units" \
 -FE"$ROOT/build/m0.2/core1-vykon-bin" -osenscore1vykon \
 "$ROOT/src/senscore1vykon.lpr"
timeout 240s python3 -B scripts/test-core1-vykon.py \
 "$ROOT/build/m0.2/core1-vykon-bin/senscore1vykon" \
 "$ROOT/sens-oracle/target/debug/sens" "$ROOT"
