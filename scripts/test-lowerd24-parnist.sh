#!/usr/bin/env bash
# G6.150: реальний FPC→native x86-64 TEST/SETcc→D1 parity.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'D24-ПАРНІСТЬ-БЛОК: Linux x86-64' >&2;exit 127; }
for x in fpc git timeout mktemp readelf objdump dd cmp grep sha256sum; do
  command -v "$x" >/dev/null || { echo "немає $x" >&2;exit 127; }
done
TMP="$(mktemp -d)"
cleanup() {
  local rc=$? f
  if ((rc)); then
    echo "D24-ПАРНІСТЬ-RED код=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.err "$TMP"/*.output; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 25 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
timeout 120s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
for exact in '(010000 (ук парне?) (укр парне?)' \
             '(010001 (ук непарне?) (укр непарне?)'; do
  git -C external/sens show HEAD:lib/domains/d6.lisp |
    grep -Fq "$exact"
done
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ "${REQUIRE_SENS_ORACLE:-0}" == 1 && -z "$ORACLE" ]]; then
  echo 'D24-ПАРНІСТЬ-БЛОК: незалежний pinned SENS REPL обовʼязковий' >&2
  exit 127
fi
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
mkdir -p "$TMP"/{units,bin,fixtures,repeat}
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-lowerd24-parnist "$ROOT/scripts/test-lowerd24-parnist.pas" \
  >"$TMP/test.build" 2>&1 || {
    cat "$TMP/test.build" >&2;exit 1;
  }
test -x "$TMP/bin/test-lowerd24-parnist"
for target in fixtures repeat; do
  timeout 90s "$TMP/bin/test-lowerd24-parnist" "$ROOT" "$TMP/$target" \
    >"$TMP/$target.output" 2>"$TMP/$target.err"
  grep -Fxq 'G6.150-D24-PARITY-FIXTURES-OK physical=32 native=32 rejects=10' \
    "$TMP/$target.output"
  if grep -Fq 'unfreed memory blocks' "$TMP/$target.err"; then
    grep -Fq '0 unfreed memory blocks' "$TMP/$target.err"
  fi
done
cmp "$TMP/fixtures/cases.tsv" "$TMP/repeat/cases.tsv"
PASS=0;ORACLES=0
while IFS=$'\t' read -r tag expected projection; do
  test -n "$tag"
  file="$TMP/fixtures/$tag.elf"
  test -s "$file"
  cmp "$file" "$TMP/repeat/$tag.elf"
  cmp "$TMP/fixtures/$tag.sens" "$TMP/repeat/$tag.sens"
  readelf -h "$file" >"$TMP/$tag.header"
  grep -Eq 'Type:[[:space:]]+EXEC' "$TMP/$tag.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$tag.header"
  readelf -l "$file" >"$TMP/$tag.segments"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/$tag.segments"
  dd if="$file" of="$TMP/$tag.machine" bs=1 skip=120 status=none
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$tag.machine" >"$TMP/$tag.dis"
  grep -Eiq 'test[[:space:]]+al,0x1' "$TMP/$tag.dis"
  if [[ "$tag" == *-0-* ]]; then
    grep -Eiq 'sete[[:space:]]+al' "$TMP/$tag.dis"
  else
    grep -Eiq 'setne[[:space:]]+al' "$TMP/$tag.dis"
  fi
  grep -Eiq 'movzx[[:space:]]+eax,al' "$TMP/$tag.dis"
  chmod 500 "$file"
  rc=0
  timeout 5s "$file" >"$TMP/$tag.output" 2>"$TMP/$tag.err" || rc=$?
  test "$rc" -eq "$expected"
  test ! -s "$TMP/$tag.output"
  test ! -s "$TMP/$tag.err"
  if [[ -n "$ORACLE" ]]; then
    printf '%s\n' "$projection" >"$TMP/$tag.lisp"
    timeout 60s "$ORACLE" "$TMP/$tag.lisp" \
      >"$TMP/$tag.oracle" 2>"$TMP/$tag.oracle.err"
    test ! -s "$TMP/$tag.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$tag.expected"
    cmp "$TMP/$tag.expected" "$TMP/$tag.oracle"
    ORACLES=$((ORACLES+1))
  fi
  PASS=$((PASS+1))
done <"$TMP/fixtures/cases.tsv"
test "$PASS" -eq 32
if [[ -n "$ORACLE" ]]; then test "$ORACLES" -eq "$PASS"; fi
echo "G6.150-D24-PARITY-PASS physical=$PASS native=$PASS independent_oracle=$ORACLES negatives=10 deterministic=32 machine=TEST_SETcc energy=NOT_MEASURED"
# Не вимикаємо наявні 97+ FPC свідків іншої частини компілятора.
timeout 600s bash scripts/test-lowerd24.sh
