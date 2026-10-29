#!/usr/bin/env bash
# G6.134 — справжній один x86-64 IMUL ELF64 із двома динамічними D12.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || {
  echo 'Д5-IMUL-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in timeout fpc git cmp grep readelf objdump python3 mktemp sha256sum; do
  command -v "$tool" >/dev/null || {
    echo "Д5-IMUL-БЛОК: бракує $tool" >&2; exit 127;
  }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(10110 (ук помножити) (укр помножити)' external/sens/lib/domains/d5.lisp
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP="$(mktemp -d)"
cleanup() {
  local rc=$?
  if ((rc!=0));then
    echo "Д5-IMUL-ПРОВАЛ: код=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 35 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units-cli" "$TMP/units-fixtures" "$TMP/physical"
for row in \
 'src/sensd12mulpotikelf.lpr sensd12mulpotikelf units-cli' \
 'scripts/test-elfd12mulpotik.pas test-elfd12mulpotik units-fixtures'; do
  read -r source exe units <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$source" >"$TMP/$exe.build.log" 2>&1 || {
      cat "$TMP/$exe.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$exe"
done
HEAPTRC="log=$TMP/generator.heap" timeout 30s \
  "$TMP/bin/test-elfd12mulpotik" "$TMP/physical" \
  >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Fq 'Д5-IMUL-СВІДКИ-ГОТОВО positive=26 d24=8 negatives=12' \
  "$TMP/generator.log"
test "$(wc -l < "$TMP/physical/cases.tsv")" -eq 26
test "$(wc -l < "$TMP/physical/overflows.tsv")" -eq 8
MODE=--зібрати-D5-множення-потік
ELF="$TMP/дванадцятибітне-множення.elf"
HEAPTRC="log=$TMP/compiler.heap" timeout 40s \
 "$TMP/bin/sensd12mulpotikelf" "$MODE" "$TMP/physical/03.sens" "$ELF" \
 >"$TMP/compile.log" 2>"$TMP/compile.err"
test -x "$ELF" && test ! -s "$TMP/compile.err"
grep -Fq 'machine=IMUL_EAX_R9D' "$TMP/compile.log"
HEAPTRC="log=$TMP/recompile.heap" timeout 40s \
 "$TMP/bin/sensd12mulpotikelf" "$MODE" "$TMP/physical/04.sens" \
 "$TMP/ідентичний.elf" >"$TMP/recompile.log" 2>"$TMP/recompile.err"
test ! -s "$TMP/recompile.err"
cmp "$ELF" "$TMP/ідентичний.elf"
readelf -h "$ELF" >"$TMP/elf-header.log"
grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/elf-header.log"
python3 - "$ELF" <<'PY'
from pathlib import Path
import struct,sys
raw=Path(sys.argv[1]).read_bytes()
assert raw[:4]==b'\x7fELF'
needle=b'\x44\x89\xc0\x41\x0f\xaf\xc1\x3d\xff\x07\x00\x00'
assert raw.count(needle)==1
p=raw.index(needle)
assert raw[p+12:p+14]==b'\x0f\x8f'
assert raw[p+18:p+23]==b'\x3d\x00\xf8\xff\xff'
assert raw[p+23:p+25]==b'\x0f\x8c'
assert raw[p+29:p+35]==b'\x25\xff\x0f\x00\x00\x93'
g=struct.unpack('<i',raw[p+14:p+18])[0]
l=struct.unpack('<i',raw[p+25:p+29])[0]
assert p+18+g==p+29+l, 'JG/JL не ведуть в один fail-closed блок'
target=p+18+g
assert raw[target:target+5]==b'\xb8\x01\x00\x00\x00'
assert raw[120:124]!=b'\x44\x89\xc0\x41' # перед IMUL є exact-frame reader
print('Д5-IMUL-JCC-ГОТОВО equal-reject-targets=так')
PY
dd if="$ELF" of="$TMP/machine" bs=1 skip=120 count=600 status=none
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/machine" \
 >"$TMP/disassembly.log"
grep -Eq 'imul[[:space:]]+eax,r9d' "$TMP/disassembly.log"
grep -Eq 'xchg[[:space:]]+(eax,ebx|ebx,eax)' "$TMP/disassembly.log"
HASH="$(sha256sum "$ELF" | cut -d' ' -f1)"
PASS=0;ORACLE_PASS=0
while IFS=$'\t' read -r label left right expected; do
  test -n "$label"
  for attempt in 1 2; do
    timeout 5s "$ELF" <"$TMP/physical/$label.frame" \
      >"$TMP/$label.$attempt.actual.sens" \
      2>"$TMP/$label.$attempt.machine.err"
    test ! -s "$TMP/$label.$attempt.machine.err"
    cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.$attempt.actual.sens"
    test "$(wc -c < "$TMP/$label.$attempt.actual.sens")" -eq 3
    test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
  done
  cmp "$TMP/$label.1.actual.sens" "$TMP/$label.2.actual.sens"
  if [[ -n "$ORACLE" ]]; then
    timeout 60s "$ORACLE" "$TMP/physical/$label.sens" \
     >"$TMP/$label.oracle.log" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.expected.oracle"
    cmp "$TMP/$label.oracle.log" "$TMP/$label.expected.oracle" || {
      echo "Д5-IMUL-ORACLE-НЕЗБІГ: $label $left $right expected=$expected" >&2
      exit 1
    }
    ORACLE_PASS=$((ORACLE_PASS+1))
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 26
if [[ -n "$ORACLE" ]]; then test "$ORACLE_PASS" -eq 26; fi
# Host read(0) має витримувати фрагментацію та вимагати EOF.
python3 - "$TMP/physical/03.frame" <<'PY' | timeout 5s "$ELF" >"$TMP/fragment.sens"
import sys,time
data=open(sys.argv[1],'rb').read()
assert len(data)==6
sys.stdout.buffer.write(data[:2]);sys.stdout.buffer.flush()
time.sleep(0.05)
sys.stdout.buffer.write(data[2:]);sys.stdout.buffer.flush()
PY
cmp "$TMP/fragment.sens" "$TMP/physical/03.expected.sens"
OVER=0;WIDE_ORACLE=0
while IFS=$'\t' read -r label left right expected; do
  rc=0
  timeout 5s "$ELF" <"$TMP/physical/$label.frame" \
    >"$TMP/$label.rejected.sens" 2>"$TMP/$label.rejected.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/$label.rejected.sens"
  grep -Fq 'ВІДМОВА' "$TMP/$label.rejected.err"
  test -s "$TMP/physical/$label.expected-d24.sens"
  if [[ -n "$ORACLE" ]]; then
    timeout 60s "$ORACLE" "$TMP/physical/$label.sens" \
     >"$TMP/$label.wideoracle.log" 2>"$TMP/$label.wideoracle.err"
    test ! -s "$TMP/$label.wideoracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.wideoracle.expected"
    cmp "$TMP/$label.wideoracle.log" "$TMP/$label.wideoracle.expected"
    WIDE_ORACLE=$((WIDE_ORACLE+1))
  fi
  OVER=$((OVER+1))
done <"$TMP/physical/overflows.tsv"
test "$OVER" -eq 8
NEG=0
for bad in empty short1 short5 extra newline invalid243 badfirst \
 badsecond badthird badlast projection d1; do
  rc=0
  timeout 5s "$ELF" <"$TMP/physical/$bad.frame" \
    >"$TMP/$bad.bad.sens" 2>"$TMP/$bad.bad.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/$bad.bad.sens"
  grep -Fq 'ВІДМОВА' "$TMP/$bad.bad.err"
  NEG=$((NEG+1))
done
test "$NEG" -eq 12
ANCHOR_NEG=0
for bad in wrong-d5 wrong-d6 d24-operand missing-arg extra-arg bad-t5m empty; do
  rc=0
  HEAPTRC="log=$TMP/reject.heap" timeout 30s \
   "$TMP/bin/sensd12mulpotikelf" "$MODE" \
   "$TMP/physical/$bad.sens" "$TMP/reject-$ANCHOR_NEG.elf" \
   >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/reject.out" && test ! -e "$TMP/reject-$ANCHOR_NEG.elf"
  grep -Fq 'Д5-МНОЖЕННЯ-ПОТІК-ВІДМОВА' "$TMP/reject.err"
  ANCHOR_NEG=$((ANCHOR_NEG+1))
done
test "$ANCHOR_NEG" -eq 7
printf '(помножити 7 3)\n' >"$TMP/physical/projection.lisp"
rc=0
"$TMP/bin/sensd12mulpotikelf" "$MODE" "$TMP/physical/projection.lisp" \
 "$TMP/projection.elf" >"$TMP/projection.out" 2>"$TMP/projection.err" || rc=$?
test "$rc" -eq 2 && test ! -e "$TMP/projection.elf"
rc=0
"$TMP/bin/sensd12mulpotikelf" "$MODE" "$TMP/physical/03.sens" \
 "$ELF" >"$TMP/clobber.out" 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/clobber.out"
test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
ln -s "$TMP/absent.elf" "$TMP/dangling.elf"
rc=0
"$TMP/bin/sensd12mulpotikelf" "$MODE" "$TMP/physical/03.sens" \
 "$TMP/dangling.elf" >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test ! -e "$TMP/absent.elf"
test -L "$TMP/dangling.elf"
timeout 5s "$ELF" <"$TMP/physical/26.frame" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/physical/26.expected.sens"
for label in generator compiler recompile; do
  test -s "$TMP/$label.heap"
  grep -Fq '0 unfreed memory blocks' "$TMP/$label.heap"
done
timeout 20s bash scripts/check-no-lcl.sh
echo "Д5-IMUL-ПОТІК-ГОТОВО positive=$PASS d24-reject=$OVER bad-frames=$NEG bad-anchors=$ANCHOR_NEG oracle=$ORACLE_PASS wide-oracle=$WIDE_ORACLE fragmented=yes energy=NOT-MEASURED"
