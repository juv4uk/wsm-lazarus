#!/usr/bin/env bash
# G6.105 — real FPC + native nested D6 min/max + independent SENS REPL.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
on_error(){
  local rc=$?
  echo "G6.105-ПОМИЛКА рядок=$1 exit=$rc" >&2
  for f in "$TMP"/*.err "$TMP"/*.log;do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 15 "$f" >&2; }
  done
  exit "$rc"
}
trap 'on_error "$LINENO"' ERR
trap 'rm -rf "$TMP"' EXIT
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]]
for exe in git fpc timeout readelf objdump cmp dd awk python3;do
  command -v "$exe" >/dev/null || { echo "немає $exe" >&2;exit 127; }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
for head in '110101 (ук найменше) (укр найменше)' \
            '110111 (ук найбільше) (укр найбільше)';do
  git -C external/sens show "$PIN:lib/domains/d6.lisp" |
    grep -Fq "($head"
done
ORACLE=${SENS_ORACLE_BIN:-}
if [[ -n "$ORACLE" ]];then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
for row in \
  'src/sensmixedextremaelf.lpr sensmixedextremaelf' \
  'scripts/test-irmixedextrema.pas test-irmixedextrema' \
  'src/senschyslo.lpr senschyslo';do
  read -r source binary <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/$binary.log" 2>&1 || {
      cat "$TMP/$binary.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$binary"
done
timeout 30s "$TMP/bin/test-irmixedextrema" "$TMP/physical" \
  >"$TMP/fixture.log" 2>"$TMP/fixture.err"
grep -Fq 'G6.105-FIXTURES-OK positive=16 negative=18' "$TMP/fixture.log"
MODE=--скомпілювати-вкладені-D6
POSITIVE=0
ORACLE_COUNT=0
for depth in 1 2 3 4;do
  for pattern in 0 1 2 3;do
    tag="$depth-$pattern"
    elf="$TMP/$tag.elf"
    timeout 20s "$TMP/bin/sensmixedextremaelf" "$MODE" \
      "$TMP/physical/$tag.sens" "$elf" \
      >"$TMP/$tag.status" 2>"$TMP/$tag.err"
    test ! -s "$TMP/$tag.err"
    grep -Fq 'machine=CMP/CMOV stdout=T5M-D12' "$TMP/$tag.status"
    test -x "$elf"
    readelf -h "$elf" >"$TMP/$tag.header"
    grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$tag.header"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$tag.header"
    dd if="$elf" of="$TMP/$tag.code" bs=1 skip=120 \
      count=$((15+10*(depth-1))) status=none
    objdump -D -b binary -m i386:x86-64 -M intel \
      "$TMP/$tag.code" >"$TMP/$tag.dis"
    grep -Eio 'cmov(g|l)[[:space:]]+eax,ecx' "$TMP/$tag.dis" |
      awk '{print $1}' >"$TMP/$tag.actual.ops"
    cmp "$TMP/physical/$tag.ops" "$TMP/$tag.actual.ops"
    timeout 10s "$elf" >"$TMP/$tag.actual.sens" 2>"$TMP/$tag.machine.err"
    test ! -s "$TMP/$tag.machine.err"
    test "$(wc -c <"$TMP/$tag.actual.sens")" -eq 3
    cmp "$TMP/physical/$tag.expected.sens" "$TMP/$tag.actual.sens"
    timeout 15s "$TMP/bin/sensmixedextremaelf" "$MODE" \
      "$TMP/physical/$tag.sens" "$TMP/$tag.again.elf" \
      >"$TMP/$tag.again.out" 2>"$TMP/$tag.again.err"
    cmp "$elf" "$TMP/$tag.again.elf"
    if [[ -n "$ORACLE" ]];then
      timeout 15s "$TMP/bin/senschyslo" --в-укр D12 \
        "$TMP/$tag.actual.sens" >"$TMP/$tag.projected"
      timeout 60s "$ORACLE" "$TMP/physical/$tag.lisp" \
        >"$TMP/$tag.oracle" 2>"$TMP/$tag.oracle.err"
      test ! -s "$TMP/$tag.oracle.err"
      cmp "$TMP/$tag.oracle" "$TMP/$tag.projected"
      ORACLE_COUNT=$((ORACLE_COUNT+1))
    fi
    POSITIVE=$((POSITIVE+1))
  done
done
test "$POSITIVE" -eq 16
if [[ -n "$ORACLE" ]];then test "$ORACLE_COUNT" -eq 16;fi
NEGATIVE=0
reject(){
  local rc=0 output="$TMP/rejected-$NEGATIVE.elf"
  timeout 15s "$TMP/bin/sensmixedextremaelf" "$@" "$output" \
    >"$TMP/negative.stdout" 2>"$TMP/negative.stderr" || rc=$?
  test "$rc" -eq 2 || { echo "негатив не відхилено: $NEGATIVE, rc=$rc" >&2;return 1; }
  test ! -e "$output" && test ! -L "$output"
  test ! -s "$TMP/negative.stdout"
  grep -Fq 'ВІДМОВА:' "$TMP/negative.stderr"
  NEGATIVE=$((NEGATIVE+1))
}
for neg in bad-depth5 bad-source-d1 bad-source-d7 bad-source-d24 \
  bad-corrupt bad-empty bad-unclosed bad-two-roots bad-head-d6 \
  bad-head-d5 bad-head-d7 bad-nested-head bad-left-d1 \
  bad-left-d7 bad-left-d24 bad-right-d1 bad-right-d7 bad-right-d24;do
  reject "$MODE" "$TMP/physical/$neg.sens"
done
reject "$MODE" "$TMP/physical/2-1.lisp"
reject "$MODE" "$TMP/physical/missing.sens"
reject --вигаданий-режим "$TMP/physical/2-1.sens"
test "$NEGATIVE" -eq 21
cp "$TMP/2-1.elf" "$TMP/protected.elf"
status=0
timeout 20s "$TMP/bin/sensmixedextremaelf" "$MODE" "$TMP/physical/1-0.sens" \
  "$TMP/protected.elf" >"$TMP/protected.out" 2>"$TMP/protected.err" || status=$?
test "$status" -eq 2
test ! -s "$TMP/protected.out"
cmp "$TMP/2-1.elf" "$TMP/protected.elf"
ln -s "$TMP/absent.elf" "$TMP/dangling.elf"
status=0
timeout 20s "$TMP/bin/sensmixedextremaelf" "$MODE" "$TMP/physical/2-1.sens" \
  "$TMP/dangling.elf" >"$TMP/dangling.out" 2>"$TMP/dangling.err" || status=$?
test "$status" -eq 2 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/absent.elf"
timeout 20s "$TMP/bin/sensmixedextremaelf" "$MODE" "$TMP/physical/2-1.sens" \
  "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/physical/2-1.expected.sens" "$TMP/recovered.sens"
echo "G6.105-MIXED-EXTREMA-OK physical=$POSITIVE oracle=$ORACLE_COUNT negatives=$NEGATIVE order=1..4 byte-identical=yes no-clobber=yes ENERGY_NOT_MEASURED"
