#!/usr/bin/env bash
# G5.63. Справжній FPC і pinned Contract 12; host-рамка не є SENS законом.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'ФІЗИЧНИЙ-СЕАНС-МЕЖІ-БЛОК: немає FPC' >&2; exit 127; }
mkdir -p build/m0.2/fizseans-mezhi-units build/m0.2/fizseans-mezhi-bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/fizseans-mezhi-units" \
  -FE"$ROOT/build/m0.2/fizseans-mezhi-bin" -osensfizseans \
  "$ROOT/src/sensfizseans.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/fizseans-mezhi-units" \
  -FE"$ROOT/build/m0.2/fizseans-mezhi-bin" -osenst5m \
  "$ROOT/src/senst5m.lpr"
python3 "$ROOT/scripts/test-fizseans-mezhi.py" \
  "$ROOT/build/m0.2/fizseans-mezhi-bin/sensfizseans" \
  "$ROOT/build/m0.2/fizseans-mezhi-bin/senst5m"
