#!/usr/bin/env bash
# G5.65: FPC не дублює семантику pinned SENS; oracle CLI незалежний.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
for program in fpc git python3 timeout; do
  command -v "$program" >/dev/null || {
    echo "ФІЗИЧНИЙ-ФАЙЛ-ОРАКУЛ-БЛОК: немає $program" >&2
    exit 127
  }
done
./scripts/check-pin.sh
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN" || {
  echo 'ФІЗИЧНИЙ-ФАЙЛ-ОРАКУЛ-БЛОК: неправильний pin SENS' >&2
  exit 1
}
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || {
  echo 'ФІЗИЧНИЙ-ФАЙЛ-ОРАКУЛ-БЛОК: немає upstream SENS binary' >&2
  exit 127
}
# Зберігаємо всі чинні позитивні, негативні й адресні перевірки.
timeout 180s bash scripts/test-fizfayl.sh
timeout 240s python3 -B scripts/test-fizfayl-orakul.py \
  "$ROOT/build/m0.2/fizfayl-bin/sensfizfayl" \
  "$ROOT/build/m0.2/fizfayl-bin/senst5m" "$ORACLE"
