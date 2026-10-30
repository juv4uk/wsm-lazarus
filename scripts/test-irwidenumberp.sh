#!/usr/bin/env bash
# G6.174 — D5:01001 число? має машинні D1:1 (D12/D24) та D1:0 (D1).
# G6.158 — справжній pinned D5:01001 numberp-specialized native AOT.
# Вхід — тільки фізичне .sens; oracle — НЕ цей Pascal backend.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in timeout git fpc grep cmp readelf objdump tail od mktemp stat; do
  command -v "$tool" >/dev/null || {
    echo "ЧИСЛО-Д5-БЛОК: немає $tool" >&2; exit 127;
  }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ЧИСЛО-Д5-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
timeout 180s bash ./scripts/sync-authority.sh
timeout 120s bash ./scripts/check-pin.sh
timeout 120s bash ./scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(01001 (ук число?) (укр число?)' external/sens/lib/domains/d5.lisp
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ "${REQUIRE_SENS_ORACLE:-0}" == 1 && -z "$ORACLE" ]]; then
  echo 'ЧИСЛО-Д5-БЛОК: потрібен незалежний pinned SENS REPL' >&2
  exit 127
fi
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP=$(mktemp -d)
finish() {
  local rc=$? f
  if ((rc)); then
    echo "ЧИСЛО-Д5-ПРОВАЛ код=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.err "$TMP"/*.out; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 18 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
trap 'echo "ЧИСЛО-Д5-ЗБІЙ рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
FPC_BIN=${FPC:-fpc}
for row in \
  'scripts/test-irwidenumberp.pas test-irwidenumberp' \
  'src/senswidenumberpelf.lpr senswidenumberpelf'; do
  read -r source binary <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/$binary.build" 2>"$TMP/$binary.build.err" || {
      cat "$TMP/$binary.build" "$TMP/$binary.build.err" >&2; exit 1;
    }
  test -x "$TMP/bin/$binary"
done
timeout 35s "$TMP/bin/test-irwidenumberp" "$TMP/physical" \
  >"$TMP/fixture.out" 2>"$TMP/fixture.err"
grep -Fxq 'G6.174-ЧИСЛО-СВІДКИ-ГОТОВО physical=10' "$TMP/fixture.out"
check_heap() {
  if grep -Fq 'unfreed memory blocks' "$1"; then
    grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$1"
  fi
}
check_heap "$TMP/fixture.err"
MODE=--скомпілювати-D5-число
PASS=0; ORACLE_PASS=0; N1=0; N12=0; N24=0
while IFS=$'\t' read -r tag decimal width; do
  test -n "$tag"
  input="$TMP/physical/$tag.sens"
  elf="$TMP/$tag.elf"
  timeout 20s "$TMP/bin/senswidenumberpelf" "$MODE" "$input" "$elf" \
    >"$TMP/$tag.out" 2>"$TMP/$tag.err"
  grep -Fq 'ЕЛЬФ-Д5-ЧИСЛО-ГОТОВО:' "$TMP/$tag.out"
  check_heap "$TMP/$tag.err"
  test -x "$elf"
  test "$(stat -c %a "$elf")" = 700
  timeout 10s readelf -h "$elf" >"$TMP/$tag.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$tag.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$tag.header"
  ! timeout 10s readelf -l "$elf" | grep -Eq 'INTERP|DYNAMIC'
  tail -c +121 "$elf" >"$TMP/$tag.machine"
  timeout 10s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$tag.machine" >"$TMP/$tag.dis"
  grep -Fq 'syscall' "$TMP/$tag.dis"
  grep -Fq 'lea' "$TMP/$tag.dis"
  timeout 5s "$elf" >"$TMP/$tag.actual.sens" \
    2>"$TMP/$tag.machine.err"
  test ! -s "$TMP/$tag.machine.err"
  cmp "$TMP/physical/$tag.expected.sens" "$TMP/$tag.actual.sens"
  timeout 20s "$TMP/bin/senswidenumberpelf" "$MODE" "$input" \
    "$TMP/$tag.again.elf" >/dev/null 2>"$TMP/$tag.again.err"
  check_heap "$TMP/$tag.again.err"
  cmp "$elf" "$TMP/$tag.again.elf"
  if [[ -n "$ORACLE" ]]; then
    printf '(число? %s)\n' "$decimal" >"$TMP/$tag.lisp"
    timeout 60s "$ORACLE" "$TMP/$tag.lisp" \
      >"$TMP/$tag.oracle" 2>"$TMP/$tag.oracle.err"
    test ! -s "$TMP/$tag.oracle.err"
    if [[ "$width" == 1 ]]; then
      printf '0\n' >"$TMP/$tag.expected.oracle"
    else
      printf '1\n' >"$TMP/$tag.expected.oracle"
    fi
    cmp "$TMP/$tag.expected.oracle" "$TMP/$tag.oracle"
    ORACLE_PASS=$((ORACLE_PASS+1))
  fi
  case "$width" in
    1) N1=$((N1+1));;
    12) N12=$((N12+1));;
    24) N24=$((N24+1));;
    *) exit 71;;
  esac
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 10 && test "$N1" -eq 2 && test "$N12" -eq 5 && test "$N24" -eq 3
if [[ -n "$ORACLE" ]]; then test "$ORACLE_PASS" -eq 10; fi
NEG=0
reject() {
  local rc=0 target="$TMP/reject-$NEG.elf"
  timeout 20s "$TMP/bin/senswidenumberpelf" "$@" "$target" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/reject.out"
  grep -Fq 'ЕЛЬФ-Д5-ЧИСЛО-ВІДМОВА:' "$TMP/reject.err"
  check_heap "$TMP/reject.err"
  NEG=$((NEG+1))
}
for invalid in wrong-head wrong-domain d1-extra d1-nested d3 d7 d48 missing extra nested \
   two-roots dotted unclosed root-atom bad-t5m empty; do
  reject "$MODE" "$TMP/physical/$invalid.sens"
done
reject "$MODE" "$TMP/physical/fake.lisp"
reject "$MODE" "$TMP/physical/not-exists.sens"
reject --вигаданий "$TMP/physical/01.sens"
test "$NEG" -eq 19
cp "$TMP/01.elf" "$TMP/existing.elf"
rc=0
timeout 20s "$TMP/bin/senswidenumberpelf" "$MODE" \
  "$TMP/physical/02.sens" "$TMP/existing.elf" \
  >"$TMP/clobber.out" 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/clobber.out"
cmp "$TMP/01.elf" "$TMP/existing.elf"
timeout 20s "$TMP/bin/senswidenumberpelf" "$MODE" \
  "$TMP/physical/01.sens" "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/physical/01.expected.sens" "$TMP/recovered.sens"
echo "G6.174-ЧИСЛО-NATIVE-PASS physical=$PASS D1=$N1 D12=$N12 D24=$N24 machine=$PASS oracle=$ORACLE_PASS negative=$NEG no-clobber=yes energy=NOT-MEASURED"
