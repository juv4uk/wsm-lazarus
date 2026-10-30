#!/usr/bin/env bash
# G6.115: дев'ятий machine profile D6:010100 через existing 8 WideIR.
# pinned .sens -> verified WideIR -> original IDIV ELF64, без нового закону.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || {
  echo 'ДЕВЯТЬ-ПРОФІЛІВ-БЛОК: потрібен Linux x86-64' >&2;exit 127;
}
for c in fpc git timeout cmp grep readelf objdump mktemp; do
  command -v "$c" >/dev/null || { echo "ДЕВЯТЬ-ПРОФІЛІВ-БЛОК: бракує $c" >&2;exit 127; }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(010100 (ук остача) (укр остача)' external/sens/lib/domains/d6.lisp
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ -n "$ORACLE" ]];then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP="$(mktemp -d)"
cleanup() {
  local rc=$?
  if ((rc != 0));then
    echo "ДЕВЯТЬ-ПРОФІЛІВ-ПРОВАЛ: код=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 45 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
  exit "$rc"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
for spec in 'scripts/test-irwiderest.pas:test-irwiderest' \
            'scripts/test-irwidefront-rest.pas:test-irwidefront-rest' \
            'src/senswidefrontelf.lpr:senswidefrontelf' \
            'src/senswiderestelf.lpr:senswiderestelf';do
  IFS=: read -r source exe <<<"$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$source" >"$TMP/$exe.build.log" 2>&1 || {
      cat "$TMP/$exe.build.log" >&2;exit 1; }
  test -x "$TMP/bin/$exe"
done
HEAPTRC="log=$TMP/gen.heap" timeout 30s \
  "$TMP/bin/test-irwiderest" "$TMP/physical" >"$TMP/gen.log" 2>"$TMP/gen.err"
grep -Fq 'G6.102-REST-FIXTURES-OK cases=28' "$TMP/gen.log"
test -s "$TMP/gen.heap"
grep -Fq '0 unfreed memory blocks' "$TMP/gen.heap"
HEAPTRC="log=$TMP/check.heap" timeout 30s \
  "$TMP/bin/test-irwidefront-rest" "$TMP/physical" >"$TMP/check.log" 2>"$TMP/check.err"
grep -Fq 'NINE-WIDEIR-REST-OK physical=28 negatives=22 identical=28' "$TMP/check.log"
test -s "$TMP/check.heap"
grep -Fq '0 unfreed memory blocks' "$TMP/check.heap"
FRONT=--скомпілювати-фізичну-форму
REST=--скомпілювати-D6-остача-D12
passed=0;verified=0
while IFS=$'\t' read -r label dividend divisor expected;do
  test -n "$label"
  elf="$TMP/$label.elf"
  HEAPTRC="log=$TMP/$label.heap" timeout 20s \
    "$TMP/bin/senswidefrontelf" "$FRONT" "$TMP/physical/$label.sens" "$elf" \
    >"$TMP/$label.out.log" 2>"$TMP/$label.err"
  test -x "$elf"
  test ! -s "$TMP/$label.err"
  grep -Fq '0 unfreed memory blocks' "$TMP/$label.heap"
  grep -Fq 'machine=pinned-exact-WideIR stdout=T5M' "$TMP/$label.out.log"
  timeout 20s "$TMP/bin/senswiderestelf" "$REST" \
    "$TMP/physical/$label.sens" "$TMP/$label.special.elf" \
    >"$TMP/$label.spec.log" 2>"$TMP/$label.spec.err"
  cmp "$elf" "$TMP/$label.special.elf"
  readelf -h "$elf" >"$TMP/$label.head.log"
  grep -Eq 'Type:.*DYN' "$TMP/$label.head.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.head.log"
  readelf -l "$elf" >"$TMP/$label.phdr.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/$label.phdr.log"
  tail -c +121 "$elf" >"$TMP/code"
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/code" >"$TMP/$label.asm.log"
  grep -Eq 'idiv[[:space:]]+rcx' "$TMP/$label.asm.log"
  grep -Eq 'add[[:space:]]+edx,ecx' "$TMP/$label.asm.log"
  grep -Eq 'jns[[:space:]]' "$TMP/$label.asm.log"
  timeout 5s "$elf" >"$TMP/$label.actual.sens"
  cmp "$TMP/$label.actual.sens" "$TMP/physical/$label.expected.sens"
  test "$(wc -c <"$TMP/$label.actual.sens")" -eq 3
  if [[ -n "$ORACLE" ]];then
    printf '(остача %s %s)\n' "$dividend" "$divisor" >"$TMP/$label.lisp"
    timeout 60s "$ORACLE" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle.log" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.oracle.expected"
    cmp "$TMP/$label.oracle.log" "$TMP/$label.oracle.expected"
    verified=$((verified+1))
  fi
  passed=$((passed+1))
done <"$TMP/physical/cases.tsv"
test "$passed" -eq 28
if [[ -n "$ORACLE" ]];then test "$verified" -eq 28;fi

neg=0
reject() {
  local label="$1";shift
  local output="$TMP/rejected-$neg.elf" rc=0
  timeout 20s "$TMP/bin/senswidefrontelf" "$@" "$output" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$output" && test ! -L "$output"
  test ! -s "$TMP/reject.out"
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/reject.err"
  neg=$((neg+1))
}
for f in other-d7 d1 d3-empty d7 d24 missing extra nested \
  two-roots dotted root-atom unclosed close-only bad-t5m empty div-zero \
  d24-right d48-left min-left min-right min-both positive-negdiv-width;do
  reject "$f" "$FRONT" "$TMP/physical/$f.sens"
done
reject text "$FRONT" "$TMP/physical/fake.lisp"
reject absent "$FRONT" "$TMP/physical/absent.sens"
reject bad-mode --вигадано "$TMP/physical/01.sens"
test "$neg" -eq 25
cp "$TMP/01.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" "$FRONT" \
 "$TMP/physical/02.sens" "$TMP/occupied.elf" >"$TMP/occupied.out" \
  2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/01.elf"
ln -s "$TMP/blocked.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" "$FRONT" \
 "$TMP/physical/03.sens" "$TMP/dangling.elf" >"$TMP/dangling.out" \
  2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" && test ! -e "$TMP/blocked.elf"
timeout 20s "$TMP/bin/senswidefrontelf" "$FRONT" \
 "$TMP/physical/14.sens" "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/physical/14.expected.sens"

# Чинні 8 профілів і їхні 26 фізичних + 6 старих + 23 відмови.
timeout 1200s bash scripts/test-irwidefront-8.sh \
  >"$TMP/prior-eight.log" 2>"$TMP/prior-eight.err"
grep -Fq 'ВІСІМ-ПРОФІЛІВ-ГОТОВО: sub=12 nsd=14' "$TMP/prior-eight.log"
echo "NINE-WIDEIR-REST-DONE physical=$passed oracle=$verified negative=$neg previous-eight=yes energy=NOT-MEASURED"
