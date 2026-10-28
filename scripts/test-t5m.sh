#!/usr/bin/env bash
# G1 physical-only T5M proof. No semantics or SENS evaluator substitution.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FPC_BIN="${FPC:-fpc}"
if ! command -v "$FPC_BIN" >/dev/null 2>&1; then
  echo "T5M-FAIL Free Pascal compiler absent" >&2
  exit 127
fi
mkdir -p "$ROOT/build/m0.2/test-units" "$ROOT/build/m0.2/bin"
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/test-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-t5m "$ROOT/scripts/test-t5m.pas"
(cd "$ROOT" && "$ROOT/build/m0.2/bin/test-t5m")
