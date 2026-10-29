#!/usr/bin/env bash
# G5.63: тільки чинна FPC 3.2.x збірка та фізичний незалежний T5M.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'ФІЗИЧНИЙ-ФАЙЛ-БЛОКЕР: немає Free Pascal' >&2
  exit 127
}
mkdir -p build/m0.2/fizfayl-units build/m0.2/fizfayl-bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/fizfayl-units" \
  -FE"$ROOT/build/m0.2/fizfayl-bin" -osensfizfayl \
  "$ROOT/src/sensfizfayl.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/fizfayl-units" \
  -FE"$ROOT/build/m0.2/fizfayl-bin" -osenst5m \
  "$ROOT/src/senst5m.lpr"
python3 "$ROOT/scripts/test-fizfayl.py" \
  "$ROOT/build/m0.2/fizfayl-bin/sensfizfayl" \
  "$ROOT/build/m0.2/fizfayl-bin/senst5m"
