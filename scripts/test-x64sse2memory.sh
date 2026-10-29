#!/usr/bin/env bash
# G6.115 — FPC x86-64 MOVDQU bytes ↔ GNU as, реальні unaligned ELF.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'SSE2-ПАМ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for t in timeout fpc as objcopy cmp readelf objdump mktemp grep wc tail chmod git; do
  command -v "$t" >/dev/null || {
    echo "SSE2-ПАМ-БЛОК: відсутній $t" >&2; exit 127;
  }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc)); then for f in "$TMP"/*.log; do [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 65 "$f" >&2; }; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/first" "$TMP/again"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-x64sse2memory "$ROOT/scripts/test-x64sse2memory.pas" \
  >"$TMP/build.log" 2>&1 || { cat "$TMP/build.log" >&2; exit 1; }
HEAPTRC="log=$TMP/heap.log" timeout 40s "$TMP/bin/test-x64sse2memory" "$TMP/first" \
  >"$TMP/test.log" 2>"$TMP/stderr.log" || {
  cat "$TMP/test.log" "$TMP/stderr.log" >&2; exit 1;
}
grep -Fq 'SSE2-MEM-OK matrix=3584 golden=6 negative=14 boundary=2 recovery=1 elf=2' "$TMP/test.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
test ! -s "$TMP/stderr.log"
timeout 90s as --64 -o "$TMP/matrix.o" "$TMP/first/matrix.s"
timeout 20s objcopy -O binary -j .text "$TMP/matrix.o" "$TMP/first/matrix.gnu.bin"
cmp "$TMP/first/matrix.fpc.bin" "$TMP/first/matrix.gnu.bin"
test "$(wc -c <"$TMP/first/matrix.fpc.bin")" -gt 15000
for spec in 'rsp 90' 'r12 107'; do
  read -r label expected <<< "$spec"
  elf="$TMP/first/$label.elf"
  chmod 700 "$elf"
  timeout 5s readelf -h "$elf" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 5s readelf -l "$elf" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$elf" >"$TMP/machine"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel "$TMP/machine" \
    >"$TMP/disassembly.log"
  grep -Eiq 'movdqu[[:space:]]+xmm' "$TMP/disassembly.log"
  grep -Eiq 'movdqu[[:space:]]+XMMWORD PTR' "$TMP/disassembly.log"
  rc=0
  timeout 5s "$elf" >"$TMP/out.log" 2>"$TMP/err.log" || rc=$?
  test "$rc" -eq "$expected" || {
    echo "SSE2-ПАМ: machine exit $rc != $expected" >&2; exit 1;
  }
  test ! -s "$TMP/out.log"
  test ! -s "$TMP/err.log"
done
HEAPTRC="log=$TMP/heap-again.log" timeout 40s \
  "$TMP/bin/test-x64sse2memory" "$TMP/again" \
  >"$TMP/repeat.log" 2>"$TMP/repeat.stderr.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap-again.log"
for file in matrix.s matrix.fpc.bin rsp.elf r12.elf; do
  cmp "$TMP/first/$file" "$TMP/again/$file"
done
echo 'SSE2-ПАМ-МАШИНА-ГАРАЗД GNU=3584 negatives=14 elf=2 deterministic=1 energy=NOT-MEASURED'
