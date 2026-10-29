#!/usr/bin/env bash
# G5.63 — справжній FPC + незалежний pinned SENS на тих самих .sens.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
for tool in fpc git python3 timeout; do
  command -v "$tool" >/dev/null || {
    echo "СЕАНС-ОРАКУЛ-БЛОК: немає $tool" >&2
    exit 127
  }
done
./scripts/check-pin.sh
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN" || {
  echo 'СЕАНС-ОРАКУЛ-БЛОК: неправильний SHA SENS' >&2
  exit 1
}
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || {
  echo 'СЕАНС-ОРАКУЛ-БЛОК: немає зібраного upstream SENS' >&2
  exit 127
}
# Спочатку всі чинні механічні і негативні тести, без скорочень.
timeout 180s bash scripts/test-fizseans.sh
# Реальні checked FPC двійковий сеанс та пакувальник з попереднього gate.
timeout 240s python3 -B scripts/test-fizseans-oracle.py \
  "$ROOT/build/m0.2/fizseans-bin/sensfizseans" \
  "$ROOT/build/m0.2/fizseans-bin/senst5m" "$ORACLE"
