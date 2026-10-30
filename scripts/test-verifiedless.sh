#!/usr/bin/env bash
# G6.191 — D5:11010 через одноразовий перевірений контекст (третя хвиля).
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'VL-БЛОК: немає fpc' >&2; exit 127; }
mkdir -p build/vl-units build/vl-bin
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$ROOT/build/vl-units" \
  -FE"$ROOT/build/vl-bin" -otest-verifiedless \
  "$ROOT/scripts/test-verifiedless.pas" >/dev/null
"$ROOT/build/vl-bin/test-verifiedless" "$ROOT/external/sens"
