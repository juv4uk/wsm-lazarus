#!/usr/bin/env bash
# G6.111: host x86-64 SSE2 1024 GNU as byte oracle + 2 real PIE ELF.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'SSE2-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in timeout fpc as objcopy cmp readelf objdump mktemp grep wc; do
  command -v "$tool" >/dev/null || {
    echo "SSE2-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 150s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc)); then for f in "$TMP"/*.log; do [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 70 "$f" >&2; }; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data" "$TMP/repeat"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-x64sse2 "$ROOT/scripts/test-x64sse2.pas" \
  >"$TMP/build.log" 2>&1 || { cat "$TMP/build.log" >&2; exit 1; }
HEAPTRC="log=$TMP/heap.log" timeout 30s \
  "$TMP/bin/test-x64sse2" "$TMP/data" >"$TMP/test.log" 2>"$TMP/stderr.log" || {
    cat "$TMP/test.log" "$TMP/stderr.log" >&2; exit 1;
  }
grep -Fq 'X64-SSE2-OK matrix=1024 golden=4 negative=12 quota=2 recovery=1 elf=2' "$TMP/test.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
test ! -s "$TMP/stderr.log"
timeout 60s as --64 -o "$TMP/matrix.o" "$TMP/data/matrix.s"
timeout 20s objcopy -O binary -j .text "$TMP/matrix.o" "$TMP/data/matrix.gnu.bin"
cmp "$TMP/data/matrix.gnu.bin" "$TMP/data/matrix.fpc.bin"
[[ "$(wc -c <"$TMP/data/matrix.gnu.bin")" -eq 4864 ]]
for spec in 'xor 2 pxor' 'addq 4 paddq'; do
  read -r name expected opcode <<<"$spec"
  elf="$TMP/data/$name.elf"
  chmod 700 "$elf"
  timeout 5s readelf -h "$elf" >"$TMP/elf.header.log"
  grep -Eq 'Type:.*DYN' "$TMP/elf.header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.header.log"
  timeout 5s readelf -l "$elf" >"$TMP/elf.segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/elf.segments.log"
  tail -c +121 "$elf" >"$TMP/elf.code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/elf.code" >"$TMP/elf.disasm.log"
  grep -Eiq "$opcode[[:space:]]+xmm0,xmm1" "$TMP/elf.disasm.log"
  rc=0
  timeout 5s "$elf" >"$TMP/elf.stdout" 2>"$TMP/elf.stderr" || rc=$?
  test "$rc" -eq "$expected"
  test ! -s "$TMP/elf.stdout"
  test ! -s "$TMP/elf.stderr"
done
HEAPTRC="log=$TMP/heap-again.log" timeout 30s \
  "$TMP/bin/test-x64sse2" "$TMP/repeat" >"$TMP/repeat.log" 2>"$TMP/repeat.stderr.log"
for name in matrix.s matrix.fpc.bin xor.elf addq.elf; do
  cmp "$TMP/data/$name" "$TMP/repeat/$name"
done
grep -Fq '0 unfreed memory blocks' "$TMP/heap-again.log"
echo 'X64-SSE2-МАШИНА-ГАРАЗД oracle=1024 negative=12 elf=2 parity=NOT-CLAIMED energy=NOT-MEASURED'
