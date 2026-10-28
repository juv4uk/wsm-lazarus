#!/usr/bin/env bash
# Перевіряємо фізичний двійковий огляд незалежно від Lazarus GUI.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/build/lazarus/model-units" "$ROOT/build/lazarus/bin"
"${FPC:-fpc}" -B -Mobjfpc -Fu"$ROOT/gui" -Fu"$ROOT/src" \
  -FU"$ROOT/build/lazarus/model-units" -FE"$ROOT/build/lazarus/bin" \
  -otest-oglyadmodel "$ROOT/scripts/test-oglyadmodel.pas"
"$ROOT/build/lazarus/bin/test-oglyadmodel"
