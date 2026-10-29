#!/usr/bin/env bash
# G6.93 — нативний рекурсивний fib: збірка ELF із точного D24 `.sens`
# і звірка виходу з незалежним оракулом. Плюс негативні випадки.
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/u" "$WORK/b"

./scripts/check-pin.sh > /dev/null

fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" -FU"$WORK/u" -FE"$WORK/b" \
  -otest-elffib "$ROOT/scripts/test-elffib.pas" > "$WORK/build.log" 2>&1 || {
    echo "ELFFIB-ЗБІЙ збірка"
    cat "$WORK/build.log"
    exit 1
  }

"$WORK/b/test-elffib"
