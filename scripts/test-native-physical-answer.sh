#!/usr/bin/env bash
# G3.13: канонічні фізичні результати вже виконаного D3.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
bash ./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'ФІЗИЧНА-ВІДПОВІДЬ-БЛОК: немає FPC' >&2; exit 127; }
mkdir -p build/native-physical-answer/units build/native-physical-answer/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/native-physical-answer/units" \
  -FE"$ROOT/build/native-physical-answer/bin" \
  -otest-native-physical-answer "$ROOT/scripts/test-native-physical-answer.pas"
"$ROOT/build/native-physical-answer/bin/test-native-physical-answer"
