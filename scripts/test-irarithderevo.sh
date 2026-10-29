#!/usr/bin/env bash
# G6.146: справжній ELF64 зі змішаного фізичного D5 дерева, FPC+SENS.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc git timeout cmp readelf python3 grep mktemp;do
  command -v "$tool" >/dev/null || { echo "ДЕРЕВО-D5: бракує $tool" >&2; exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
git -C sens-oracle show HEAD:lib/domains/d5.lisp |
  grep -Fq '(01010 (ук додати) (укр додати)'
git -C sens-oracle show HEAD:lib/domains/d5.lisp |
  grep -Fq '(01011 (ук відняти) (укр відняти)'
ORACLE=$(printenv SENS_ORACLE_BIN || true)
[[ -n "$ORACLE" && -x "$ORACLE" ]] || {
  echo 'ДЕРЕВО-D5: незалежний pinned SENS oracle відсутній' >&2;exit 127;
}
TMP=$(mktemp -d)
fail() {
  local rc=$?
  echo "ДЕРЕВО-D5-ЗБІЙ line=$1 status=$rc" >&2
  for p in "$TMP"/*.log "$TMP"/*.err; do
    if [[ -s "$p" ]];then echo "--- $p" >&2;tail -n 18 "$p" >&2;fi
  done
  exit "$rc"
}
trap 'fail "$LINENO"' ERR
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
FPC_BIN=$(printenv FPC || echo fpc)
for row in \
  'scripts/test-irarithderevo.pas test-irarithderevo' \
  'src/sensarithderevoelf.lpr sensarithderevoelf' \
  'src/senschyslo.lpr senschyslo';do
  read -r source program <<<"$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$program" \
    "$ROOT/$source" >"$TMP/$program.build.log" 2>&1 || {
      cat "$TMP/$program.build.log" >&2;exit 1;
    }
done
timeout 180s "$TMP/bin/test-irarithderevo" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
# Не припускати, що FPC 3.2.2 однаково перекодовує Unicode-літерали
# у stdout: семантичний gate — вже підтверджені 32/17 у самому генераторі,
# тут звіряємо точні ASCII-поля; на невдачі показуємо ПОВНИЙ вивід.
if ! LC_ALL=C grep -Eq 'positive=32[[:space:]]+negative=17' \
  "$TMP/generator.out"; then
  echo 'ДЕРЕВО-D5: лічильники 32/17 не підтверджено' >&2
  cat "$TMP/generator.out" >&2
  od -An -tx1 "$TMP/generator.out" >&2
  exit 1
fi
if grep -Fq 'unfreed memory blocks' "$TMP/generator.err";then
  grep -Fq '0 unfreed memory blocks' "$TMP/generator.err"
fi

COUNT=0
while IFS=$'\t' read -r label steps;do
  test -n "$label" && test "$steps" -ge 1 && test "$steps" -le 31
  src="$TMP/physical/$label.sens"
  exe="$TMP/physical/$label.elf"
  test -s "$src" && test -s "$exe"
  readelf -h "$exe" >"$TMP/header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header"
  if readelf -l "$exe" |grep -Eq 'INTERP|DYNAMIC';then
    echo 'ДЕРЕВО-D5: ELF має динамічний загрузчик' >&2;exit 1
  fi
  python3 - "$exe" "$steps" <<'PY'
from pathlib import Path
import sys
b=Path(sys.argv[1]).read_bytes()
want=int(sys.argv[2])
pc=120
count=dict(mov=0,push=0,pop=0,add=0,sub=0)
stack=0
while True:
    if b[pc:pc+5]==bytes.fromhex('25ff0f0000'):
        break
    if b[pc]==0xb8:
        count['mov']+=1;pc+=5
    elif b[pc]==0x50:
        count['push']+=1;stack+=1;pc+=1
    elif b[pc]==0x59:
        count['pop']+=1;stack-=1;pc+=1
        assert stack>=0,'pop раніше за push'
    elif b[pc:pc+2]==bytes.fromhex('01c8'):
        count['add']+=1;pc+=2
    elif b[pc:pc+4]==bytes.fromhex('29c189c8'):
        count['sub']+=1;pc+=4
    else:
        raise AssertionError(f'невідома x86 операція offset={pc} byte={b[pc]:02x}')
    assert pc<len(b) and pc<4096,'машинний код вийшов за межу'
assert stack==0,count
assert count['mov']==want+1 and count['push']==want and count['pop']==want,count
assert count['add']+count['sub']==want,count
PY
  chmod 500 "$exe"
  timeout 10s "$exe" >"$TMP/actual.sens" 2>"$TMP/machine.err"
  test ! -s "$TMP/machine.err"
  cmp "$TMP/actual.sens" "$TMP/physical/$label.expected.sens"
  test "$(wc -c <"$TMP/actual.sens")" -eq 3
  timeout 30s "$TMP/bin/sensarithderevoelf" --змішане-дерево-D5 \
    "$src" "$TMP/$label.cli.elf" >"$TMP/cli.out" 2>"$TMP/cli.err"
  cmp "$TMP/$label.cli.elf" "$exe"
  timeout 15s "$ORACLE" "$TMP/physical/$label.oracle.lisp" \
    >"$TMP/oracle.out" 2>"$TMP/oracle.err"
  test ! -s "$TMP/oracle.err"
  timeout 10s "$TMP/bin/senschyslo" --в-укр D12 \
    "$TMP/actual.sens" >"$TMP/machine.ukr" 2>"$TMP/decimal.err"
  cmp "$TMP/machine.ukr" "$TMP/oracle.out"
  COUNT=$((COUNT+1))
done <"$TMP/physical/cases.tsv"
test "$COUNT" -eq 32
cp "$TMP/physical/2-8.elf" "$TMP/occupied.elf"
rc=0
timeout 15s "$TMP/bin/sensarithderevoelf" --змішане-дерево-D5 \
  "$TMP/physical/2-8.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out" &&
  test -s "$TMP/occupied.err"
cmp "$TMP/occupied.elf" "$TMP/physical/2-8.elf"
cp "$TMP/physical/2-8.sens" "$TMP/not-physical.lisp"
rc=0
timeout 15s "$TMP/bin/sensarithderevoelf" --змішане-дерево-D5 \
  "$TMP/not-physical.lisp" "$TMP/not-physical.elf" \
  >"$TMP/projection.out" 2>"$TMP/projection.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/projection.out" &&
  test ! -e "$TMP/not-physical.elf"
echo "ДЕРЕВО-D5-НАТИВНО-ГАРАЗД: FPC=так machine=32 oracle=32 negatives=17+2 push-pop=balanced mixed=так joules=NOT-MEASURED"
