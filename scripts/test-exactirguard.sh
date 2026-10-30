#!/usr/bin/env bash
# G6.7 — інваріанти in-memory ExactIR, не парсер EIR1 і не SENS-oracle.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null || { echo 'СТОРОЖ-IR-ПОМИЛКА: немає Free Pascal' >&2; exit 127; }
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
mkdir -p build/m0.2/exactirguard-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/exactirguard-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-exactirguard "$ROOT/scripts/test-exactirguard.pas"
"$ROOT/build/m0.2/bin/test-exactirguard"
