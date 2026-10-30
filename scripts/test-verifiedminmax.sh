#!/usr/bin/env bash
# G6.209 — D6:110101 «найменше» / D6:110111 «найбільше» через
# одноразовий перевірений контекст (сьома хвиля).
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'VMM-БЛОК: немає fpc' >&2; exit 127; }
mkdir -p build/vmm-units build/vmm-bin
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$ROOT/build/vmm-units" \
  -FE"$ROOT/build/vmm-bin" -otest-verifiedminmax \
  "$ROOT/scripts/test-verifiedminmax.pas" >/dev/null
"$ROOT/build/vmm-bin/test-verifiedminmax" "$ROOT/external/sens" "$@"
