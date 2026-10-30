#!/usr/bin/env bash
# G6.181 — фізичний D6 NEG→ABS у справжньому машинному ELF64.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
for tool in fpc git timeout readelf objdump cmp python3 mktemp grep;do
  command -v "$tool" >/dev/null || { echo "Д6-ЗНАК-МОДУЛЬ-БЛОК $tool" >&2;exit 127; }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(010010 (ук змінити-знак) (укр змінити-знак)' external/sens/lib/domains/d6.lisp
grep -Fq '(010011 (ук модуль) (укр модуль)' external/sens/lib/domains/d6.lisp
ORACLE=$(printenv SENS_ORACLE_BIN || true)
REQUIRE=$(printenv REQUIRE_SENS_ORACLE || echo 0)
if [[ "$REQUIRE" == 1 && -z "$ORACLE" ]]; then exit 127; fi
if [[ -n "$ORACLE" ]];then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP=$(mktemp -d)
cleanup() {
  local rc=$? f
  if ((rc)); then
    echo "Д6-ЗНАК-МОДУЛЬ-ПРОВАЛ rc=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.err "$TMP"/*.out;do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 20 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/свідки"
for row in \
  'scripts/test-d6negabs-fixtures.pas test-d6negabs-fixtures' \
  'src/sensd6negabself.lpr sensd6negabself';do
  read -r source exe <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$source" >"$TMP/$exe.build" 2>&1 || {
      cat "$TMP/$exe.build" >&2; exit 1;
    }
  test -x "$TMP/bin/$exe"
done
timeout 20s "$TMP/bin/test-d6negabs-fixtures" "$TMP/свідки" \
  >"$TMP/gen.out" 2>"$TMP/gen.err"
test "$(wc -l <"$TMP/свідки/cases.tsv")" -eq 14
for label in 01 02 03 04 05 06 07 08 09 10 11 12 13 14; do
  test -s "$TMP/свідки/$label.sens"
  test -s "$TMP/свідки/$label.expected.sens"
done
MODE=--скомпілювати-D6-знак-модуль
NATIVE=0;ORACLE_PASS=0;WIDE=0
while IFS=$'\t' read -r label value wanted width;do
  test -n "$label"
  elf="$TMP/$label.elf"
  timeout 35s "$TMP/bin/sensd6negabself" "$MODE" \
    "$TMP/свідки/$label.sens" "$elf" \
    >"$TMP/$label.out" 2>"$TMP/$label.err"
  test -x "$elf"
  grep -Fq 'machine=NEG_CDQ_XOR_SUB' "$TMP/$label.out"
  readelf -h "$elf" >"$TMP/elfheader"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/elfheader"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elfheader"
  ! readelf -l "$elf" | grep -Eq 'INTERP|DYNAMIC'
  for attempt in 1 2;do
    timeout 5s "$elf" >"$TMP/$label-$attempt.actual.sens" \
      2>"$TMP/$label-$attempt.err"
    test ! -s "$TMP/$label-$attempt.err"
    cmp "$TMP/$label-$attempt.actual.sens" "$TMP/свідки/$label.expected.sens"
    if [[ "$width" == 24 ]];then
      test "$(wc -c <"$TMP/$label-$attempt.actual.sens")" -eq 5
    else
      test "$(wc -c <"$TMP/$label-$attempt.actual.sens")" -eq 3
    fi
  done
  cmp "$TMP/$label-1.actual.sens" "$TMP/$label-2.actual.sens"
  if [[ -n "$ORACLE" ]];then
    printf '(модуль (змінити-знак %s))\n' "$value" >"$TMP/$label.lisp"
    timeout 60s "$ORACLE" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$wanted" >"$TMP/$label.expected"
    cmp "$TMP/$label.oracle.out" "$TMP/$label.expected"
    ORACLE_PASS=$((ORACLE_PASS+1))
  fi
  [[ "$width" == 24 ]] && WIDE=$((WIDE+1))
  NATIVE=$((NATIVE+1))
done <"$TMP/свідки/cases.tsv"
test "$NATIVE" -eq 14 && test "$WIDE" -eq 1
if [[ -n "$ORACLE" ]];then test "$ORACLE_PASS" -eq 14;fi
python3 - "$TMP/08.elf" "$TMP/machine.bin" <<'PY'
from pathlib import Path
import struct,sys
raw=Path(sys.argv[1]).read_bytes()
assert raw[:4]==b'\x7fELF'
assert struct.unpack_from('<Q',raw,96)[0]==len(raw)
assert struct.unpack_from('<Q',raw,104)[0]==len(raw)
assert raw[120]==0xB8
assert raw[125:132]==bytes.fromhex('f7 d8 99 31 d0 29 d0')
Path(sys.argv[2]).write_bytes(raw[120:132])
PY
objdump -D -b binary -m i386:x86-64 -M intel \
  "$TMP/machine.bin" >"$TMP/machine.asm"
grep -Eiq 'neg[[:space:]]+eax' "$TMP/machine.asm"
grep -Eiq 'cdq' "$TMP/machine.asm"
grep -Eiq 'xor[[:space:]]+eax,edx' "$TMP/machine.asm"
grep -Eiq 'sub[[:space:]]+eax,edx' "$TMP/machine.asm"
NEG=0
for name in other-outer other-inner swapped bare d24 d1 d3 extra \
  missing unclosed two-roots root-atom dotted bad-t5m empty fake;do
  file="$TMP/свідки/$name.sens"
  [[ "$name" == fake ]] && file="$TMP/свідки/fake.lisp"
  out="$TMP/rejected-$NEG.elf"
  rc=0
  timeout 25s "$TMP/bin/sensd6negabself" "$MODE" "$file" "$out" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/reject.out"
  test ! -e "$out" && test ! -L "$out"
  grep -Fq 'Д6-ЗНАК-МОДУЛЬ-ВІДМОВА:' "$TMP/reject.err"
  NEG=$((NEG+1))
done
test "$NEG" -eq 16
cp "$TMP/01.elf" "$TMP/existing.elf"
rc=0
timeout 30s "$TMP/bin/sensd6negabself" "$MODE" \
  "$TMP/свідки/02.sens" "$TMP/existing.elf" \
  >"$TMP/clobber.out" 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/clobber.out"
cmp "$TMP/existing.elf" "$TMP/01.elf"
ln -s "$TMP/missing.elf" "$TMP/occupied-link.elf"
rc=0
timeout 30s "$TMP/bin/sensd6negabself" "$MODE" \
  "$TMP/свідки/02.sens" "$TMP/occupied-link.elf" \
  >"$TMP/symlink.out" 2>"$TMP/symlink.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/occupied-link.elf"
test ! -e "$TMP/missing.elf"
timeout 30s "$TMP/bin/sensd6negabself" "$MODE" \
  "$TMP/свідки/08.sens" "$TMP/repeated.elf" >/dev/null
cmp "$TMP/repeated.elf" "$TMP/08.elf"
timeout 5s "$TMP/repeated.elf" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/свідки/08.expected.sens"
echo "Д6-ЗНАК-МОДУЛЬ-ELF-ГОТОВО machine=$NATIVE d24=$WIDE oracle=$ORACLE_PASS negatives=$NEG no-clobber=2 bytes-repeat=1 energy=NOT-MEASURED"
# Усі .ppu/.o/ELF і фізичні свідки належать $TMP і очищаються EXIT.
# Питання: звідки походять D6 ключі? Де машина обчислює NEG/ABS?
# Чому D12→D24 не звужується? Хто підтверджує semantic parity?
