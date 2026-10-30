#!/usr/bin/env bash
# G6.85 — одна фізична D5:11011(W12,W12) → verified WideIR → ELF64.
set -Eeuo pipefail
trap 'echo "ШИРОКЕ-D5-БЛОК рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for tool in fpc timeout readelf objdump cmp mktemp grep python3; do
  command -v "$tool" >/dev/null || exit 127
done
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
ORACLE_BIN=$(printenv SENS_ORACLE_BIN || true)
REQUIRE_ORACLE=$(printenv REQUIRE_SENS_ORACLE || echo 0)
if [[ "$REQUIRE_ORACLE" == 1 ]]; then test -n "$ORACLE_BIN"; fi
if [[ -n "$ORACLE_BIN" ]]; then
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
  test -x "$ORACLE_BIN"
  grep -Fq '(11011 (ук більше?) (укр більше?)' sens-oracle/lib/domains/d5.lisp
  grep -Fq 'більше? proof "CMP+SETG+MOVZX' sens-oracle/lib/machine/profile/current-domain-x86-64.lisp
fi
TMP=$(mktemp -d);trap 'rm -rf "$TMP"' EXIT
BIN="$ROOT/build/m0.2/widebilsh/bin"
UNITS="$ROOT/build/m0.2/widebilsh/units"
mkdir -p "$BIN" "$UNITS" "$TMP/cases"
FPC_BIN=$(printenv FPC || echo fpc)
for source in src/senswidebilsh-elf.lpr src/sensd12bilsh-elf.lpr \
  scripts/test-elfd12bilsh.pas scripts/test-widebilsh-fixtures.pas; do
  name=$(basename "$source" | sed -E 's/\.(lpr|pas)$//')
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" -o"$name" "$ROOT/$source" \
    >"$TMP/$name.compile.log" 2>"$TMP/$name.compile.err" || {
      cat "$TMP/$name.compile.log" "$TMP/$name.compile.err" >&2;exit 1
    }
done
timeout 20s "$BIN/test-elfd12bilsh" "$TMP/cases" >"$TMP/matrix.tsv" 2>"$TMP/fixture.err"
timeout 20s "$BIN/test-widebilsh-fixtures" "$TMP/cases" \
  >"$TMP/physical-fixture.out" 2>"$TMP/physical-fixture.err"
test "$(wc -l <"$TMP/matrix.tsv")" -eq 12
test "$(find "$TMP/cases" -maxdepth 1 -name '*-program.sens' | wc -l)" -eq 12
MACHINE=0;ORACLE=0
while IFS=$'\t' read -r id left right expected; do
  source="$TMP/cases/$id-program.sens"
  elf="$TMP/$id.elf";old="$TMP/$id-old.elf"
  timeout 15s "$BIN/senswidebilsh-elf" \
    --скомпілювати-D5-більше-D12 "$source" "$elf" \
    >"$TMP/publish.log" 2>"$TMP/publish.err"
  test -x "$elf"
  # -gh публікує штатний heaptrc навіть за нульового витоку.
  # Тому перевіряємо ПОВНИЙ протокол stderr, а не приховуємо його.
  python3 - "$TMP/publish.err" <<'PYHEAP'
from pathlib import Path
import re, sys
lines=Path(sys.argv[1]).read_text(encoding='utf-8').splitlines()
assert len(lines)==5, f'неочікувана діагностика FPC: {lines!r}'
assert re.fullmatch(r'Heap dump by heaptrc unit of .+',lines[0]), lines
a=re.fullmatch(r'(\d+) memory blocks allocated\s+: (\d+)/(\d+)',lines[1])
b=re.fullmatch(r'(\d+) memory blocks freed\s+: (\d+)/(\d+)',lines[2])
assert a and b and a.groups()==b.groups(), f'витік allocation/free: {lines!r}'
assert re.fullmatch(r'0 unfreed memory blocks\s+: 0',lines[3]), lines
assert re.fullmatch(r'True heap size\s+: \d+',lines[4]), lines
PYHEAP
  grep -Fq 'machine=CMP/SETG' "$TMP/publish.log"
  timeout 15s "$BIN/sensd12bilsh-elf" --більше-D12 \
    "$TMP/cases/$id-l.sens" "$TMP/cases/$id-r.sens" "$old" >/dev/null
  cmp "$old" "$elf"
  readelf -h "$elf" | grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)'
  timeout 5s "$elf" >"$TMP/$id-out.sens"
  cmp "$TMP/cases/$id-expected.sens" "$TMP/$id-out.sens"
  timeout 15s "$BIN/senswidebilsh-elf" \
    --скомпілювати-D5-більше-D12 "$source" "$TMP/$id-again.elf" >/dev/null
  cmp "$elf" "$TMP/$id-again.elf"
  MACHINE=$((MACHINE+1))
  if [[ -n "$ORACLE_BIN" ]]; then
    printf '(більше? %s %s)\n' "$left" "$right" >"$TMP/expression.lisp"
    timeout 60s "$ORACLE_BIN" "$TMP/expression.lisp" >"$TMP/oracle.out" 2>"$TMP/oracle.err" || {
      cat "$TMP/oracle.err" >&2;exit 1
    }
    test ! -s "$TMP/oracle.err"
    python3 - "$TMP/oracle.out" "$expected" <<'PY'
from pathlib import Path
import sys
actual=Path(sys.argv[1]).read_text(encoding='utf-8').strip()
if actual.startswith('sens[укр]> '):
    actual=actual[len('sens[укр]> '):].strip()
projection={'1':'ТАК','0':'НІ','ТАК':'ТАК','НІ':'НІ',
            '(т а к)':'ТАК','(н і)':'НІ'}
assert actual in projection,f'невідомий pinned D1 формат: {actual!r}'
assert projection[actual]==sys.argv[2],f'SENS oracle mismatch: {actual!r}'
PY
    ORACLE=$((ORACLE+1))
  fi
done <"$TMP/matrix.tsv"
test "$MACHINE" -eq 12
if [[ -n "$ORACLE_BIN" ]]; then test "$ORACLE" -eq 12; fi
dd if="$TMP/03.elf" of="$TMP/machine.bytes" bs=1 skip=120 count=62 status=none
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/machine.bytes" >"$TMP/machine.asm"
grep -Eiq 'cmp[[:space:]]+eax,ecx' "$TMP/machine.asm"
grep -Eiq 'setg[[:space:]]+al' "$TMP/machine.asm"
grep -Eiq 'movzx[[:space:]]+eax,al' "$TMP/machine.asm"
NEG=0
reject() {
  local label=$1;shift
  local output="$TMP/reject-$label.elf"
  if timeout 12s "$BIN/senswidebilsh-elf" "$@" "$output" \
    >"$TMP/reject.stdout" 2>"$TMP/reject.stderr"; then
    echo "ШИРОКЕ-D5-ХИБНИЙ-ДОПУСК: $label" >&2;exit 1
  fi
  test ! -e "$output";test ! -s "$TMP/reject.stdout"
  grep -Fq 'ВІДМОВА:' "$TMP/reject.stderr"
  NEG=$((NEG+1))
}
for name in bad-head bad-d7-head bad-unary bad-arity bad-d24 \
  bad-w13 bad-nested bad-two-roots bad-no-list bad-dotted \
  bad-corrupt bad-padding bad-empty; do
  reject "$name" --скомпілювати-D5-більше-D12 "$TMP/cases/$name.sens"
done
reject projection --скомпілювати-D5-більше-D12 "$TMP/cases/bad-projection.lisp"
reject missing --скомпілювати-D5-більше-D12 "$TMP/cases/missing.sens"
reject mode --неіснуючий-D5 "$TMP/cases/03-program.sens"
test "$NEG" -eq 16
cp "$TMP/03.elf" "$TMP/existing.elf"
if timeout 12s "$BIN/senswidebilsh-elf" --скомпілювати-D5-більше-D12 \
  "$TMP/cases/03-program.sens" "$TMP/existing.elf" \
  >"$TMP/reject.stdout" 2>"$TMP/reject.stderr"; then
  echo 'ШИРОКЕ-D5-ХИБА: замінено ELF' >&2;exit 1
fi
cmp "$TMP/03.elf" "$TMP/existing.elf"
test ! -s "$TMP/reject.stdout"
timeout 12s "$BIN/senswidebilsh-elf" --скомпілювати-D5-більше-D12 \
  "$TMP/cases/03-program.sens" "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/cases/03-expected.sens" "$TMP/recovered.sens"
echo "ШИРОКЕ-D5-ELF-ГАРАЗД D2-WideIR=verified фізичних-програм=$MACHINE oracle=$ORACLE негативів=$NEG machine=CMP/SETG D1=T5M energy=NOT_MEASURED"
