#!/usr/bin/env bash
# G5.64 — справжній FPC / pinned SENS на ТОЧНИХ фізичних T5M коренях.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
for tool in fpc git python3 timeout; do
  command -v "$tool" >/dev/null || {
    echo "ФАЙЛОВИЙ-ОРAКУЛ-БЛОК: немає $tool" >&2
    exit 127
  }
done
./scripts/check-pin.sh
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN" || {
  echo "ФАЙЛОВИЙ-ОРАКУЛ-БЛОК: порушено pinned SENS SHA" >&2
  exit 1
}
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || {
  echo "ФАЙЛОВИЙ-ОРАКУЛ-БЛОК: upstream SENS не зібрано" >&2
  exit 127
}
# Усі існуючі справжні фізичні позитиви та негативи зберігаються.
timeout 200s bash scripts/test-fizfayl.sh
timeout 240s python3 -B scripts/test-fizfayl-oracle.py \
  "$ROOT/build/m0.2/fizfayl-bin/sensfizfayl" \
  "$ROOT/build/m0.2/fizfayl-bin/senst5m" "$ORACLE"
