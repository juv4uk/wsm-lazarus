#!/usr/bin/env bash
# G6.116 — два незалежні фізичні D5 піддерева → один справжній ELF64.
# Canonical .sens, pinned D3/D5/D12, 32 physical binary witnesses, 21+ negatives.
set -Eeuo pipefail
trap 'status=$?; echo "ВИБІР-ДВОХ-АРИФМЕТИЧНИХ-ГІЛОК-ЗБІЙ status=$status line=$LINENO cmd=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for tool in fpc git timeout python3 readelf objdump cmp dd grep mktemp; do
  command -v "$tool" >/dev/null || exit 127
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
git -C external/sens show HEAD:lib/domains/d3.lisp |
  grep -Fq '(101 (ук тотожне?) (укр тотожне?)'
git -C external/sens show HEAD:lib/domains/d5.lisp |
  grep -Fq '(01010 (ук додати) (укр додати)'
git -C external/sens show HEAD:lib/domains/d5.lisp |
  grep -Fq '(01011 (ук відняти) (укр відняти)'
git -C external/sens show HEAD:lib/domains/d3.lisp |
  grep -Fq '(101 (ук тотожне?) (укр тотожне?)'
SENS_ORACLE_BIN=$(printenv SENS_ORACLE_BIN || true)
if [[ $(printenv REQUIRE_SENS_ORACLE || echo 0) == 1 ]]; then
  test -n "$SENS_ORACLE_BIN"
fi
if [[ -n "$SENS_ORACLE_BIN" ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" == "$PIN"
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/cases"
FPC_BIN=$(printenv FPC || echo fpc)
for entry in \
 'src/senstwoarithchoiceelf.lpr senstwoarithchoiceelf' \
 'scripts/test-irtwoarithchoice.pas test-irtwoarithchoice'; do
  read -r path executable <<<"$entry"
  if ! timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$executable" \
    "$ROOT/$path" >"$TMP/$executable.build.out" 2>"$TMP/$executable.build.err"; then
    cat "$TMP/$executable.build.out" "$TMP/$executable.build.err" >&2
    exit 1
  fi
  test -x "$TMP/bin/$executable"
done
timeout 20s "$TMP/bin/test-irtwoarithchoice" "$TMP/cases" \
  >"$TMP/cases.tsv" 2>"$TMP/fixture.err"
test "$(wc -l < "$TMP/cases.tsv")" -eq 32
test "$(find "$TMP/cases" -maxdepth 1 -name '*-program.sens' | wc -l)" -eq 32
test "$(find "$TMP/cases" -maxdepth 1 -name '*-expected.sens' | wc -l)" -eq 32
test "$(find "$TMP/cases" -maxdepth 1 -name 'bad-*.sens' | wc -l)" -eq 21
test -s "$TMP/cases/fake.lisp"

# З -gh FPC може видати штатний heaptrc або нічого. Якщо видано —
# повний протокол allocation/free перевіряється, чужий stderr відхиляється.
clean_heap() {
  python3 - "$1" <<'PY'
from pathlib import Path
import re,sys
lines=Path(sys.argv[1]).read_text(encoding='utf-8').splitlines()
if not lines: sys.exit(0)
assert len(lines)==5,f'неочікуваний FPC stderr: {lines!r}'
assert re.fullmatch(r'Heap dump by heaptrc unit of .+',lines[0]),lines
a=re.fullmatch(r'(\d+) memory blocks allocated\s+: (\d+)/(\d+)',lines[1])
b=re.fullmatch(r'(\d+) memory blocks freed\s+: (\d+)/(\d+)',lines[2])
assert a and b and a.groups()==b.groups(),f'heap-trace leak: {lines!r}'
assert re.fullmatch(r'0 unfreed memory blocks\s+: 0',lines[3]),lines
assert re.fullmatch(r'True heap size\s+: \d+',lines[4]),lines
PY
}
normalize_repl() {
 python3 - "$1" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(encoding='utf-8').strip()
if s.startswith('sens[укр]> '): s=s[len('sens[укр]> '):].strip()
d={'0':'0','1':'1','НІ':'0','ТАК':'1','(н і)':'0','(т а к)':'1'}
assert s in d,f'невідома D1 pinned SENS проєкція: {s!r}'
print(d[s])
PY
}
CLI="$TMP/bin/senstwoarithchoiceelf"
MODE=--скомпілювати-вибір-двох-арифметичних-гілок
PASS=0;ORACLE=0;TRUE=0;FALSE=0
while IFS=$'\t' read -r label a b c d lop rop expected; do
  [[ $expected == 0 || $expected == 1 ]]
  source="$TMP/cases/$label-program.sens"
  elf="$TMP/$label.elf"
  timeout 15s "$CLI" "$MODE" "$source" "$elf" \
    >"$TMP/compiler.out" 2>"$TMP/compiler.err"
  clean_heap "$TMP/compiler.err"
  grep -Fq 'ВИБІР-ДВОХ-АРИФМЕТИЧНИХ-ГІЛОК-ELF-ГОТОВО:' "$TMP/compiler.out"
  test -x "$elf"
  readelf -h "$elf" >"$TMP/$label.header"
  grep -Eq 'Type:.*DYN' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  dd if="$elf" of="$TMP/$label.prefix" bs=1 skip=120 count=37 status=none
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$label.prefix" >"$TMP/$label.asm"

  # Два незалежні арифметичні машинні opcode рівно відповідають
  # pinned D5 координатам обох дочірніх піддерев.
  want_add=0;want_sub=0
  for head in "$lop" "$rop"; do
    case "$head" in
      01010) want_add=$((want_add+1)) ;;
      01011) want_sub=$((want_sub+1)) ;;
      *) echo 'недопустимий фізичний D5 fixture' >&2;exit 1 ;;
    esac
  done
  found_add=$(grep -Eic 'add[[:space:]]+eax,' "$TMP/$label.asm" || true)
  found_sub=$(grep -Eic 'sub[[:space:]]+eax,' "$TMP/$label.asm" || true)
  test "$found_add" -eq "$want_add"
  test "$found_sub" -eq "$want_sub"
  grep -Eiq 'cmp[[:space:]]+eax,ecx' "$TMP/$label.asm"
  grep -Eiq 'sete[[:space:]]+al' "$TMP/$label.asm"
  grep -Eiq 'movzx[[:space:]]+eax,al' "$TMP/$label.asm"
  test "$(grep -Eic 'xchg[[:space:]]+e(ax|cx),e(ax|cx)' "$TMP/$label.asm")" -eq 2
  timeout 5s "$elf" >"$TMP/$label.actual.sens"
  cmp "$TMP/cases/$label-expected.sens" "$TMP/$label.actual.sens"
  timeout 15s "$CLI" "$MODE" "$source" "$TMP/$label.again.elf" \
    >"$TMP/recompiled.out" 2>"$TMP/recompiled.err"
  clean_heap "$TMP/recompiled.err"
  cmp "$elf" "$TMP/$label.again.elf"
  if [[ $expected == 1 ]]; then TRUE=$((TRUE+1)); else FALSE=$((FALSE+1)); fi
  if [[ -n "$SENS_ORACLE_BIN" ]]; then
    # SAME physical binary SENS file — no user .lisp semantics as oracle.
    timeout 60s "$SENS_ORACLE_BIN" "$source" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err" || {
        cat "$TMP/$label.oracle.err" >&2;exit 1
      }
    test ! -s "$TMP/$label.oracle.err"
    normalize_repl "$TMP/$label.oracle" >"$TMP/$label.normal"
    test "$(cat "$TMP/$label.normal")" == "$expected"
    ORACLE=$((ORACLE+1))
  fi
  PASS=$((PASS+1))
done <"$TMP/cases.tsv"
test "$PASS" -eq 32 && test "$TRUE" -gt 0 && test "$FALSE" -gt 0
if [[ -n "$SENS_ORACLE_BIN" ]]; then test "$ORACLE" -eq 32; fi

NEG=0
reject() {
  local label=$1;shift
  local output="$TMP/bad-$label.elf" rc=0
  timeout 15s "$CLI" "$@" "$output" \
    >"$TMP/reject.stdout" 2>"$TMP/reject.stderr" || rc=$?
  test "$rc" -eq 2 && test ! -e "$output" && test ! -s "$TMP/reject.stdout"
  grep -Fq 'ВИБІР-ДВОХ-АРИФМЕТИЧНИХ-ГІЛОК-ELF-ВІДМОВА:' "$TMP/reject.stderr"
  if grep -Fq 'Heap dump by heaptrc' "$TMP/reject.stderr"; then
    grep -Fq '0 unfreed memory blocks : 0' "$TMP/reject.stderr"
  fi
  NEG=$((NEG+1))
}
for label in root left-head right-head flat missing-left missing-right \
 extra-left extra-right d1-left d7-right d24 w13 two-roots dotted \
 corrupt padding empty overflow-plus-left overflow-minus-left \
 overflow-plus-right overflow-minus-right; do
  reject "$label" "$MODE" "$TMP/cases/bad-$label.sens"
done
test "$NEG" -eq 21
reject projection "$MODE" "$TMP/cases/fake.lisp"
reject missing "$MODE" "$TMP/cases/no-program.sens"
reject mode --неіснуючий "$TMP/cases/01-program.sens"
test "$NEG" -eq 24
cp "$TMP/01.elf" "$TMP/occupied.elf"
rc=0
timeout 15s "$CLI" "$MODE" "$TMP/cases/02-program.sens" "$TMP/occupied.elf" \
 >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/01.elf" "$TMP/occupied.elf"
ln -s "$TMP/absent.elf" "$TMP/dangling.elf"
rc=0
timeout 15s "$CLI" "$MODE" "$TMP/cases/02-program.sens" "$TMP/dangling.elf" \
 >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" && test ! -e "$TMP/absent.elf"
test ! -s "$TMP/dangling.out"
timeout 15s "$CLI" "$MODE" "$TMP/cases/02-program.sens" "$TMP/recovered.elf" \
 >"$TMP/recovered.out" 2>"$TMP/recovered.err"
clean_heap "$TMP/recovered.err"
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/cases/02-expected.sens" "$TMP/recovered.sens"
echo "ВИБІР-ДВОХ-АРИФМЕТИЧНИХ-ГІЛОК-ГАРАЗД фізичних=$PASS позитивних=$TRUE негативних=$FALSE pinned-oracle=$ORACLE відмов=$NEG machine=ALU,XCHG,ALU,XCHG,CMP,SETE,MOVZX ELF=1 D1=T5M energy=NOT_MEASURED"
