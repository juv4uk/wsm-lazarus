#!/usr/bin/env bash
# G3.2: фактичні D3-форми, без обіцянки повного runtime або Core4.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC_BIN=${FPC:-fpc}
mkdir -p "$ROOT/build/m0.2/nativeeval-units" "$ROOT/build/m0.2/bin"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/nativeeval-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-nativeeval "$ROOT/scripts/test-nativeeval.pas"
(cd "$ROOT" && build/m0.2/bin/test-nativeeval external/sens)
# Новий FPC свідок користується тією самою pinned authority та unit cache,
# не створюючи ще один workflow / apt install на кожен PR.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/nativeeval-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-nativeeval-appq-boundary "$ROOT/scripts/test-nativeeval-appq-boundary.pas"
(cd "$ROOT" && build/m0.2/bin/test-nativeeval-appq-boundary)

# Існуючий FPC PR-gate: обчислення створеного D10 замикання і лексичного
# значення; не підмінювати цим повне Core1 або незалежний SENS oracle.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/nativeeval-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-nativeeval-computed-closure "$ROOT/scripts/test-nativeeval-computed-closure.pas"
(cd "$ROOT" && build/m0.2/bin/test-nativeeval-computed-closure)

# G3.867: точний D5:00100, відмови неповного LABEL/помилкового тіла,
# чужого width/bits і пошкодженого T5M у цьому самому checked FPC PR job.
# 1) Чому binder не надає callability? 2) Хто керує lifetime Engine?
# 3) Чому неповна мітка не означає відсутність підтримки LABEL?
# 4) Чому незалежний SENS oracle тут не заявлено?
timeout 180s bash "$ROOT/scripts/test-nativeeval-label-boundaries.sh"

# G3 lexical capture: той самий FPC runner і pinned authority,
# без нового workflow/apt та без нового runtime у GUI.
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/nativeeval-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-nativeeval-lexical-capture "$ROOT/scripts/test-nativeeval-lexical-capture.pas"
(cd "$ROOT" && build/m0.2/bin/test-nativeeval-lexical-capture)
