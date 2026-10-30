#!/usr/bin/env bash
# G6.250 — незалежні GNU as 128 ADC/SBB, реальні ELF64 і W1 T5M.
# Один чинний fpc-headless/verified-all, без нового workflow або apt.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'X64-CARRY-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in timeout fpc as objcopy cmp readelf mktemp grep chmod; do
  command -v "$tool" >/dev/null || {
    echo "X64-CARRY-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc)); then for f in "$TMP"/*.log; do
  [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 30 "$f" >&2; }
done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
FPC_BIN=${FPC:-fpc}
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64carry \
  "$ROOT/scripts/test-x64carry.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 30s "$TMP/bin/test-x64carry" \
  "$TMP/physical" >"$TMP/test.log" 2>"$TMP/stderr.log" || {
    cat "$TMP/test.log" "$TMP/stderr.log" >&2; exit 1;
  }
grep -Fxq 'X64-CARRY-ГОТОВО golden=128 negative=6 elf64=4 t5m=4 energy=NOT-MEASURED' "$TMP/test.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
timeout 30s as --64 -o "$TMP/carry-reference.o" "$TMP/physical/carry-reference.s"
timeout 30s objcopy -O binary -j .text "$TMP/carry-reference.o" \
  "$TMP/carry-gnu.bin"
test "$(wc -c < "$TMP/carry-gnu.bin")" -eq 256
cmp "$TMP/physical/carry-fpc.bin" "$TMP/carry-gnu.bin"
COUNT=0
for op in adc sbb; do
  for flag in 0 1; do
    target="$TMP/physical/$op-$flag.elf"
    expected="$TMP/physical/$op-$flag.expected.sens"
    test -s "$target" && test -s "$expected"
    test "$(wc -c < "$expected")" -eq 1
    chmod 700 "$target"
    timeout 5s readelf -h "$target" >"$TMP/header.log"
    grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header.log"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
    timeout 5s readelf -l "$target" >"$TMP/segments.log"
    grep -Fq 'LOAD' "$TMP/segments.log"
    ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
    timeout 5s "$target" >"$TMP/actual.sens" 2>"$TMP/machine.log"
    test ! -s "$TMP/machine.log"
    cmp "$TMP/actual.sens" "$expected"
    COUNT=$((COUNT+1))
  done
done
test "$COUNT" -eq 4
echo 'VERIFIED-X64-CARRY-PASS FPC=checked golden=128 negative=6 ELF64=4 T5M=4 oracle=HOST-ISA energy=NOT-MEASURED'
