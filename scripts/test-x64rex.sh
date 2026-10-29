#!/usr/bin/env bash
# Фізичний host REX: checked FPC, незалежний GNU as, реальні ELF64.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'X64-REX-БЛОК: потрібен Linux x86_64' >&2; exit 127;
}
for tool in timeout fpc as objcopy cmp readelf objdump mktemp; do
  command -v "$tool" >/dev/null || {
    echo "X64-REX-БЛОК: відсутній $tool" >&2; exit 127;
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
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64rex \
  "$ROOT/scripts/test-x64rex.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 30s "$TMP/bin/test-x64rex" "$TMP/data" \
  >"$TMP/test.log" 2>"$TMP/stderr.log" || {
    cat "$TMP/test.log" "$TMP/stderr.log" >&2; exit 1;
  }
grep -Fq 'X64-REX-OK matrix=832 golden=4 negative=9 recovery=1 elf=2' "$TMP/test.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
timeout 60s as --64 -o "$TMP/matrix.o" "$TMP/data/matrix.s"
timeout 30s objcopy -O binary -j .text "$TMP/matrix.o" "$TMP/data/matrix.gnu.bin"
cmp "$TMP/data/matrix.fpc.bin" "$TMP/data/matrix.gnu.bin"
test "$(wc -c <"$TMP/data/matrix.gnu.bin")" -eq 2944
for bit in 0 1; do
  target="$TMP/data/rex-$bit.elf"
  chmod 700 "$target"
  timeout 5s readelf -h "$target" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 5s readelf -l "$target" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$target" >"$TMP/machine"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine" >"$TMP/asm.log"
  grep -Eq 'movabs[[:space:]]+r8,' "$TMP/asm.log"
  grep -Eq 'xor[[:space:]]+r9,r9' "$TMP/asm.log"
  grep -Eq 'add[[:space:]]+r8,r9' "$TMP/asm.log"
  grep -Eq 'mov[[:space:]]+rdx,r8' "$TMP/asm.log"
  timeout 5s "$target" >"$TMP/actual.sens"
  cmp "$TMP/actual.sens" "$TMP/data/rex-$bit.expected.sens"
done
echo 'X64-REX-МАШИНА-ГАРАЗД matrix=832 golden=4 negative=9 elf64=2 energy=NOT-MEASURED'
