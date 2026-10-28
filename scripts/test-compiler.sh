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
"$BUILD/bin/sensc" --verify-ir "$tmp/one.sir"
"$BUILD/bin/sensc" --verify-ir "$tmp/two.sir"

# SIR1 fixtures are mechanical corruption tests, not SENS semantic laws.
printf 'SIR1\000\000\000\000\000' > "$tmp/empty-ok.sir"
"$BUILD/bin/sensc" --verify-ir "$tmp/empty-ok.sir"
printf 'BIR1\000\000\000\000\000' > "$tmp/bad-magic.sir"
printf 'SIR1' > "$tmp/missing-end.sir"
printf 'SIR1\007\000\000\000\000' > "$tmp/bad-opcode.sir"
printf 'SIR1\001\000\000\000\000\000\000\000\000\000' > "$tmp/unclosed.sir"
printf 'SIR1\002\000\000\000\000\000\000\000\000\000' > "$tmp/extra-close.sir"
printf 'SIR1\003\007\000\000\000ab' > "$tmp/truncated.sir"
printf 'SIR1\004\001\000\000\000x\000\000\000\000\000' > "$tmp/bad-string.sir"
printf 'SIR1\001\001\000\000\000x\000\000\000\000\000' > "$tmp/bad-struct.sir"
printf 'SIR1\000\001\000\000\000x' > "$tmp/bad-end.sir"
cp "$tmp/one.sir" "$tmp/trailing.sir"
printf 'x' >> "$tmp/trailing.sir"
for bad in bad-magic missing-end bad-opcode unclosed extra-close truncated bad-string bad-struct bad-end trailing; do
  if "$BUILD/bin/sensc" --verify-ir "$tmp/$bad.sir"; then
    echo "SENSC-FAIL corrupt SIR1 accepted: $bad" >&2
    exit 1
  fi
done
printf '(незакрите' > "$tmp/bad.lisp"
if "$BUILD/bin/sensc" --compile-ir "$tmp/bad.lisp" "$tmp/bad.sir"; then
  echo 'SENSC-FAIL malformed source accepted' >&2
  exit 1
fi
test ! -e "$tmp/bad.sir"
echo 'SENSC-IR-TEST-OK deterministic=1 malformed=reject verifier=12-cases'
