#!/usr/bin/env bash
# G7.9 — фізична межа WSMIMG1, справжній FPC, перевірені exact host keys.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'ОБРАЗ-ЗРОСТАННЯ-БЛОКЕР: Free Pascal недоступний' >&2; exit 127; }
./scripts/check-pin.sh
mkdir -p build/m0.2/image-growth-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/image-growth-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-image-growth "$ROOT/scripts/test-image-growth.pas"
"$ROOT/build/m0.2/bin/test-image-growth"
# Попередній G7.4 read/write та негативи не послаблено.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/image-growth-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-image "$ROOT/scripts/test-image.pas"
"$ROOT/build/m0.2/bin/test-image"
echo 'ОБРАЗ-ЗРОСТАННЯ-CI-ГАРАЗД FPC=реальний Lazarus=спільний-профільний'
