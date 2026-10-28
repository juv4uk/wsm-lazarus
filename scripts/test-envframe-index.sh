#!/usr/bin/env bash
# G3.11: реальна перевірка геометричного host-сховища точних ключів FPC.
# Це тільки host-механізм, не semantic parity SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'ENVFRAME-INDEX-БЛОКЕР: потрібен Free Pascal' >&2
  exit 127
}
mkdir -p build/m0.2/envframe-index-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/envframe-index-units" \
  -FE"$ROOT/build/m0.2/bin" -otest-envframe-index \
  "$ROOT/scripts/test-envframe.pas"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
"$ROOT/build/m0.2/bin/test-envframe-index" >"$TMP/stdout" 2>"$TMP/stderr"
grep -F 'ENVFRAME-INDEX-OK' "$TMP/stdout"
grep -F 'ENVFRAME-OK' "$TMP/stdout"
grep -F '0 unfreed memory blocks' "$TMP/stderr"
echo 'ENVFRAME-INDEX-CI-ГАРАЗД FPC=реальний ключів=2046 витоки=0'
