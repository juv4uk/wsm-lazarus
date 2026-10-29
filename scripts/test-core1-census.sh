#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

./scripts/check-pin.sh
test -s external/sens/lib/core1.sens
test "$(git -C external/sens rev-parse HEAD)" = \
  "$(sed -nE 's/^MY_LISP_PIN=([0-9a-f]{40})$/\1/p' refs/tier1-baseline.properties)"

UNITS="$ROOT/build/m0.2/core1-census-units"
BIN="$ROOT/build/m0.2/core1-census-bin"
mkdir -p "$UNITS" "$BIN"
timeout 240s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$UNITS" -FE"$BIN" -otest-core1-census \
  "$ROOT/scripts/test-core1-census.pas"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
set +e
timeout 120s "$BIN/test-core1-census" "$ROOT" >"$TMP/census.out" 2>"$TMP/census.err"
STATUS=$?
set -e
if [[ "$STATUS" -ne 0 ]]; then
  cat "$TMP/census.out" "$TMP/census.err" >&2
  echo "CORE1-CENSUS-БЛОК: програма завершилася з кодом $STATUS" >&2
  exit 1
fi
test "$(grep -c '^CORE1-CENSUS-НЕДОПУЩЕНО D7=' "$TMP/census.out")" -eq 4
grep -Fq 'CORE1-CENSUS-ГАРАЗД total=96 admitted=92 rejected=4' "$TMP/census.out"
grep -Fq '0 unfreed memory blocks' "$TMP/census.err"

# Missing authority must fail closed without publishing a partial census.
mkdir -p "$TMP/missing-root"
set +e
timeout 60s "$BIN/test-core1-census" "$TMP/missing-root" \
  >"$TMP/negative.out" 2>"$TMP/negative.err"
NEGATIVE_STATUS=$?
set -e
test "$NEGATIVE_STATUS" -ne 0
test ! -s "$TMP/negative.out"
grep -Fq 'CORE1-CENSUS-ПРОВАЛ:' "$TMP/negative.err"
grep -Fq '0 unfreed memory blocks' "$TMP/negative.err"
cat "$TMP/census.out"
echo 'CORE1-CENSUS-ТЕСТ-ГАРАЗД exact-D7=так T5M-round-trip=так rejection=fail-closed heaptrc=0'
