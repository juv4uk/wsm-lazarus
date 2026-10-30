#!/usr/bin/env bash
# G6.247 — дешевий регресійний доказ без нового workflow і без apt.
# Збираємо тільки FPC host-codegen; GNU as перевіряє 24 opcode незалежно.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'X64-РЕГІСТРИ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc as objcopy cmp readelf timeout grep mktemp; do
  command -v "$tool" >/dev/null || {
    echo "X64-РЕГІСТРИ-БЛОК: немає $tool" >&2; exit 127;
  }
done
TMP=$(mktemp -d)
cleanup() {
  rc=$?
  if ((rc)); then
    echo "X64-РЕГІСТРИ-ПРОВАЛ код=$rc" >&2
    for file in "$TMP"/*.log "$TMP"/*.err; do
      [[ -s "$file" ]] || continue
      tail -n 35 "$file" >&2
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/data"
timeout 150s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-verified-x64code-regs \
  "$ROOT/scripts/test-verified-x64code-regs.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 40s \
  "$TMP/bin/test-verified-x64code-regs" "$TMP/data" \
  >"$TMP/test.log" 2>"$TMP/test.err"
grep -Fq 'G6.247-X64CODE-REGS-PASS matrix=24 negatives=8 recovery=1 elf=2' "$TMP/test.log"
test ! -s "$TMP/test.err"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
timeout 20s as --64 "$TMP/data/matrix.s" -o "$TMP/matrix.o"
timeout 20s objcopy -O binary -j .text "$TMP/matrix.o" "$TMP/matrix.gnu.bin"
cmp "$TMP/data/matrix.fpc.bin" "$TMP/matrix.gnu.bin"
for bit in 0 1; do
  image="$TMP/data/bit-$bit.elf"
  expected="$TMP/data/bit-$bit.sens"
  test -s "$image" && test -s "$expected"
  timeout 5s readelf -h "$image" >"$TMP/elf-$bit.log"
  grep -Eq 'Type:.*DYN' "$TMP/elf-$bit.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf-$bit.log"
  chmod 700 "$image"
  timeout 5s "$image" >"$TMP/out-$bit.sens" 2>"$TMP/run-$bit.err"
  cmp "$expected" "$TMP/out-$bit.sens"
  test ! -s "$TMP/run-$bit.err"
done
echo 'G6.247-VERIFIED-X64CODE-REGS-PASS checked-FPC=3.2.2 GNU-as=24 negative=8 recovery=1 physical-D1-T5M-ELF64=2 oracle=NOT-RUN energy=NOT-MEASURED'
