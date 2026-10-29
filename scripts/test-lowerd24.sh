#!/usr/bin/env bash
# G6.95 — перше справжнє зниження тіла SENS у машинний код.
# Оракул — обчислювач SENS (для тіл лише з параметрами) і пряма
# арифметика (для тіл із літералами, де обчислювач поки відмовляє).
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/u" "$WORK/b"
./scripts/check-pin.sh > /dev/null
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" -FU"$WORK/u" -FE"$WORK/b" \
  -otest-lowerd24 "$ROOT/scripts/test-lowerd24.pas" > "$WORK/build.log" 2>&1 || {
    echo "LOWER24-ЗБІЙ збірка"; cat "$WORK/build.log"; exit 1; }
"$WORK/b/test-lowerd24" "$ROOT"
