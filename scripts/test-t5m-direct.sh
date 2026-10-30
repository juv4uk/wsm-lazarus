#!/usr/bin/env bash
# G1.20 — справжній FPC, точний pinned T5M, алокація без проміжних тритів.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'T5M-ПРЯМИЙ-БЛОКЕР: Free Pascal відсутній' >&2
  exit 127
}
./scripts/check-pin.sh
mkdir -p build/m0.2/t5m-direct-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/t5m-direct-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-t5m-direct "$ROOT/scripts/test-t5m-direct.pas"
"$ROOT/build/m0.2/bin/test-t5m-direct"
# Старий fixed-vector pinned upstream test НЕ змінюємо і не вимикаємо.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/t5m-direct-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-t5m "$ROOT/scripts/test-t5m.pas"
"$ROOT/build/m0.2/bin/test-t5m"
echo 'T5M-ПРЯМИЙ-CI-ГАРАЗД FPC=справжній pinned=codec 4MiB=допущено'
