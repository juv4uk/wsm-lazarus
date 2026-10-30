#!/usr/bin/env bash
# G6 — перевірена машина BSWAP; жодних заяв про SENS semantics/енергію.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'X64-BSWAP-БЛОК: потрібен Linux x86_64' >&2; exit 127;
}
for tool in timeout fpc as objcopy readelf objdump cmp mktemp; do
  command -v "$tool" >/dev/null || {
    echo "X64-BSWAP-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 150s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  for f in "$TMP"/*.log; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 70 "$f" >&2; }
  done
fi
rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64bswap \
  "$ROOT/scripts/test-x64bswap.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 30s "$TMP/bin/test-x64bswap" "$TMP/data" \
  >"$TMP/test.log" 2>"$TMP/stderr.log" || {
    cat "$TMP/test.log" "$TMP/stderr.log" >&2; exit 1;
  }
grep -Fq 'X64-BSWAP-OK cases=32 negative=9 elf=2 energy=NOT-MEASURED' "$TMP/test.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
timeout 30s as --64 -o "$TMP/data/bswap-reference.o" "$TMP/data/bswap-reference.s"
timeout 30s objcopy -O binary -j .text \
  "$TMP/data/bswap-reference.o" "$TMP/data/bswap-gnu.bin"
test "$(wc -c < "$TMP/data/bswap-gnu.bin")" -eq 88
cmp "$TMP/data/bswap-fpc.bin" "$TMP/data/bswap-gnu.bin"
for width in 32 64; do
  target="$TMP/data/case-$width.elf"
  expected="$TMP/data/case-$width.expected.bin"
  test -s "$target" && test -s "$expected"
  test "$(wc -c < "$expected")" -eq 8
  chmod 700 "$target"
  timeout 5s readelf -h "$target" >"$TMP/elf.log"
  grep -Eq 'Type:.*EXEC' "$TMP/elf.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.log"
  timeout 5s readelf -l "$target" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$target" >"$TMP/code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/code" >"$TMP/asm.log"
  if [[ "$width" == 32 ]]; then
    grep -Eq 'bswap[[:space:]]+eax' "$TMP/asm.log"
  else
    grep -Eq 'bswap[[:space:]]+r8([[:space:]]|$)' "$TMP/asm.log"
  fi
  timeout 5s "$target" >"$TMP/actual.bin"
  test "$(wc -c < "$TMP/actual.bin")" -eq 8
  cmp "$TMP/actual.bin" "$expected"
done
echo 'X64-BSWAP-МАШИНА-ГАРАЗД 32 GNU-as parity; 9 negative; 2 ELF64; energy=NOT-MEASURED'
