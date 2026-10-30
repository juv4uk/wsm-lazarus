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
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]]
for tool in git fpc timeout cmp readelf objdump grep python3 sha256sum strace;do
  command -v "$tool" >/dev/null || { echo "немає $tool" >&2;exit 127; }
done
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
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
assert b'\x48\x83\xf8\x06\x0f\x85' in code, 'lost donor frame gate'
assert code.startswith(bytes.fromhex('48 83 ec 20 45 31 d2')), 'missing bounded loop'
assert b'\x4c\x01\xd6\xba\x06\x00\x00\x00' in code, 'missing offset read'
assert b'\x48\x8d\x74\x24\x06\xba\x01\x00\x00\x00' in code, 'missing EOF probe'
assert code.count(bytes.fromhex('48 83 f8 fc 0f 84'))==2, 'missing 2 dedicated EINTR retries'
assert b'\x0f\xb6\x04\x06' in code, 'lost physical T5M decoder'
assert b'\x8a\x04\x06' in code, 'lost physical T5M writer'
assert expected+b'\x25\xff\x0f\x00\x00\x89\xc3'+b'\x90'*18 in code, 'bad fixed-width splice'
PY
  dd if="$elf" of="$T/$kind.machine" bs=1 skip=120 count=410 status=none
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$T/$kind.machine" >"$T/$kind.dis"
  grep -Eiq "cmp[[:space:]]+eax,r9d" "$T/$kind.dis"
  grep -Eiq "$op[[:space:]]+eax,r9d" "$T/$kind.dis"
  # G6.121: real pipe writes with delayed fragments (not a fake static frame).
  # A complete 6-byte frame MUST NOT finish before stdin EOF, because a
  # seventh byte can still arrive. Reject incomplete/extra with zero stdout.
  python3 - "$elf" "$T/frames/07.frame" "$T/frames/07-$kind.sens" <<'PY'
from pathlib import Path
import subprocess, select, sys, time
elf,frame_path,expected_path=sys.argv[1:]
frame=Path(frame_path).read_bytes()
expected=Path(expected_path).read_bytes()
assert len(frame)==6 and len(expected)==3

def run(chunks,good,extra=b''):
    p=subprocess.Popen([elf],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE,bufsize=0)
    try:
        i=0
        for count in chunks:
            part=frame[i:i+count]
            assert len(part)==count
            p.stdin.write(part)
            p.stdin.flush()
            i+=count
            time.sleep(0.025)  # ensure the Linux reader receives a short read
            assert p.poll() is None, 'ELF exited before EOF'
            assert not select.select([p.stdout],[],[],0)[0], 'partial stdout'
        if extra:
            assert i==6
            p.stdin.write(extra)
            p.stdin.flush()
            time.sleep(0.015)
        p.stdin.close()
        p.stdin=None
        out,err=p.communicate(timeout=8)
        assert p.returncode==(0 if good else 2), (chunks,extra,p.returncode,err)
        if good:
            assert out==expected and not err, (chunks,out,err)
        else:
            assert not out and b'\xd0' in err, (chunks,out,err)
    finally:
        if p.poll() is None:
            p.kill()
            p.communicate(timeout=3)

for chunks in ((1,1,1,1,1,1),(2,4),(5,1),(6,)):
    run(chunks,True)
run((6,),False,b'\xff')
run((5,),False)
run((),False)
print('G6.121-FRAGMENTED-PIPE-OK profile='+Path(elf).stem+
      ' positives=4 negatives=3 no-output-before-EOF=yes')
PY
  # G6.127 — actual Linux ptrace syscall fault injection.
  # Read EINTR=-4 must retry without losing the already admitted W12 frame.
  # when=1 interrupts first frame read; when=2 interrupts EOF probe.
  # Non-EINTR EIO must remain fail-closed (exit2, zero partial stdout).
  for injected_call in 1 2;do
    timeout 15s strace -qq -o "$T/$kind-eintr-$injected_call.trace" \
      -e "inject=read:error=EINTR:when=$injected_call" -- "$elf" \
      <"$T/frames/07.frame" \
      >"$T/$kind-eintr-$injected_call.sens" \
      2>"$T/$kind-eintr-$injected_call.err"
    test ! -s "$T/$kind-eintr-$injected_call.err"
    grep -Fq 'EINTR (Interrupted system call)' \
      "$T/$kind-eintr-$injected_call.trace"
    cmp "$T/frames/07-$kind.sens" "$T/$kind-eintr-$injected_call.sens"
  done
  for injected_call in 1 2;do
    code=0
    timeout 15s strace -qq -o "$T/$kind-eio-$injected_call.trace" \
      -e "inject=read:error=EIO:when=$injected_call" -- "$elf" \
      <"$T/frames/07.frame" \
      >"$T/$kind-eio-$injected_call.sens" \
      2>"$T/$kind-eio-$injected_call.err" || code=$?
    test "$code" -eq 2
    grep -Fq 'EIO (Input/output error)' "$T/$kind-eio-$injected_call.trace"
    grep -Fq 'Д12-ПОТІК-ВІДМОВА:' "$T/$kind-eio-$injected_call.err"
    test ! -s "$T/$kind-eio-$injected_call.sens"
  done
  echo "G6.127-SYSCALL-OK profile=$kind EINTR=2 EIO=2 physical=T5M retry=CPU"
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
# Shared baseline gate stays MANDATORY and fail-closed. Run after actual
# machine/FPC checks so unrelated main changes cannot mask hardware evidence.
./scripts/check-no-lcl.sh
echo "G6.127-D6-STREAM-OK ELF=2 physical=36 oracle=$TOTAL_ORACLE negatives=24 fragmented=8 truncated-excess=6 EINTR=4 EIO=4 preEOF=0 no-clobber=yes energy=НЕ-ВИМІРЯНО"
