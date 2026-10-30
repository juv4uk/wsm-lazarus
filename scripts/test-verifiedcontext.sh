#!/usr/bin/env bash
# G6.180 — перевірений контекст: один прохід T5M→WideIR замість двох.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'VC-БЛОК: немає fpc' >&2; exit 127; }
./scripts/sync-authority.sh >/dev/null 2>&1 || true
mkdir -p build/vc-units build/vc-bin
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$ROOT/build/vc-units" \
  -FE"$ROOT/build/vc-bin" -otest-verifiedcontext \
  "$ROOT/scripts/test-verifiedcontext.pas" >/dev/null
"$ROOT/build/vc-bin/test-verifiedcontext" "$ROOT/external/sens"
