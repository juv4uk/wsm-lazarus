#!/usr/bin/env bash
# G6.210 — D6:001110 «подвійне додавання» через одноразовий
# перевірений контекст (восьма хвиля).
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'VDA-БЛОК: немає fpc' >&2; exit 127; }
mkdir -p build/vda-units build/vda-bin
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$ROOT/build/vda-units" \
  -FE"$ROOT/build/vda-bin" -otest-verifiedd6doubleadd \
  "$ROOT/scripts/test-verifiedd6doubleadd.pas" >/dev/null
"$ROOT/build/vda-bin/test-verifiedd6doubleadd" "$ROOT/external/sens" "$@"
