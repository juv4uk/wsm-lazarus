#!/usr/bin/env bash
# #891 — checked Free Pascal + headless Core1. PTY/UTF-8 екран — окремо.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
timeout 90s bash scripts/check-pin.sh
FPC="${FPC:-fpc}"
command -v "$FPC" >/dev/null || { echo 'FREEVISION-BLOCK fpc відсутній' >&2; exit 127; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/units" "$WORK/bin"
timeout 180s "$FPC" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$WORK/units" -FE"$WORK/bin" \
  -osenscore1repl "$ROOT/src/senscore1repl.lpr"
timeout 180s "$FPC" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/tui" -FU"$WORK/units" -FE"$WORK/bin" \
  -osensfv "$ROOT/tui/sensfv.lpr"
timeout 90s "$WORK/bin/sensfv" --selftest "$WORK/bin/senscore1repl" "$ROOT"
echo 'FREEVISION-BUILD-OK compiler=FPC fv=linked interactive-pty=NOT_VERIFIED'
