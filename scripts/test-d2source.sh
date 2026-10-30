#!/usr/bin/env bash
# G1.3: actual Free Pascal binary D2 structural AST after pinned T5M codec.
# No SENS language law, runtime, Core4 execution, or fake REPL oracle here.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null 2>&1 || {
  echo "D2SOURCE-BLOCKED missing FPC toolchain" >&2
  exit 127
}
./scripts/check-pin.sh
mkdir -p build/m0.2/d2-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/d2-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-d2source "$ROOT/scripts/test-d2source.pas"
./build/m0.2/bin/test-d2source

# G1.4: standalone physical T5M viewer/packer CLI (no SENS evaluator).
bash "$ROOT/scripts/test-t5m-cli.sh"
