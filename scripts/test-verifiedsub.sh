#!/usr/bin/env bash
# G6.192 — D5:01011 «відняти» через одноразовий перевірений контекст (четверта хвиля).
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'VS-БЛОК: немає fpc' >&2; exit 127; }
mkdir -p build/vs-units build/vs-bin
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$ROOT/build/vs-units" \
  -FE"$ROOT/build/vs-bin" -otest-verifiedsub \
  "$ROOT/scripts/test-verifiedsub.pas" >/dev/null
"$ROOT/build/vs-bin/test-verifiedsub" "$ROOT/external/sens" "$@"
