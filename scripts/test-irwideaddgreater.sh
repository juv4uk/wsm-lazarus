#!/usr/bin/env bash
# G6.89 — pinned фізична вкладена D5:11011(D5:01010 D12 D12,D12).
# Жодної семантики з host-чисел: кожну відповідь перевіряє upstream.
set -Eeuo pipefail
trap 's=$?; echo "ВКЛАДЕНИЙ-Д5-ЗБІЙ status=$s line=$LINENO cmd=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
for tool in fpc timeout git objdump readelf cmp python3 mktemp grep; do
  command -v "$tool" >/dev/null || { echo "НЕМАЄ $tool" >&2; exit 127; }
done
git -C external/sens show HEAD:lib/domains/d5.lisp |
  grep -Fq '(01010 (ук додати) (укр додати)'
git -C external/sens show HEAD:lib/domains/d5.lisp |
  grep -Fq '(11011 (ук більше?) (укр більше?)'
git -C external/sens show HEAD:lib/machine/profile/current-domain-x86-64.lisp |
  grep -Fq 'більше? proof "CMP+SETG+MOVZX'
ORACLE_BIN=$(printenv SENS_ORACLE_BIN || true)
REQUIRE_ORACLE=$(printenv REQUIRE_SENS_ORACLE || echo 0)
if [[ "$REQUIRE_ORACLE" == 1 ]]; then test -n "$ORACLE_BIN"; fi
if [[ -n "$ORACLE_BIN" ]]; then
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
  test -x "$ORACLE_BIN"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/cases"
FPC_BIN=$(printenv FPC || echo fpc)
for entry in \
  'src/senswideaddgreaterelf.lpr senswideaddgreaterelf' \
  'scripts/test-irwideaddgreater-fixtures.pas test-irwideaddgreater-fixtures'; do
  read -r path executable <<< "$entry"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$executable" \
    "$ROOT/$path" >"$TMP/$executable.build" 2>"$TMP/$executable.build.err" || {
      cat "$TMP/$executable.build" "$TMP/$executable.build.err" >&2; exit 1
    }
  test -x "$TMP/bin/$executable"
done
timeout 15s "$TMP/bin/test-irwideaddgreater-fixtures" "$TMP/cases" \
  >"$TMP/cases.tsv" 2>"$TMP/fixtures.err"
test "$(wc -l < "$TMP/cases.tsv")" -eq 14
test "$(find "$TMP/cases" -name '*-program.sens' | wc -l)" -eq 14
# FPC WriteLn Unicode залежить від codepage хостового stderr.
# Перевіряти слід фізичні свідки, не друкований службовий текст.
test "$(find "$TMP/cases" -maxdepth 1 -name '*-expected.sens' | wc -l)" -eq 14
test "$(find "$TMP/cases" -maxdepth 1 -name 'bad-*.sens' | wc -l)" -eq 17
test -f "$TMP/cases/bad-projection.lisp"
test "$(wc -c < "$TMP/cases/bad-projection.lisp")" -gt 0

# FPC -gh навмисно вмикає heaptrc; успіх потребує нуль незвільнених
# блоків, рівності лічильників і відсутності сторонніх рядків stderr.
heap_clean() {
  python3 - "$1" <<'PYHEAP'
from pathlib import Path
import re,sys
lines=Path(sys.argv[1]).read_text(encoding='utf-8').splitlines()
# FPC -gh може не друкувати heaptrc за нормального виходу.
# Якщо звіт є — весь звіт мусить підтвердити нуль витоків.
if not lines:
    sys.exit(0)
assert len(lines)==5, f'неочікуваний stderr FPC: {lines!r}'
assert re.fullmatch(r'Heap dump by heaptrc unit of .+',lines[0]), lines
a=re.fullmatch(r'(\d+) memory blocks allocated\s+: (\d+)/(\d+)',lines[1])
b=re.fullmatch(r'(\d+) memory blocks freed\s+: (\d+)/(\d+)',lines[2])
assert a and b and a.groups()==b.groups(),f'витік пам’яті: {lines!r}'
assert re.fullmatch(r'0 unfreed memory blocks\s+: 0',lines[3]), lines
assert re.fullmatch(r'True heap size\s+: \d+',lines[4]), lines
PYHEAP
}

normal_repl() {
  python3 - "$1" <<'PYRESULT'
from pathlib import Path
import sys
lines=Path(sys.argv[1]).read_text(encoding='utf-8').strip().splitlines()
assert len(lines)==1,f'SENS повинен повернути один D1: {lines!r}'
s=lines[0].removeprefix('sens[укр]> ').strip()
d={'0':'0','1':'1','НІ':'0','ТАК':'1','(н і)':'0','(т а к)':'1'}
assert s in d,f'невідома pinned D1 проєкція: {s!r}'
print(d[s])
PYRESULT
}

CLI="$TMP/bin/senswideaddgreaterelf"
MODE=--скомпілювати-вкладене-більше
PASS=0;ORACLE=0;ONE=0;ZERO=0
while IFS=$'\t' read -r label a b c expected; do
  [[ $expected == 0 || $expected == 1 ]]
  path="$TMP/cases/$label-program.sens"
  elf="$TMP/$label.elf"
  timeout 15s "$CLI" "$MODE" "$path" "$elf" \
    >"$TMP/$label.compiler.out" 2>"$TMP/$label.compiler.err"
  heap_clean "$TMP/$label.compiler.err"
  grep -Fq 'ВКЛАДЕНИЙ-Д5-ЕЛФ-ГОТОВО' "$TMP/$label.compiler.out"
  test -x "$elf"
  readelf -h "$elf" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  dd if="$elf" of="$TMP/$label.code" bs=1 skip=120 count=80 status=none
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$label.code" >"$TMP/$label.dis"
  grep -Eiq 'add[[:space:]]+eax,' "$TMP/$label.dis"
  grep -Eiq 'cmp[[:space:]]+eax,ecx' "$TMP/$label.dis"
  grep -Eiq 'setg[[:space:]]+al' "$TMP/$label.dis"
  grep -Eiq 'movzx[[:space:]]+eax,al' "$TMP/$label.dis"
  timeout 5s "$elf" >"$TMP/$label.actual.sens"
  cmp "$TMP/cases/$label-expected.sens" "$TMP/$label.actual.sens"
  timeout 15s "$CLI" "$MODE" "$path" "$TMP/$label-again.elf" \
    >"$TMP/recompiled.out" 2>"$TMP/recompiled.err"
  heap_clean "$TMP/recompiled.err"
  cmp "$elf" "$TMP/$label-again.elf"
  if [[ $expected == 1 ]]; then ONE=$((ONE+1)); else ZERO=$((ZERO+1)); fi
  if [[ -n "$ORACLE_BIN" ]]; then
    printf '(більше? (додати %s %s) %s)\n' "$a" "$b" "$c" \
      >"$TMP/$label.lisp"
    timeout 60s "$ORACLE_BIN" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err" || {
        cat "$TMP/$label.oracle.err" >&2;exit 1
      }
    test ! -s "$TMP/$label.oracle.err"
    normal_repl "$TMP/$label.oracle" >"$TMP/$label.normal"
    test "$(cat "$TMP/$label.normal")" == "$expected"
    ORACLE=$((ORACLE+1))
  fi
  PASS=$((PASS+1))
done <"$TMP/cases.tsv"
test "$PASS" -eq 14 && test "$ONE" -gt 0 && test "$ZERO" -gt 0
if [[ -n "$ORACLE_BIN" ]]; then test "$ORACLE" -eq 14; fi

NEG=0
reject() {
  local label=$1;shift
  local output="$TMP/reject-$label.elf"
  local status=0
  timeout 15s "$CLI" "$@" "$output" \
    >"$TMP/reject.stdout" 2>"$TMP/reject.stderr" || status=$?
  test "$status" -eq 2
  test ! -e "$output"
  test ! -s "$TMP/reject.stdout"
  grep -Fq 'ВКЛАДЕНИЙ-Д5-ЕЛФ-ВІДМОВА:' "$TMP/reject.stderr"
  # Звіт -gh необов'язковий для нульового managed heap, але
  # будь-який наявний heaptrc мусить підтвердити нуль витоків.
  if grep -Fq 'Heap dump by heaptrc' "$TMP/reject.stderr"; then
    grep -Fq '0 unfreed memory blocks : 0' "$TMP/reject.stderr"
  fi
  NEG=$((NEG+1))
}
for label in bad-root bad-inner bad-d7 bad-d24 bad-w13 \
  bad-inner-missing bad-inner-extra bad-roots bad-flat bad-outer-extra \
  bad-outer-missing bad-dotted bad-corrupt bad-padding bad-empty \
  bad-overflow-positive bad-overflow-negative; do
  reject "$label" "$MODE" "$TMP/cases/$label.sens"
done
reject projection "$MODE" "$TMP/cases/bad-projection.lisp"
reject missing "$MODE" "$TMP/cases/missing.sens"
reject mode --невідомий "$TMP/cases/01-program.sens"
test "$NEG" -eq 20
cp "$TMP/01.elf" "$TMP/occupied.elf"
status=0
timeout 15s "$CLI" "$MODE" "$TMP/cases/01-program.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.stdout" 2>"$TMP/occupied.stderr" || status=$?
test "$status" -eq 2
cmp "$TMP/01.elf" "$TMP/occupied.elf"
test ! -s "$TMP/occupied.stdout"
ln -s "$TMP/01.elf" "$TMP/link.elf"
status=0
timeout 15s "$CLI" "$MODE" "$TMP/cases/01-program.sens" "$TMP/link.elf" \
  >"$TMP/link.stdout" 2>"$TMP/link.stderr" || status=$?
test "$status" -eq 2 && test -L "$TMP/link.elf"
test ! -s "$TMP/link.stdout"
timeout 15s "$CLI" "$MODE" "$TMP/cases/01-program.sens" "$TMP/recovered.elf" \
  >"$TMP/recovered.out" 2>"$TMP/recovered.err"
heap_clean "$TMP/recovered.err"
cmp "$TMP/01.elf" "$TMP/recovered.elf"
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/cases/01-expected.sens" "$TMP/recovered.sens"
echo "ВКЛАДЕНИЙ-D5-ЕЛФ-ГАРАЗД physical=$PASS true=$ONE false=$ZERO oracle=$ORACLE negatives=$NEG opcode=ADD,CMP,SETG/MOVZX result=D1-T5M leaks=0 energy=NOT_MEASURED"
