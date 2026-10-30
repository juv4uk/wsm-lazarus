#!/usr/bin/env bash
# G6.203 — дешевий checked FPC тест SIR1 без другого важкого toolchain.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FPC_BIN="${FPC:-fpc}"
command -v "$FPC_BIN" >/dev/null || {
  echo 'SIR1-АТОМАРНІСТЬ-БЛОК: Free Pascal відсутній' >&2
  exit 127
}
mkdir -p build/m0.2/sir1-inspect-units build/m0.2/bin
timeout 120s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/sir1-inspect-units" \
  -FE"$ROOT/build/m0.2/bin" -otest-sir1-inspect-atomic \
  "$ROOT/scripts/test-sir1-inspect-atomic.pas"
timeout 20s "$ROOT/build/m0.2/bin/test-sir1-inspect-atomic"
