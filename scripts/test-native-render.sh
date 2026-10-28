#!/usr/bin/env bash
# G3.12: FPC з range/overflow/checks та реальний heaptrc.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null 2>&1 || { echo 'ВИВІД-БЛОК: FPC не знайдено' >&2; exit 127; }
mkdir -p build/native-render/units build/native-render/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/native-render/units" -FE"$ROOT/build/native-render/bin" \
  -otest-native-render "$ROOT/scripts/test-native-render.pas"
./build/native-render/bin/test-native-render
