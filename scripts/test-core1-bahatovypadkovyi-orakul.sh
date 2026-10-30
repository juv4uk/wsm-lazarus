#!/usr/bin/env bash
# G3.47 — фізичне pinned Core1 DEFINE, 16 справжніх upstream викликів.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
for app in fpc git python3 timeout cmp; do
  command -v "$app" >/dev/null || {
    echo "CORE1-ОРАКУЛ-БЛОК: немає $app" >&2; exit 127;
  }
done
./scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
cmp external/sens/lib/core1.sens sens-oracle/lib/core1.sens
cmp external/sens/lib/core1.lisp sens-oracle/lib/core1.lisp
test -x sens-oracle/target/debug/sens || {
  echo "CORE1-ОРАКУЛ-БЛОК: не зібрано незалежний SENS" >&2; exit 127;
}
# Без послаблення чинних Core1 механізмів/негативів.
timeout 240s bash scripts/test-core1-vykon.sh
mkdir -p build/m0.2/core1-orakul-units build/m0.2/core1-orakul-bin
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/core1-orakul-units" \
  -FE"$ROOT/build/m0.2/core1-orakul-bin" \
  -osenst5m "$ROOT/src/senst5m.lpr"
timeout 240s python3 -B scripts/test-core1-bahatovypadkovyi-orakul.py \
  "$ROOT/build/m0.2/core1-vykon-bin/senscore1vykon" \
  "$ROOT/build/m0.2/core1-orakul-bin/senst5m" \
  "$ROOT/sens-oracle/target/debug/sens" "$ROOT"
