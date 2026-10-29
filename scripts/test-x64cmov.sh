#!/usr/bin/env bash
# G6.113 — реальні FPC, незалежний GNU as і ELF64. Не енергозамір.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'X64-CMOV-БЛОК: потрібен Linux x86_64' >&2; exit 127;
}
for tool in timeout fpc as objcopy readelf objdump cmp mktemp; do
  command -v "$tool" >/dev/null || {
    echo "X64-CMOV-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 150s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then for f in "$TMP"/*.log; do
  [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 70 "$f" >&2; }
done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64cmov \
  "$ROOT/scripts/test-x64cmov.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 30s "$TMP/bin/test-x64cmov" "$TMP/data" \
  >"$TMP/test.log" 2>"$TMP/stderr.log" || {
    cat "$TMP/test.log" "$TMP/stderr.log" >&2; exit 1;
  }
grep -Fq 'X64-CMOV-OK cases=1024 negative=4 elf=4 energy=NOT-MEASURED' "$TMP/test.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
timeout 30s as --64 -o "$TMP/data/cmov-reference.o" "$TMP/data/cmov-reference.s"
timeout 30s objcopy -O binary -j .text \
  "$TMP/data/cmov-reference.o" "$TMP/data/cmov-gnu.bin"
test "$(wc -c < "$TMP/data/cmov-gnu.bin")" -eq 3072
cmp "$TMP/data/cmov-fpc.bin" "$TMP/data/cmov-gnu.bin"
for a in 0 1; do
  for b in 0 1; do
    target="$TMP/data/case-$a$b.elf"
    expected="$TMP/data/case-$a$b.expected.sens"
    test -s "$target" && test -s "$expected"
    chmod 700 "$target"
    timeout 5s readelf -h "$target" >"$TMP/elf.log"
    grep -Eq 'Type:.*EXEC' "$TMP/elf.log"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.log"
    timeout 5s readelf -l "$target" >"$TMP/segments.log"
    ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
    tail -c +121 "$target" >"$TMP/code"
    timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
      "$TMP/code" >"$TMP/asm.log"
    grep -Eq 'cmp[[:space:]]+eax,ecx' "$TMP/asm.log"
    grep -Eq 'cmove[[:space:]]+edx,ebx' "$TMP/asm.log"
    timeout 5s "$target" >"$TMP/actual.sens"
    cmp "$TMP/actual.sens" "$expected"
  done
done
echo 'X64-CMOV-МАШИНА-ГАРАЗД 1024 GNU-as parity; 4 negative; 4 ELF64; energy=NOT-MEASURED'
