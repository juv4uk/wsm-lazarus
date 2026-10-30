#!/usr/bin/env bash
# G6.252 — фізичний D24 + D24 у Linux ELF64 через справжній ADD→ADC.
# Перевіряємо машини, точні T5M байти, негативи та неповний stdout.
# Тільки вже чинний verified-all/FPC; ніякого окремого workflow чи apt.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'D24-CARRY-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in timeout fpc cmp grep readelf objdump mktemp chmod; do
  command -v "$tool" >/dev/null || {
    echo "D24-CARRY-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc)); then for log in "$TMP"/*.log; do
  [[ ! -s "$log" ]] || { echo "--- $log" >&2; tail -n 40 "$log" >&2; }
done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
FPC_BIN=${FPC:-fpc}
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-elfd24carry "$ROOT/scripts/test-elfd24carry.pas" \
  >"$TMP/build.log" 2>&1 || { cat "$TMP/build.log" >&2; exit 1; }
HEAPTRC="log=$TMP/heap.log" timeout 30s "$TMP/bin/test-elfd24carry" \
  "$TMP/physical" >"$TMP/fixture.log" 2>"$TMP/error.log" || {
    cat "$TMP/fixture.log" "$TMP/error.log" >&2; exit 1;
  }
grep -Fxq 'D24-CARRY-ГОТОВО ELF64=10 negative=8 recovery=1 T5M=W24-exact CPU=ADD-ADC oracle=LOCAL-PINNED energy=NOT-MEASURED' "$TMP/fixture.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
test "$(wc -l < "$TMP/physical/cases.txt")" -eq 10
PASS=0
while IFS= read -r label; do
  [[ "$label" =~ ^[0-9][0-9]$ ]] || exit 1
  exe="$TMP/physical/$label.elf"
  expected="$TMP/physical/$label.expected.sens"
  test -s "$exe" && test -s "$expected"
  test "$(wc -c < "$expected")" -eq 5
  timeout 5s readelf -h "$exe" >"$TMP/header.log"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 5s readelf -l "$exe" >"$TMP/segments.log"
  grep -Fq 'LOAD' "$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  chmod 700 "$exe"
  timeout 5s "$exe" >"$TMP/actual.sens" 2>"$TMP/machine.log"
  test ! -s "$TMP/machine.log"
  cmp "$expected" "$TMP/actual.sens"
  PASS=$((PASS+1))
done <"$TMP/physical/cases.txt"
test "$PASS" -eq 10
# Розрізняємо ADD і справжній ADC у тілі згенерованої машини.
tail -c +121 "$TMP/physical/01.elf" >"$TMP/machine.bin"
timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
  "$TMP/machine.bin" >"$TMP/disasm.log"
grep -Eq 'add[[:space:]]+eax,ecx' "$TMP/disasm.log"
grep -Eq 'adc[[:space:]]+edx,ebx' "$TMP/disasm.log"
CLOSED=0
FULL=0
RECOVERED=0
for label in 01 04; do
  exe="$TMP/physical/$label.elf"
  expected="$TMP/physical/$label.expected.sens"
  rc=0
  ( exec 1>&-; timeout 5s "$exe" ) 2>"$TMP/closed.log" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/closed.log"
  CLOSED=$((CLOSED+1))
  rc=0
  timeout 5s "$exe" >/dev/full 2>"$TMP/full.log" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/full.log"
  FULL=$((FULL+1))
  timeout 5s "$exe" >"$TMP/recovered.sens" 2>"$TMP/recovered.log"
  test ! -s "$TMP/recovered.log"
  cmp "$expected" "$TMP/recovered.sens"
  RECOVERED=$((RECOVERED+1))
done
test "$CLOSED" -eq 2 && test "$FULL" -eq 2 && test "$RECOVERED" -eq 2
echo 'VERIFIED-D24-CARRY-PASS FPC=checked ELF64=10 negative=8 closed=2 full=2 recovery=3 T5M=byte-exact oracle=LOCAL-PINNED energy=NOT-MEASURED'
