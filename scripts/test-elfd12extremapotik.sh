#!/usr/bin/env bash
# G6.114 — same ELF64 min/max reused across dynamic signed W12 stdin frames.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
T=$(mktemp -d)
fault(){
  local rc=$?
  echo "G6.114-ЗБІЙ рядок=$1 код=$rc" >&2
  for f in "$T"/*.err "$T"/*.log;do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 20 "$f" >&2; }
  done
  exit "$rc"
}
trap 'fault "$LINENO"' ERR
trap 'rm -rf "$T"' EXIT
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]]
for tool in git fpc timeout cmp readelf objdump grep python3 sha256sum;do
  command -v "$tool" >/dev/null || { echo "немає $tool" >&2;exit 127; }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(semantic-identity . (exact-domain exact-width exact-bit-word admitted-law))' \
  external/sens/contracts/language-contract-12.lisp
for key in '110101 (ук найменше) (укр найменше)' \
           '110111 (ук найбільше) (укр найбільше)';do
  git -C external/sens show "$PIN:lib/domains/d6.lisp" |
    grep -F "($key" >/dev/null
done
ORACLE=${SENS_ORACLE_BIN:-}
if [[ -n "$ORACLE" ]];then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
mkdir -p "$T/bin" "$T/units" "$T/frames"
for row in \
  'src/sensd12extremapotikelf.lpr sensd12extremapotikelf' \
  'scripts/test-elfd12extremapotik-fixtures.pas test-elfd12extremapotik-fixtures' \
  'src/senschyslo.lpr senschyslo';do
  read -r src exe <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$T/units" -FE"$T/bin" "-o$exe" \
    "$ROOT/$src" >"$T/$exe.log" 2>&1 || { cat "$T/$exe.log" >&2;exit 1; }
  test -x "$T/bin/$exe"
done
timeout 30s "$T/bin/test-elfd12extremapotik-fixtures" "$T/frames" \
  >"$T/cases.tsv" 2>"$T/fixtures.err"
grep -Fq 'G6.114-FIXTURES-OK pairs=18 negatives=12' "$T/fixtures.err"
test "$(wc -l < "$T/cases.tsv")" -eq 18
for kind in min max;do
  if [[ "$kind" == min ]];then mode=--D6-110101;op=cmovg;name='найменше'
  else mode=--D6-110111;op=cmovl;name='найбільше';fi
  elf="$T/$kind.elf"
  timeout 15s "$T/bin/sensd12extremapotikelf" "$mode" "$elf" \
    >"$T/$kind.build" 2>"$T/$kind.err"
  test ! -s "$T/$kind.err"
  grep -Fq 'signed-CMOV=T5M' "$T/$kind.build"
  test -x "$elf"
  readelf -h "$elf" >"$T/$kind.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$T/$kind.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$T/$kind.header"
  python3 - "$elf" "$op" <<'PY'
from pathlib import Path
import sys
b=Path(sys.argv[1]).read_bytes()
assert b[:4]==b'\x7fELF'
code=b[120:600]
old=bytes.fromhex('44 89 c0 44 01 c8')
new=bytes.fromhex('44 89 c0 44 39 c8 41 0f')
expected=new+(b'\x4f' if sys.argv[2]=='cmovg' else b'\x4c')+b'\xc1'
assert old not in code, 'old ADD instruction still present'
assert code.count(expected)==1, 'expected signed CMP+CMOV missing or repeated'
assert b'\x48\x83\xf8\x06\x0f\x85' in code, 'lost exact frame gate'
assert b'\x0f\xb6\x04\x06' in code, 'lost physical T5M decoder'
assert b'\x8a\x04\x06' in code, 'lost physical T5M writer'
assert expected+b'\x25\xff\x0f\x00\x00\x89\xc3'+b'\x90'*18 in code, 'bad fixed-width splice'
PY
  dd if="$elf" of="$T/$kind.machine" bs=1 skip=120 count=410 status=none
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$T/$kind.machine" >"$T/$kind.dis"
  grep -Eiq "cmp[[:space:]]+eax,r9d" "$T/$kind.dis"
  grep -Eiq "$op[[:space:]]+eax,r9d" "$T/$kind.dis"
  HASH=$(sha256sum "$elf" | cut -d' ' -f1)
  P=0;C=0
  while IFS=$'\t' read -r tag left right;do
    timeout 10s "$elf" <"$T/frames/$tag.frame" \
      >"$T/$kind-$tag.sens" 2>"$T/$kind-$tag.machine.err"
    test ! -s "$T/$kind-$tag.machine.err"
    cmp "$T/frames/$tag-$kind.sens" "$T/$kind-$tag.sens"
    test "$(wc -c < "$T/$kind-$tag.sens")" -eq 3
    test "$(sha256sum "$elf" | cut -d' ' -f1)" = "$HASH"
    if [[ -n "$ORACLE" ]];then
      timeout 10s "$T/bin/senschyslo" --в-укр D12 \
        "$T/$kind-$tag.sens" >"$T/$kind-$tag.ukr"
      printf '(%s %s %s)\n' "$name" "$left" "$right" >"$T/$kind-$tag.lisp"
      timeout 60s "$ORACLE" "$T/$kind-$tag.lisp" \
        >"$T/$kind-$tag.oracle" 2>"$T/$kind-$tag.oracle.err"
      test ! -s "$T/$kind-$tag.oracle.err"
      cmp "$T/$kind-$tag.oracle" "$T/$kind-$tag.ukr"
      C=$((C+1))
    fi
    P=$((P+1))
  done <"$T/cases.tsv"
  test "$P" -eq 18
  if [[ -n "$ORACLE" ]];then test "$C" -eq 18;fi
  # Invalid host frames must yield exit(2), no partial stdout.
  N=0
  for bad in bad-empty bad-short1 bad-short5 bad-extra bad-newline \
    bad-first bad-second bad-third bad-last bad-projection bad-d1 bad-d24;do
    rc=0
    timeout 10s "$elf" <"$T/frames/$bad.frame" \
      >"$T/$kind-$bad.out" 2>"$T/$kind-$bad.err" || rc=$?
    test "$rc" -eq 2 && test ! -s "$T/$kind-$bad.out"
    grep -Fq 'Д12-ПОТІК-ВІДМОВА:' "$T/$kind-$bad.err"
    N=$((N+1))
  done
  test "$N" -eq 12
  timeout 15s "$T/bin/sensd12extremapotikelf" "$mode" "$T/$kind-again.elf" \
    >"$T/$kind.again.out"
  cmp "$elf" "$T/$kind-again.elf"
  cp "$elf" "$T/$kind-protected.elf"
  rc=0
  timeout 15s "$T/bin/sensd12extremapotikelf" "$mode" \
    "$T/$kind-protected.elf" >"$T/$kind-blocked.out" \
    2>"$T/$kind-blocked.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$T/$kind-blocked.out"
  cmp "$elf" "$T/$kind-protected.elf"
  ln -s "$T/no-target.elf" "$T/$kind-link.elf"
  rc=0
  timeout 15s "$T/bin/sensd12extremapotikelf" "$mode" \
    "$T/$kind-link.elf" >"$T/$kind-link.out" \
    2>"$T/$kind-link.err" || rc=$?
  test "$rc" -eq 2 && test -L "$T/$kind-link.elf" && test ! -e "$T/no-target.elf"
  echo "G6.114-PROFILE-OK profile=$kind native=$P oracle=$C negatives=$N exact-T5M=yes reproducible=yes"
done
rc=0
timeout 10s "$T/bin/sensd12extremapotikelf" --мовна-назва \
  "$T/invalid.elf" >"$T/mode.out" 2>"$T/mode.err" || rc=$?
test "$rc" -eq 2 && test ! -e "$T/invalid.elf"
TOTAL_ORACLE=0
if [[ -n "$ORACLE" ]];then TOTAL_ORACLE=36;fi
echo "G6.114-D6-STREAM-OK ELF=2 physical=36 oracle=$TOTAL_ORACLE negatives=24 no-clobber=yes energy=НЕ-ВИМІРЯНО"
