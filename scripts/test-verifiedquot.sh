#!/usr/bin/env bash
# G6.201 — один verified WideIR → реальний x86-64 CQO/IDIV, без Rust/Zig.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'VQ-БЛОК: немає fpc' >&2; exit 127; }
test -f "$ROOT/external/sens/contracts/language-contract-12.lisp" || {
  echo 'VQ-БЛОК: немає pinned Contract 12.0' >&2; exit 66;
}
mkdir -p build/vq-units build/vq-bin
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/vq-units" -FE"$ROOT/build/vq-bin" \
  -otest-verifiedquot "$ROOT/scripts/test-verifiedquot.pas"
timeout 240s "$ROOT/build/vq-bin/test-verifiedquot" "$ROOT/external/sens"
