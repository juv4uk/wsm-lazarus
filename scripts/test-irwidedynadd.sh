#!/usr/bin/env bash
# G6.144 — source qualified D5 ADD -> reusable machine D12 stdin.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)";cd "$ROOT"
TMP="$(mktemp -d)"
finish(){ local rc=$?;if ((rc));then
 echo "D5-DYN-FAIL code=$rc" >&2
 for f in "$TMP"/*.log "$TMP"/*.err;do [[ ! -s "$f" ]] || {
 echo "--- $f" >&2;tail -n 40 "$f" >&2; };done
 fi;rm -rf "$TMP";exit "$rc"; }
trap finish EXIT
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]]
for x in timeout fpc git readelf objdump cmp sha256sum grep mktemp;do
 command -v "$x" >/dev/null;done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(01010 (ук додати) (укр додати)' external/sens/lib/domains/d5.lisp
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ -n "$ORACLE" ]];then
 test -x "$ORACLE"
 test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data"
for row in 'src/senswideaddpotik.lpr:senswideaddpotik' \
 'scripts/test-irwidedynadd.pas:test-irwidedynadd' \
 'scripts/test-elfd12potik.pas:test-elfd12potik' \
 'src/senschyslo.lpr:senschyslo';do
 IFS=: read -r src exe <<<"$row"
 timeout 180s "${FPC:-fpc}" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
  "$ROOT/$src" >"$TMP/$exe.build.log" 2>&1 || {
  cat "$TMP/$exe.build.log" >&2;exit 1; }
done
HEAPTRC="log=$TMP/anchor.heap" timeout 60s "$TMP/bin/test-irwidedynadd" \
 "$TMP/data" >"$TMP/anchor.log" 2>"$TMP/anchor.err"
grep -Fq 'D5-DYN-ANCHOR-OK valid=2 identical=3 negatives=16' "$TMP/anchor.log"
grep -Fq '0 unfreed memory blocks' "$TMP/anchor.heap"
HEAPTRC="log=$TMP/fixtures.heap" timeout 50s "$TMP/bin/test-elfd12potik" \
 "$TMP/data" >"$TMP/cases.tsv" 2>"$TMP/fixtures.err"
grep -Fq 'Д12-ПОТІК-СВІДКИ-ГОТОВО позитивів=13' "$TMP/fixtures.err"
test "$(wc -l <"$TMP/cases.tsv")" -eq 13
MODE=--зібрати-D5-додавання-потік
ELF="$TMP/dynamic.elf"
HEAPTRC="log=$TMP/build.heap" timeout 60s "$TMP/bin/senswideaddpotik" \
 "$MODE" "$TMP/data/first.sens" "$ELF" >"$TMP/build.log" 2>"$TMP/build.err"
test -x "$ELF"
grep -Fq '0 unfreed memory blocks' "$TMP/build.heap"
test ! -s "$TMP/build.err"
grep -Fq 'machine=ADD stdin=2xT5M-D12' "$TMP/build.log"
timeout 60s "$TMP/bin/senswideaddpotik" "$MODE" "$TMP/data/second.sens" \
 "$TMP/second.elf" >"$TMP/second.log" 2>"$TMP/second.err"
cmp "$ELF" "$TMP/second.elf"
readelf -h "$ELF" >"$TMP/header.log"
readelf -l "$ELF" >"$TMP/segments.log"
grep -Eq 'Type:.*DYN' "$TMP/header.log"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
tail -c +121 "$ELF" >"$TMP/code"
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" >"$TMP/dis.log"
grep -Eiq 'add[[:space:]]+eax,r9d' "$TMP/dis.log"
SHA="$(sha256sum "$ELF" | cut -d' ' -f1)"
PASS=0;ORACLES=0
while IFS=$'\t' read -r name left right;do
 [[ -n "$name" ]]
 for repeat in 1 2;do
  timeout 5s "$ELF" <"$TMP/data/$name.frame" \
   >"$TMP/$name.$repeat.sens" 2>"$TMP/$name.$repeat.err"
  test ! -s "$TMP/$name.$repeat.err"
  cmp "$TMP/$name.$repeat.sens" "$TMP/data/$name-expected.sens"
  test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$SHA"
  PASS=$((PASS+1))
 done
 cmp "$TMP/$name.1.sens" "$TMP/$name.2.sens"
 if [[ -n "$ORACLE" ]];then
  printf '(додати %s %s)\n' "$left" "$right" >"$TMP/$name.lisp"
  timeout 60s "$ORACLE" "$TMP/$name.lisp" \
   >"$TMP/$name.oracle.lisp" 2>"$TMP/$name.oracle.err"
  test ! -s "$TMP/$name.oracle.err"
  timeout 10s "$TMP/bin/senschyslo" --в-укр D12 \
   "$TMP/$name.1.sens" >"$TMP/$name.actual.lisp"
  cmp "$TMP/$name.actual.lisp" "$TMP/$name.oracle.lisp"
  ORACLES=$((ORACLES+1))
 fi
done <"$TMP/cases.tsv"
test "$PASS" -eq 26
if [[ -n "$ORACLE" ]];then test "$ORACLES" -eq 13;fi
BAD=0
for frame in overflow-up overflow-down overflow-wide empty short1 short5 \
 extra invalid243 badfirst badsecond badthird badlast newline projection d1;do
 rc=0
 timeout 5s "$ELF" <"$TMP/data/$frame.frame" \
  >"$TMP/bad-$BAD.sens" 2>"$TMP/bad-$BAD.err" || rc=$?
 test "$rc" -eq 2 && test ! -s "$TMP/bad-$BAD.sens"
 grep -Fq 'Д12-ПОТІК-ВІДМОВА:' "$TMP/bad-$BAD.err"
 BAD=$((BAD+1))
done
test "$BAD" -eq 15
CLI_BAD=0
reject(){ local rc=0 dst="$TMP/rejected-$CLI_BAD.elf"
 timeout 30s "$TMP/bin/senswideaddpotik" "$@" "$dst" \
  >"$TMP/refused.out" 2>"$TMP/refused.err" || rc=$?
 test "$rc" -eq 2 && test ! -e "$dst" && test ! -L "$dst"
 test ! -s "$TMP/refused.out"
 grep -Fq 'Д5-ДИНАМІЧНЕ-ДОДАВАННЯ-ВІДМОВА:' "$TMP/refused.err"
 CLI_BAD=$((CLI_BAD+1));}
cp "$TMP/data/first.sens" "$TMP/data/fake.lisp"
printf '\377' >"$TMP/data/corrupt.sens"
: >"$TMP/data/empty.sens"
reject "$MODE" "$TMP/data/fake.lisp"
reject "$MODE" "$TMP/data/corrupt.sens"
reject "$MODE" "$TMP/data/empty.sens"
reject "$MODE" "$TMP/data/absent.sens"
reject --вигадано "$TMP/data/first.sens"
test "$CLI_BAD" -eq 5
cp "$ELF" "$TMP/occupied.elf"
rc=0
timeout 30s "$TMP/bin/senswideaddpotik" "$MODE" "$TMP/data/second.sens" \
 "$TMP/occupied.elf" >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$ELF" "$TMP/occupied.elf"
ln -s "$TMP/missing.elf" "$TMP/dangling.elf"
rc=0
timeout 30s "$TMP/bin/senswideaddpotik" "$MODE" "$TMP/data/second.sens" \
 "$TMP/dangling.elf" >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" && test ! -e "$TMP/missing.elf"
timeout 30s "$TMP/bin/senswideaddpotik" "$MODE" "$TMP/data/first.sens" \
 "$TMP/recovered.elf" >/dev/null
cmp "$ELF" "$TMP/recovered.elf"
timeout 5s "$TMP/recovered.elf" <"$TMP/data/12.frame" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/data/12-expected.sens"
echo "D5-DYNAMIC-WIDEIR-PASS machine=$PASS oracle=$ORACLES frame-negative=$BAD source-negative=16 cli-negative=$CLI_BAD no-clobber=2 recovery=1 energy=NOT-MEASURED"
