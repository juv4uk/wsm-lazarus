#!/usr/bin/env bash
# #867 — тільки фізичний FPC witness, жодного нового evaluator/dispatch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Перевірити реальний pinned gitlink/sparse authority до будь-якого виконання.
timeout 90s bash scripts/check-pin.sh

# Жоден локальний Pascal тест не визначає адреси самостійно:
# координата і проєкції повинні фізично існувати в pinned SENS.
grep -Eq '^[[:space:]]*\(00100 \(ук мітка\) \(укр мітка\)' \
  external/sens/lib/domains/d5.lisp || {
  echo 'МІТКА-ФІЗИЧНИЙ-ПРОВАЛ: pinned D5:00100 відсутній або змінений' >&2
  exit 1
}

FPC_BIN="${FPC:-fpc}"
command -v "$FPC_BIN" >/dev/null 2>&1 || {
  echo 'МІТКА-ФІЗИЧНИЙ-БЛОК: Free Pascal відсутній' >&2
  exit 127
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/units" "$WORK/bin"

# Справжня checked FPC збірка. Навмисно без залежності від Lazarus/LCL.
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$WORK/units" -FE"$WORK/bin" \
  -otest-nativeeval-label-boundaries \
  "$ROOT/scripts/test-nativeeval-label-boundaries.pas"

timeout 120s "$WORK/bin/test-nativeeval-label-boundaries"
echo 'МІТКА-ПЕРЕВІРКА-ЗАВЕРШЕНА fpc=checked authoritative=pinned'
