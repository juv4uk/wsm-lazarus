#!/usr/bin/env bash
# Самостійний фізичний тест: FPC має реально зібрати обидва API.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FPC_BIN="${FPC:-fpc}"
command -v "$FPC_BIN" >/dev/null || { echo 'ШИРОКИЙ-ПОТІК-БЛОК: FPC відсутній' >&2; exit 127; }
mkdir -p build/t5m-wide/units build/t5m-wide/bin
for specimen in test-t5madmission test-t5m-wide-stream; do
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$ROOT/build/t5m-wide/units" -FE"$ROOT/build/t5m-wide/bin" \
    -o"$specimen" "$ROOT/scripts/$specimen.pas"
  "$ROOT/build/t5m-wide/bin/$specimen"
done
