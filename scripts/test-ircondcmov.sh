#!/usr/bin/env bash
# G6.116: verified D3/T5M → CPU CMOVcc → ELF64, independent pinned SENS.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'D3-CMOV-БЛОК: потрібен Linux x86_64' >&2; exit 127;
}
for tool in timeout fpc git readelf objdump cmp mktemp grep; do
  command -v "$tool" >/dev/null || {
    echo "D3-CMOV-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(110 (ук за-умовою)' external/sens/lib/domains/d3.lisp
grep -Fq '(101 (ук тотожне?)' external/sens/lib/domains/d3.lisp
grep -Fq '(cond-clause . (test expression))' \
  external/sens/contracts/language-contract-12.lisp
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || {
  echo 'D3-CMOV-БЛОК: потрібен незалежний pinned SENS CLI' >&2;exit 127; }
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  for f in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 70 "$f" >&2; }
  done
fi;rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-ircondcmov \
  "$ROOT/scripts/test-ircondcmov.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 60s "$TMP/bin/test-ircondcmov" \
  "$TMP/physical" >"$TMP/test.log" 2>"$TMP/test.err" || {
    cat "$TMP/test.log" "$TMP/test.err" >&2;exit 1;
  }
grep -Fq 'D3-CMOV-OK positives=10 negatives=13 PIE=10 T5M=10 recovery=1 energy=NOT-MEASURED' "$TMP/test.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
count=0
for source in "$TMP/physical/"*.sens; do
  [[ -f "$source" ]] || { echo 'немає фізичних свідків' >&2;exit 1; }
  name="$(basename "$source" .sens)"
  elf="$TMP/physical/$name.elf"
  expected="$TMP/physical/$name.expected.sens"
  oracle_text="$TMP/physical/$name.oracle.txt"
  test -s "$elf" && test -s "$expected" && test -s "$oracle_text"
  chmod 500 "$elf"
  timeout 5s readelf -h "$elf" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 5s readelf -l "$elf" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$elf" >"$TMP/machine.bin"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine.bin" >"$TMP/asm.log"
  grep -Eq 'cmovne[[:space:]]+ecx,edx' "$TMP/asm.log"
  grep -Eq 'cmove[[:space:]]+ebx,ecx' "$TMP/asm.log"
  timeout 5s "$elf" >"$TMP/actual.sens" 2>"$TMP/machine.err"
  test ! -s "$TMP/machine.err"
  cmp "$expected" "$TMP/actual.sens"
  timeout 90s "$ORACLE" "$source" >"$TMP/oracle.actual" \
    2>"$TMP/oracle.err" || {
      echo "D3-CMOV-ОРАКУЛ-ВІДМОВА: $name" >&2
      cat "$TMP/oracle.err" >&2; exit 1;
    }
  test ! -s "$TMP/oracle.err"
  cmp "$oracle_text" "$TMP/oracle.actual"
  count=$((count+1))
done
test "$count" -eq 10
echo "D3-CMOV-МАШИНА-ГАРАЗД physical=$count ELF64=$count pinned-SENS=$count negatives=13 energy=NOT-MEASURED"
