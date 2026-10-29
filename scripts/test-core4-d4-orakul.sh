#!/usr/bin/env bash
# G4.49: два незалежні механізми на тих самих canonical T5M байтах.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
for dep in git fpc python3 timeout; do
  command -v "$dep" >/dev/null || {
    echo "CORE4-Д4-БЛОК: немає $dep" >&2
    exit 127
  }
done
./scripts/check-pin.sh
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN" || {
  echo 'CORE4-Д4-БЛОК: незалежний SENS має неправильний SHA' >&2
  exit 2
}
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || {
  echo 'CORE4-Д4-БЛОК: немає справжнього upstream SENS CLI' >&2
  exit 127
}
UNITS="$ROOT/build/m0.2/core4-d4-orakul-units"
BIN="$ROOT/build/m0.2/core4-d4-orakul-bin"
mkdir -p "$UNITS" "$BIN"
# Справжній checked FPC, не компіляція лише синтаксису.
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" -osenst5m \
  "$ROOT/src/senst5m.lpr"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" -osenscore4vykon \
  "$ROOT/src/senscore4vykon.lpr"
timeout 400s python3 -B scripts/test-core4-d4-orakul.py \
  "$ROOT" "$BIN/senscore4vykon" "$BIN/senst5m" "$ORACLE"
