#!/usr/bin/env bash
# Реальний FPC, незмінний pinned Contract 12 та фізичні T5M-кадри.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'ФІЗИЧНИЙ-СЕАНС-БЛОК: немає FPC' >&2; exit 127; }
mkdir -p build/m0.2/fizseans-units build/m0.2/fizseans-bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/fizseans-units" \
  -FE"$ROOT/build/m0.2/fizseans-bin" -osensfizseans \
  "$ROOT/src/sensfizseans.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/fizseans-units" \
  -FE"$ROOT/build/m0.2/fizseans-bin" -osenst5m \
  "$ROOT/src/senst5m.lpr"
python3 "$ROOT/scripts/test-fizseans.py" \
  "$ROOT/build/m0.2/fizseans-bin/sensfizseans" \
  "$ROOT/build/m0.2/fizseans-bin/senst5m"
