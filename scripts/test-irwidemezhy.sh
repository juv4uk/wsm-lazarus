#!/usr/bin/env bash
# G6.144 — real FPC / exact D2/T5M → pinned WideIR → existing SETLE/SETGE.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
 echo 'D6-МЕЖІ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for t in timeout fpc git cmp readelf objdump grep mktemp python3 sha256sum; do
 command -v "$t" >/dev/null || {
  echo "D6-МЕЖІ-БЛОК: бракує $t" >&2; exit 127;
 }
done
timeout 180s bash ./scripts/sync-authority.sh
timeout 120s bash ./scripts/check-pin.sh
timeout 30s bash ./scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show HEAD:lib/domains/d6.lisp | grep -Fq '(110100 (ук не-більше?)' 
git -C external/sens show HEAD:lib/domains/d6.lisp | grep -Fq '(110110 (ук не-менше?)'
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ -n "$ORACLE" ]]; then
 test -x "$ORACLE" && test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc!=0)); then
 echo "D6-МЕЖІ-ПРОВАЛ: status=$rc" >&2
 for f in "$TMP"/*.log "$TMP"/*.err; do
  [[ ! -s "$f" ]] || { echo "-- $f" >&2; tail -n 40 "$f" >&2; }
 done
fi
rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/u1" "$TMP/u2" "$TMP/u3" "$TMP/physical"
for row in \
 'src/senswidemezhyelf.lpr senswidemezhyelf u1' \
 'src/sensd6mezhyelf.lpr sensd6mezhyelf u2' \
 'scripts/test-elfd12bilsh.pas test-elfd12bilsh u3'; do
 read -r source binary units <<<"$row"
 timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
   -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" "-o$binary" \
   "$ROOT/$source" >"$TMP/$binary.build.log" 2>&1 || {
    cat "$TMP/$binary.build.log" >&2; exit 1;
   }
 test -x "$TMP/bin/$binary"
done
mkdir -p "$TMP/u4"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
 -Fu"$ROOT/src" -FU"$TMP/u4" -FE"$TMP/bin" -otest-irwidemezhy \
 "$ROOT/scripts/test-irwidemezhy.pas" >"$TMP/physical.build.log" 2>&1 || {
 cat "$TMP/physical.build.log" >&2; exit 1;
}
test -x "$TMP/bin/test-irwidemezhy"
timeout 30s "$TMP/bin/test-elfd12bilsh" "$TMP/physical" \
 >"$TMP/matrix.tsv" 2>"$TMP/base.err"
test "$(wc -l < "$TMP/matrix.tsv")" -eq 12
timeout 30s "$TMP/bin/test-irwidemezhy" "$TMP/physical" \
 >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Fq 'D6-MEZHY-FIXTURES-OK: 24' "$TMP/generator.log"
test ! -s "$TMP/generator.err"
MODE=--скомпілювати-D6-межі
COUNT=0
ORACLE_COUNT=0
while IFS=$'\t' read -r label left right old_answer; do
 test -n "$label"
 for opcode in 110100 110110; do
  if [[ "$opcode" == 110100 ]]; then
    if (( left<=right )); then expected=1; else expected=0; fi
    machine=0f9ec0
  else
    if (( left>=right )); then expected=1; else expected=0; fi
    machine=0f9dc0
  fi
  if [[ "$expected" == 1 ]]; then expfile="$TMP/physical/03-expected.sens";
  else expfile="$TMP/physical/01-expected.sens"; fi
  elf="$TMP/$label-$opcode.elf"
  timeout 20s "$TMP/bin/senswidemezhyelf" "$MODE" \
   "$TMP/physical/$label-$opcode.sens" "$elf" \
   >"$TMP/$label-$opcode.compile.log" 2>"$TMP/$label-$opcode.compile.err"
  test -x "$elf"
  test ! -s "$TMP/$label-$opcode.compile.err"
  grep -Fq 'machine=CMP/SETLE/SETGE stdout=T5M-D1' \
   "$TMP/$label-$opcode.compile.log"
  timeout 5s "$elf" >"$TMP/$label-$opcode.actual.sens" \
   2>"$TMP/$label-$opcode.machine.err"
  test ! -s "$TMP/$label-$opcode.machine.err"
  cmp "$expfile" "$TMP/$label-$opcode.actual.sens"
  test "$(wc -c < "$TMP/$label-$opcode.actual.sens")" -eq 1
  readelf -h "$elf" | grep -Eq 'Type:.*DYN'
  python3 - "$elf" "$machine" <<'PY'
from pathlib import Path
import struct,sys
data=Path(sys.argv[1]).read_bytes()
assert data[:4]==b'\x7fELF'
assert struct.unpack_from('<Q',data,96)[0]==len(data)
assert struct.unpack_from('<Q',data,104)[0]==len(data)
assert bytes.fromhex(sys.argv[2]) in data[120:165]
PY
  timeout 20s "$TMP/bin/sensd6mezhyelf" "--D6-$opcode" \
    "$TMP/physical/$label-l.sens" "$TMP/physical/$label-r.sens" \
    "$TMP/$label-$opcode.donor.elf" \
    >"$TMP/$label-$opcode.donor.log" 2>"$TMP/$label-$opcode.donor.err"
  cmp "$elf" "$TMP/$label-$opcode.donor.elf"
  timeout 20s "$TMP/bin/senswidemezhyelf" "$MODE" \
    "$TMP/physical/$label-$opcode.sens" "$TMP/$label-$opcode.again.elf" \
    >"$TMP/$label-$opcode.again.log" 2>"$TMP/$label-$opcode.again.err"
  cmp "$elf" "$TMP/$label-$opcode.again.elf"
  if [[ -n "$ORACLE" ]]; then
    timeout 60s "$ORACLE" "$TMP/physical/$label-$opcode.sens" \
      >"$TMP/$label-$opcode.oracle.log" 2>"$TMP/$label-$opcode.oracle.err"
    test ! -s "$TMP/$label-$opcode.oracle.err"
    python3 - "$TMP/$label-$opcode.oracle.log" "$expected" <<'PY'
import sys
s=open(sys.argv[1],encoding='utf-8').read().strip()
if s.startswith('sens[укр]> '): s=s[len('sens[укр]> '):].strip()
true={'1','ТАК','(т а к)'}
false={'0','НІ','(н і)'}
assert s in (true if sys.argv[2]=='1' else false),repr(s)
PY
    ORACLE_COUNT=$((ORACLE_COUNT+1))
  fi
  COUNT=$((COUNT+1))
 done
done < "$TMP/matrix.tsv"
test "$COUNT" -eq 24
if [[ -n "$ORACLE" ]]; then test "$ORACLE_COUNT" -eq 24; fi
NEG=0
reject() {
 local path="$1" rc=0
 timeout 20s "$TMP/bin/senswidemezhyelf" "$MODE" "$path" \
  "$TMP/reject-$NEG.elf" >"$TMP/reject.log" 2>"$TMP/reject.err" || rc=$?
 test "$rc" -eq 2 && test ! -e "$TMP/reject-$NEG.elf"
 test ! -s "$TMP/reject.log"
 grep -Fq 'Д6-МЕЖІ-WIDEIR-ВІДМОВА:' "$TMP/reject.err"
 NEG=$((NEG+1))
}
for name in wrong-d5 wrong-d6 wrong-d7 d1 d24 d24-right missing \
 extra nested two-roots dotted root-atom unclosed close-only \
 wrong-signature malformed empty; do
 reject "$TMP/physical/$name.sens"
done
reject "$TMP/physical/fake.lisp"
reject "$TMP/physical/missing-file.sens"
test "$NEG" -eq 19
cp "$TMP/06-110100.elf" "$TMP/occupied.elf"
hash_before="$(sha256sum "$TMP/occupied.elf" | cut -d' ' -f1)"
rc=0
timeout 20s "$TMP/bin/senswidemezhyelf" "$MODE" \
  "$TMP/physical/06-110100.sens" "$TMP/occupied.elf" \
  >"$TMP/clobber.log" 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/clobber.log"
test "$(sha256sum "$TMP/occupied.elf" | cut -d' ' -f1)" = "$hash_before"
ln -s "$TMP/nonexistent.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswidemezhyelf" "$MODE" \
 "$TMP/physical/06-110100.sens" "$TMP/dangling.elf" \
 >"$TMP/dangling.log" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" &&
  test ! -e "$TMP/nonexistent.elf"
timeout 20s "$TMP/bin/senswidemezhyelf" "$MODE" \
 "$TMP/physical/08-110110.sens" "$TMP/recovered.elf" \
 >"$TMP/recovery.log" 2>"$TMP/recovery.err"
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/physical/03-expected.sens" "$TMP/recovered.sens"
echo "D6-MEZHY-WIDEIR-OK physical=$COUNT oracle=$ORACLE_COUNT negative=$NEG donor-byte-identical=$COUNT machine=SETLE/SETGE energy=NOT-MEASURED"
