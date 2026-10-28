#!/usr/bin/env bash
# Окрема реальна FPC перевірка фізичного цитування D3:001.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN="${FPC:-fpc}"
command -v "$FPC_BIN" >/dev/null || { echo 'ЦИТАТА-БЛОК: Free Pascal відсутній' >&2; exit 127; }
mkdir -p build/native-quote/units build/native-quote/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/native-quote/units" -FE"$ROOT/build/native-quote/bin" \
  -otest-native-quote "$ROOT/scripts/test-native-quote.pas"
./build/native-quote/bin/test-native-quote
