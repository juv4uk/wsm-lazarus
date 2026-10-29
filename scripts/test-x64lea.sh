#!/usr/bin/env bash
# Реальні checked FPC, GNU as/objcopy та два виконані PIE ELF.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'X64-LEA-БЛОК: потрібен Linux x86_64' >&2; exit 127;
}
for tool in timeout fpc as objcopy cmp readelf objdump mktemp; do
  command -v "$tool" >/dev/null || {
    echo "X64-LEA-БЛОК: відсутній $tool" >&2; exit 127;
  }
done
timeout 150s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then for f in "$TMP"/*.log; do
  [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 60 "$f" >&2; }
done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64lea \
  "$ROOT/scripts/test-x64lea.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 30s "$TMP/bin/test-x64lea" "$TMP/data" \
  >"$TMP/test.log" 2>"$TMP/stderr.log" || {
    cat "$TMP/test.log" "$TMP/stderr.log" >&2; exit 1;
  }
grep -Fq 'X64-LEA-ГОТОВО matrix=5376 golden=4 negative=10 recovery=1 elf=2' "$TMP/test.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
timeout 60s as --64 -o "$TMP/matrix.o" "$TMP/data/matrix.s"
timeout 30s objcopy -O binary -j .text "$TMP/matrix.o" "$TMP/data/matrix.gnu.bin"
cmp "$TMP/data/matrix.fpc.bin" "$TMP/data/matrix.gnu.bin"
for bit in 0 1; do
  exe="$TMP/data/lea-$bit.elf"
  chmod 700 "$exe"
  timeout 5s readelf -h "$exe" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 5s readelf -l "$exe" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    --start-address=120 "$exe" >"$TMP/asm.log"
  grep -Eq 'lea[[:space:]]+rdx,' "$TMP/asm.log"
  timeout 5s "$exe" >"$TMP/actual.sens"
  cmp "$TMP/actual.sens" "$TMP/data/lea-$bit.expected.sens"
done
echo 'X64-LEA-МАШИНА-ГАРАЗД vectors=5376 golden=4 negative=10 elf64=2 energy=NOT-MEASURED'
