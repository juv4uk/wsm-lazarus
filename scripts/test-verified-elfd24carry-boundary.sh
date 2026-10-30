#!/usr/bin/env bash
# G6.260 — 66 реальних Linux ELF64 D24 ADD→ADC і 14 атомарних переповнень.
# Новий незалежний verified-тест; чинний test-verified-all.sh підхоплює
# цей файл без нового workflow, apt або дорогої компіляції SENS Rust/Zig.
# Математичний Int64 witness НЕ є незалежним SENS REPL oracle.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'D24-BOUNDARY-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
FPC_BIN=${FPC:-fpc}
for tool in "$FPC_BIN" timeout cmp readelf objdump grep mktemp wc; do
  command -v "$tool" >/dev/null || {
    echo "D24-BOUNDARY-БЛОК: немає $tool" >&2
    exit 127
  }
done
timeout 120s bash scripts/check-pin.sh
TMP=$(mktemp -d)
cleanup() {
  local rc=$? f
  if ((rc)); then
    echo "D24-BOUNDARY-ПРОВАЛ код=$rc" >&2
    for f in "$TMP"/*.log; do
      [[ -s "$f" ]] || continue
      echo "--- $f" >&2
      tail -n 45 "$f" >&2
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-elfd24carry-boundary \
  "$ROOT/scripts/test-elfd24carry-boundary.pas" \
  >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2
    exit 1
  }
HEAPTRC="log=$TMP/heap.log" timeout 45s \
  "$TMP/bin/test-elfd24carry-boundary" "$TMP/physical" \
  >"$TMP/fixture.log" 2>"$TMP/fixture.err.log" || {
    cat "$TMP/fixture.log" "$TMP/fixture.err.log" >&2
    exit 1
  }
grep -Fxq 'D24-CARRY-BOUNDARY-PASS positives=66 negatives=14 recovery=1' "$TMP/fixture.log"
test ! -s "$TMP/fixture.err.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
test "$(wc -l < "$TMP/physical/cases.txt")" -eq 66

PASS=0
while IFS= read -r label; do
  [[ "$label" =~ ^[0-9][0-9]$ ]] || exit 1
  exe="$TMP/physical/$label.elf"
  expected="$TMP/physical/$label.expected.sens"
  test -s "$exe" && test -s "$expected"
  test -s "$TMP/physical/$label.left.sens"
  test -s "$TMP/physical/$label.right.sens"
  test "$(wc -c < "$expected")" -eq 5
  timeout 5s readelf -h "$exe" >"$TMP/header.log"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 5s readelf -l "$exe" >"$TMP/segments.log"
  grep -Fq LOAD "$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  chmod 700 "$exe"
  timeout 5s "$exe" >"$TMP/actual.sens" 2>"$TMP/run.log"
  test ! -s "$TMP/run.log"
  cmp "$expected" "$TMP/actual.sens"
  PASS=$((PASS+1))
done <"$TMP/physical/cases.txt"
test "$PASS" -eq 66

# Один із реально виконаних ELF має містити машинний ADD→ADC,
# а не лише підставлені п'ять байтів результату.
tail -c +121 "$TMP/physical/01.elf" >"$TMP/code.bin"
timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
  "$TMP/code.bin" >"$TMP/disasm.log"
grep -Eq 'add[[:space:]]+eax,ecx' "$TMP/disasm.log"
grep -Eq 'adc[[:space:]]+edx,ebx' "$TMP/disasm.log"

CLOSED=0
FULL=0
RECOVERED=0
for label in 01 66; do
  exe="$TMP/physical/$label.elf"
  expected="$TMP/physical/$label.expected.sens"
  rc=0
  ( exec 1>&-; timeout 5s "$exe" ) 2>"$TMP/closed.log" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/closed.log"
  CLOSED=$((CLOSED+1))
  rc=0
  timeout 5s "$exe" >/dev/full 2>"$TMP/full.log" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/full.log"
  FULL=$((FULL+1))
  timeout 5s "$exe" >"$TMP/recovered.sens" 2>"$TMP/recovered.log"
  cmp "$expected" "$TMP/recovered.sens"
  test ! -s "$TMP/recovered.log"
  RECOVERED=$((RECOVERED+1))
done
test "$CLOSED" -eq 2 && test "$FULL" -eq 2 && test "$RECOVERED" -eq 2
echo 'VERIFIED-D24-CARRY-BOUNDARY-PASS FPC=checked ELF64=66 D24-overflow=14 T5M=byte-exact ADD-ADC=machine closed=2 full=2 recovery=3 oracle=LOCAL-MATH energy=NOT-MEASURED'
