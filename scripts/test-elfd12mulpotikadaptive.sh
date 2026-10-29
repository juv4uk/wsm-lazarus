#!/usr/bin/env bash
# G6.137 — перевірити один адаптивний IMUL ELF на exact D12/D24.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || {
 echo 'АДАПТИВНЕ-IMUL-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for t in timeout fpc git cmp sha256sum python3 readelf objdump grep mktemp; do
 command -v "$t" >/dev/null || {
  echo "АДАПТИВНЕ-IMUL-БЛОК: немає $t" >&2; exit 127;
 }
done
timeout 180s bash ./scripts/sync-authority.sh
timeout 120s bash ./scripts/check-pin.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(10110 (ук помножити) (укр помножити)' external/sens/lib/domains/d5.lisp
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ -n "$ORACLE" ]]; then
 test -x "$ORACLE"
 test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc!=0)); then
 echo "АДАПТИВНЕ-IMUL-ПРОВАЛ code=$rc" >&2
 for f in "$TMP"/*.log "$TMP"/*.err; do
  [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 40 "$f" >&2; }
 done
fi
rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/ucli" "$TMP/ugen" "$TMP/physical"
for row in \
 'src/sensd12mulpotikadaptive.lpr sensd12mulpotikadaptive ucli' \
 'scripts/test-elfd12mulpotik.pas test-elfd12mulpotik ugen'; do
 read -r source prog units <<<"$row"
 timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" "-o$prog" \
  "$ROOT/$source" >"$TMP/$prog.build.log" 2>&1 || {
   cat "$TMP/$prog.build.log" >&2; exit 1;
  }
 test -x "$TMP/bin/$prog"
done
timeout 30s "$TMP/bin/test-elfd12mulpotik" "$TMP/physical" \
 >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Fq 'positive=26 d24=8 negatives=12' "$TMP/generator.log"
test "$(wc -l < "$TMP/physical/cases.tsv")" -eq 26
test "$(wc -l < "$TMP/physical/overflows.tsv")" -eq 8
MODE=--зібрати-адаптивне-D5-множення
ELF="$TMP/адаптивне-множення.elf"
timeout 60s "$TMP/bin/sensd12mulpotikadaptive" "$MODE" \
 "$TMP/physical/03.sens" "$ELF" \
 >"$TMP/compile.log" 2>"$TMP/compile.err"
test -x "$ELF" && test ! -s "$TMP/compile.err"
grep -Fq 'stdin=2xT5M-D12 stdout=T5M-D12-or-D24' "$TMP/compile.log"
timeout 60s "$TMP/bin/sensd12mulpotikadaptive" "$MODE" \
 "$TMP/physical/04.sens" "$TMP/again.elf" \
 >"$TMP/recompile.log" 2>"$TMP/recompile.err"
test ! -s "$TMP/recompile.err"
cmp "$ELF" "$TMP/again.elf"
readelf -h "$ELF" >"$TMP/elf-header.log"
grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/elf-header.log"
python3 - "$ELF" <<'PY'
import struct,sys
from pathlib import Path
data=Path(sys.argv[1]).read_bytes()
assert data[:4]==b'\x7fELF'
assert struct.unpack_from('<Q',data,96)[0]==len(data)
assert struct.unpack_from('<Q',data,104)[0]==len(data)
assert struct.unpack_from('<Q',data,24)[0]==120
head=b'\x44\x89\xc0\x41\x0f\xaf\xc1\x89\xc3'
assert data.count(head)==1, 'не знайдено унікальний новий signed IMUL'
assert data.count(b'\x81\xe3\xff\x0f\x00\x00')>=1
assert data.count(b'\x81\xe3\xff\xff\xff\x00')>=1
assert data.count(b'\x48\x83\xf8\x05\x0f\x85')==1
print('АДАПТИВНЕ-IMUL-МАШИНА-ГОТОВО signed-IMUL=так output=D12/D24')
PY
dd if="$ELF" of="$TMP/code" bs=1 skip=120 count=1600 status=none
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" \
 >"$TMP/disassembly.log"
grep -Eq 'imul[[:space:]]+eax,r9d' "$TMP/disassembly.log"
HASH="$(sha256sum "$ELF" | cut -d' ' -f1)"
SMALL=0;WIDE=0;ORA=0
while IFS=$'\t' read -r label left right expected; do
 test -n "$label"
 for attempt in 1 2; do
  timeout 6s "$ELF" <"$TMP/physical/$label.frame" \
    >"$TMP/$label.$attempt.actual.sens" \
    2>"$TMP/$label.$attempt.stderr"
  test ! -s "$TMP/$label.$attempt.stderr"
  cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.$attempt.actual.sens"
  test "$(wc -c < "$TMP/$label.$attempt.actual.sens")" -eq 3
 done
 cmp "$TMP/$label.1.actual.sens" "$TMP/$label.2.actual.sens"
 if [[ -n "$ORACLE" ]]; then
  timeout 60s "$ORACLE" "$TMP/physical/$label.sens" \
    >"$TMP/$label.oracle.log" 2>"$TMP/$label.oracle.err"
  test ! -s "$TMP/$label.oracle.err"
  printf '%s\n' "$expected" >"$TMP/$label.expected-oracle"
  cmp "$TMP/$label.expected-oracle" "$TMP/$label.oracle.log"
  ORA=$((ORA+1))
 fi
 SMALL=$((SMALL+1))
done <"$TMP/physical/cases.tsv"
test "$SMALL" -eq 26
while IFS=$'\t' read -r label left right expected; do
 test -n "$label"
 for attempt in 1 2; do
  timeout 6s "$ELF" <"$TMP/physical/$label.frame" \
    >"$TMP/$label.$attempt.actual.sens" \
    2>"$TMP/$label.$attempt.stderr"
  test ! -s "$TMP/$label.$attempt.stderr"
  cmp "$TMP/physical/$label.expected-d24.sens" "$TMP/$label.$attempt.actual.sens"
  test "$(wc -c < "$TMP/$label.$attempt.actual.sens")" -eq 5
 done
 cmp "$TMP/$label.1.actual.sens" "$TMP/$label.2.actual.sens"
 if [[ -n "$ORACLE" ]]; then
  timeout 60s "$ORACLE" "$TMP/physical/$label.sens" \
    >"$TMP/$label.oracle.log" 2>"$TMP/$label.oracle.err"
  test ! -s "$TMP/$label.oracle.err"
  printf '%s\n' "$expected" >"$TMP/$label.expected-oracle"
  cmp "$TMP/$label.expected-oracle" "$TMP/$label.oracle.log"
  ORA=$((ORA+1))
 fi
 WIDE=$((WIDE+1))
done <"$TMP/physical/overflows.tsv"
test "$WIDE" -eq 8
test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
NEG=0
for bad in empty short1 short5 extra newline invalid243 \
 badfirst badsecond badthird badlast projection d1; do
 rc=0
 timeout 6s "$ELF" <"$TMP/physical/$bad.frame" \
  >"$TMP/$bad.actual.sens" 2>"$TMP/$bad.err" || rc=$?
 test "$rc" -eq 2 && test ! -s "$TMP/$bad.actual.sens"
 grep -Fq 'ВІДМОВА' "$TMP/$bad.err"
 NEG=$((NEG+1))
done
test "$NEG" -eq 12
# fragmented stdin: donor exact EOF handling retained.
python3 - "$TMP/physical/overflow1.frame" <<'PY' | \
 timeout 6s "$ELF" >"$TMP/fragment.sens"
import sys,time
raw=open(sys.argv[1],'rb').read()
assert len(raw)==6
sys.stdout.buffer.write(raw[:2]);sys.stdout.buffer.flush()
time.sleep(0.03)
sys.stdout.buffer.write(raw[2:]);sys.stdout.buffer.flush()
PY
cmp "$TMP/physical/overflow1.expected-d24.sens" "$TMP/fragment.sens"
REJECT=0
for bad in wrong-d5 wrong-d6 d24-operand missing-arg \
 extra-arg bad-t5m empty; do
 rc=0
 timeout 60s "$TMP/bin/sensd12mulpotikadaptive" "$MODE" \
  "$TMP/physical/$bad.sens" "$TMP/reject-$REJECT.elf" \
  >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
 test "$rc" -eq 2 && test ! -s "$TMP/reject.out"
 test ! -e "$TMP/reject-$REJECT.elf"
 grep -Fq 'АДАПТИВНЕ-D5-IMUL-ВІДМОВА' "$TMP/reject.err"
 REJECT=$((REJECT+1))
done
test "$REJECT" -eq 7
rc=0
"$TMP/bin/sensd12mulpotikadaptive" "$MODE" \
 "$TMP/physical/03.sens" "$ELF" >"$TMP/clobber.out" \
 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/clobber.out"
test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
timeout 6s "$ELF" <"$TMP/physical/01.frame" >"$TMP/recovered.sens"
cmp "$TMP/physical/01.expected.sens" "$TMP/recovered.sens"
timeout 20s bash scripts/check-no-lcl.sh
echo "АДАПТИВНЕ-IMUL-ГОТОВО small=$SMALL wide=$WIDE real-elf=$((2*(SMALL+WIDE))) oracle=$ORA negative=$NEG anchors=$REJECT fragmented=yes energy=NOT-MEASURED"
