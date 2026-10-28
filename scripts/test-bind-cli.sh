#!/usr/bin/env bash
# G2.4: structural head-inventory CLI, never semantic callability.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
BUILD_DIR="$ROOT/build/m0.2"
UNIT_DIR="$BUILD_DIR/test-units"
BIN_DIR="$BUILD_DIR/bin"
mkdir -p "$UNIT_DIR" "$BIN_DIR"
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" \
  -osensbind "$ROOT/src/sensbind.lpr"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '(сполучити (як-є ()))\n(за-умовою так)\n' > "$TMP/known.lisp"
"$BIN_DIR/sensbind" --require-bound "$TMP/known.lisp" "$ROOT/external/sens" > "$TMP/known.out"
grep -F 'SENSBIND-HEAD state=bound byte=2 line=1 byte-column=2 domain=3 bits=111' "$TMP/known.out"
grep -F 'SENSBIND-SUMMARY heads=3 bound=3 unknown=0 nonatom=0 callable=unverified' "$TMP/known.out"
"$BIN_DIR/sensbind" --require-bound "$TMP/known.lisp" "$ROOT/external/sens" > "$TMP/repeat.out"
cmp "$TMP/known.out" "$TMP/repeat.out"

printf '(невідоме так)\n' > "$TMP/unknown.lisp"
"$BIN_DIR/sensbind" --analyze "$TMP/unknown.lisp" "$ROOT/external/sens" > "$TMP/unknown.out"
grep -F 'SENSBIND-SUMMARY heads=1 bound=0 unknown=1 nonatom=0 callable=unverified' "$TMP/unknown.out"
if "$BIN_DIR/sensbind" --require-bound "$TMP/unknown.lisp" "$ROOT/external/sens" > "$TMP/strict.out" 2>&1; then
  echo 'BINDCLI-FAIL unknown head accepted by strict mode' >&2
  exit 1
fi
grep -F 'SENSBIND-FAIL head byte=2 line=1 byte-column=2' "$TMP/strict.out"

printf '((так))\n' > "$TMP/nonatom.lisp"
"$BIN_DIR/sensbind" --analyze "$TMP/nonatom.lisp" "$ROOT/external/sens" > "$TMP/nonatom.out"
grep -F 'SENSBIND-SUMMARY heads=2 bound=1 unknown=0 nonatom=1 callable=unverified' "$TMP/nonatom.out"
if "$BIN_DIR/sensbind" --require-bound "$TMP/nonatom.lisp" "$ROOT/external/sens" >/dev/null 2>&1; then
  echo 'BINDCLI-FAIL nonatom head accepted by strict mode' >&2
  exit 1
fi
printf '(сполучити' > "$TMP/malformed.lisp"
if "$BIN_DIR/sensbind" --analyze "$TMP/malformed.lisp" "$ROOT/external/sens" >/dev/null 2>&1; then
  echo 'BINDCLI-FAIL malformed source accepted' >&2
  exit 1
fi
if "$BIN_DIR/sensbind" --analyze "$TMP/known.lisp" "$ROOT/external/absent" >/dev/null 2>&1; then
  echo 'BINDCLI-FAIL unpinned source accepted' >&2
  exit 1
fi
if "$BIN_DIR/sensbind" --analyze "$TMP/known.sens" "$ROOT/external/sens" >/dev/null 2>&1; then
  echo 'BINDCLI-FAIL binary .sens routed through .lisp reader' >&2
  exit 1
fi

"$BIN_DIR/sensbind" --analyze "$ROOT/external/sens/lib/core4.lisp" "$ROOT/external/sens" > "$TMP/core4.out"
grep -F 'callable=unverified' "$TMP/core4.out" | grep -F 'SENSBIND-SUMMARY'
echo 'BINDCLI-OK positional=1 exact-domains=1 deterministic=1 strict=reject core4=parse-only'
