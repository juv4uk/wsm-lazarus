#!/usr/bin/env bash
# Active Lazarus gate: SENS exact-domain mechanism, without legacy SID8 authority.
# This is NOT a claim of full Core4 execution parity; the evaluator is being migrated.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
BUILD_DIR="$ROOT/build/m0.2"
UNIT_DIR="$BUILD_DIR/test-units"
BIN_DIR="$BUILD_DIR/bin"

"$ROOT/scripts/check-pin.sh"
"$ROOT/scripts/check-no-lcl.sh"

if ! command -v "$FPC_BIN" >/dev/null 2>&1; then
  echo "DOMAIN-FAIL missing Free Pascal compiler: $FPC_BIN" >&2
  exit 127
fi

# Fail closed if deprecated SID8 implementation becomes reachable from the new domain unit.
if grep -nE 'TSid8|wsm\.historical|wsm\.registry|SID8' "$ROOT/src/wsm.domain.pas"; then
  echo "DOMAIN-FAIL legacy identity dependency" >&2
  exit 1
fi

"$ROOT/scripts/build.sh"
mkdir -p "$UNIT_DIR" "$BIN_DIR"
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" \
  -FE"$BIN_DIR" -otest-domain "$ROOT/scripts/test-domain.pas"
(cd "$ROOT" && "$BIN_DIR/test-domain")
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" -otest-bind "$ROOT/scripts/test-bind.pas"
(cd "$ROOT" && "$BIN_DIR/test-bind")
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" -otest-bindindex "$ROOT/scripts/test-bindindex.pas"
(cd "$ROOT" && "$BIN_DIR/test-bindindex")
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" -otest-bindtree "$ROOT/scripts/test-bindtree.pas"
(cd "$ROOT" && "$BIN_DIR/test-bindtree")
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" -otest-bindatoms "$ROOT/scripts/test-bindatoms.pas"
(cd "$ROOT" && "$BIN_DIR/test-bindatoms")
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" -otest-binarybind "$ROOT/scripts/test-binarybind.pas"
(cd "$ROOT" && "$BIN_DIR/test-binarybind")
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" -otest-binarylocbind "$ROOT/scripts/test-binarylocbind.pas"
(cd "$ROOT" && "$BIN_DIR/test-binarylocbind")
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" -otest-binarytree "$ROOT/scripts/test-binarytree.pas"
(cd "$ROOT" && "$BIN_DIR/test-binarytree")
"$ROOT/scripts/test-bind-cli.sh"
"$ROOT/scripts/test-compiler.sh"
# Один наявний FPC PR-gate: включає 60+20 механічних перевірок
# native evaluator, без додаткового workflow/apt/важких мов.
timeout 180s bash "$ROOT/scripts/test-nativeeval.sh"
echo "LAZARUS-DOMAIN-GATE-OK scope=exact-domain-and-headless-build core4-execution=not-yet-verified"
