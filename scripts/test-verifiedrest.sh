#!/usr/bin/env bash
# G6.206 — D6:010100 «остача» через одноразовий перевірений контекст (шоста хвиля).
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'VR-БЛОК: немає fpc' >&2; exit 127; }
mkdir -p build/vr-units build/vr-bin
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$ROOT/build/vr-units" \
  -FE"$ROOT/build/vr-bin" -otest-verifiedrest \
  "$ROOT/scripts/test-verifiedrest.pas" >/dev/null
"$ROOT/build/vr-bin/test-verifiedrest" "$ROOT/external/sens" "$@"
