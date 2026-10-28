#!/usr/bin/env bash
# G2.18 — реальна FPC перевірка незмінного pinned D1–D10 індексу.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
command -v fpc >/dev/null || { echo 'ПОМИЛКА: Free Pascal відсутній' >&2; exit 127; }
OUT="$ROOT/build/bindindex-atomic"
mkdir -p "$OUT/units" "$OUT/bin"
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$OUT/units" -FE"$OUT/bin" \
  -otest-bindindex-atomic scripts/test-bindindex.pas
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
"$OUT/bin/test-bindindex-atomic" 2>&1 | tee "$LOG"
grep -Fq 'BINDINDEX-ATOMIC-OK' "$LOG"
# Не ігнорувати реальний managed heap leak через зелену exit code.
if grep -Eq '[1-9][0-9]* unfreed memory blocks' "$LOG"; then
  echo 'ПОМИЛКА: невивільнені FPC блоки після побудови індексу' >&2
  exit 1
fi
echo 'ІНДЕКС-УК-ГАРАЗД: D1–D10 pinned, відмова атомарна, FPC heaptrc перевірено'
