#!/usr/bin/env bash
# G5.3 host-private byte-framing regression, NOT a SENS REPL or language law.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC_BIN=${FPC:-fpc}
UNITS="$ROOT/build/m0.2/sessionwire-units"
BIN="$ROOT/build/m0.2/bin"
mkdir -p "$UNITS" "$BIN"
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" \
  -otest-sessionwire "$ROOT/scripts/test-sessionwire.pas"
(cd "$ROOT" && "$BIN/test-sessionwire")
# G5.4: справжнє обмежене виконання D3 через вже наявний оцінювач.
# Українська проєкція тільки для вводу, результат — точні двійкові слова.
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" \
  -otest-sessiond3 "$ROOT/scripts/test-sessiond3.pas"
(cd "$ROOT" && "$BIN/test-sessiond3")
