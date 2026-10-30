#!/usr/bin/env bash
# G6.200 — D5:10111 «частка» через одноразовий перевірений контекст (п'ята хвиля).
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'VQ-БЛОК: немає fpc' >&2; exit 127; }
mkdir -p build/vq-units build/vq-bin
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$ROOT/build/vq-units" \
  -FE"$ROOT/build/vq-bin" -otest-verifiedquot \
  "$ROOT/scripts/test-verifiedquot.pas" >/dev/null
"$ROOT/build/vq-bin/test-verifiedquot" "$ROOT/external/sens" "$@"
