#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build/m0.2"
mkdir -p "$BUILD/units" "$BUILD/bin"
fpc -B -Mobjfpc -Fu"$ROOT/src" -FU"$BUILD/units" -FE"$BUILD/bin" -osensc "$ROOT/src/sensc.lpr"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
"$BUILD/bin/sensc" --compile-ir "$ROOT/external/sens/lib/core4.lisp" "$tmp/one.sir"
"$BUILD/bin/sensc" --compile-ir "$ROOT/external/sens/lib/core4.lisp" "$tmp/two.sir"
cmp "$tmp/one.sir" "$tmp/two.sir"
printf '(незакрите' > "$tmp/bad.lisp"
if "$BUILD/bin/sensc" --compile-ir "$tmp/bad.lisp" "$tmp/bad.sir"; then
  echo 'SENSC-FAIL malformed source accepted' >&2
  exit 1
fi
test ! -e "$tmp/bad.sir"
echo 'SENSC-IR-TEST-OK deterministic=1 malformed=reject'
# G7.1: independent heap-mechanism test; does not confer SENS law authority.
bash "$ROOT/scripts/test-gc.sh"
