#!/usr/bin/env bash
# Механічна перевірка двійково-первинного IR, не SENS-оракул.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'ТОЧНЕ-IR-БЛОК: Free Pascal не встановлено' >&2; exit 127; }
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
mkdir -p build/m0.2/exactir-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/exactir-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-exactir "$ROOT/scripts/test-exactir.pas"
"$ROOT/build/m0.2/bin/test-exactir"
