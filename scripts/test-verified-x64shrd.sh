#!/usr/bin/env bash
# G6.250 — незалежна машина SHRD: checked FPC, GNU as, реальні ELF64.
# Чинний test-verified-all.sh підхоплює цей файл без нового workflow/apt.
# Це лише host x86-64, не нові правила SENS, D7 чи D12+.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'SHRD-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in timeout fpc as objcopy cmp readelf objdump grep mktemp; do
  command -v "$tool" >/dev/null || {
    echo "SHRD-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
TMP=$(mktemp -d)
cleanup() {
  local rc=$? f
  if ((rc)); then
    echo "SHRD-ПРОВАЛ код=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ -s "$f" ]] || continue
      echo "--- $f" >&2
      tail -n 45 "$f" >&2
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/data"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64shrd \
  "$ROOT/scripts/test-x64shrd.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 45s \
  "$TMP/bin/test-x64shrd" "$TMP/data" >"$TMP/test.log" 2>"$TMP/test.err" || {
    cat "$TMP/test.log" "$TMP/test.err" >&2; exit 1;
  }
grep -Eq '^G6[.]250-SHRD-[^[:space:]]+ matrix=64 golden=4 negative=7 elf=4 recovery=1$' "$TMP/test.log"
test ! -s "$TMP/test.err"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
timeout 30s as --64 "$TMP/data/shrd-matrix.s" -o "$TMP/matrix.o"
timeout 30s objcopy -O binary -j .text "$TMP/matrix.o" "$TMP/matrix.gnu.bin"
test "$(wc -c < "$TMP/matrix.gnu.bin")" -eq 256
cmp "$TMP/data/shrd-matrix.fpc.bin" "$TMP/matrix.gnu.bin"
for a in 0 1; do
  for b in 0 1; do
    target="$TMP/data/shrd-$a-$b.elf"
    expected="$TMP/data/shrd-$a-$b.expected.sens"
    test -s "$target" && test -s "$expected"
    chmod 700 "$target"
    timeout 5s readelf -h "$target" >"$TMP/elf.log"
    grep -Eq 'Type:.*DYN' "$TMP/elf.log"
    grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.log"
    timeout 5s readelf -l "$target" >"$TMP/segments.log"
    grep -Fq LOAD "$TMP/segments.log"
    ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
    tail -c +121 "$target" >"$TMP/machine.bin"
    timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
      "$TMP/machine.bin" >"$TMP/asm.log"
    grep -Eq 'shrd[[:space:]]+eax,ecx,0x1' "$TMP/asm.log"
    grep -Eq 'shrd[[:space:]]+eax,edx,0x1f' "$TMP/asm.log"
    timeout 5s "$target" >"$TMP/actual.sens" 2>"$TMP/native.err"
    cmp "$expected" "$TMP/actual.sens"
    test ! -s "$TMP/native.err"
    rc=0
    timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$target" \
      2>"$TMP/closed.err" || rc=$?
    test "$rc" -eq 1 && test ! -s "$TMP/closed.err"
    rc=0
    timeout 5s "$target" >/dev/full 2>"$TMP/full.err" || rc=$?
    test "$rc" -eq 1 && test ! -s "$TMP/full.err"
    timeout 5s "$target" >"$TMP/recovery.sens"
    cmp "$expected" "$TMP/recovery.sens"
  done
done
echo 'VERIFIED-SHRD-PASS FPC=checked GNU-as=64 golden=4 negative=7 ELF64=4 T5M=4 closed=4 full=4 recovery=4 oracle=NOT-RUN energy=NOT-MEASURED'
