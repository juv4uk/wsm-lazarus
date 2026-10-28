#!/usr/bin/env bash
# G4.1 standalone pinned-source admission; no Core4 semantic execution.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null 2>&1 || {
  echo 'CORE4-SOURCE-BLOCKED fpc missing' >&2
  exit 127
}
./scripts/check-pin.sh
mkdir -p build/m0.2/core4-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/core4-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-core4source "$ROOT/scripts/test-core4source.pas"
"$ROOT/build/m0.2/bin/test-core4source"
