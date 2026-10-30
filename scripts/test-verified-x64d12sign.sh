#!/usr/bin/env bash
# G6.256 — фізичний D12 → SHL/MOVSX/SAR → 9 справжніх ELF64.
# Тільки механізм backend, без нового закону, без додаткового workflow.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
for tool in timeout as objcopy cmp readelf objdump mktemp grep wc chmod git; do
  command -v "$tool" >/dev/null || exit 127
done
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || exit 127
timeout 120s bash scripts/check-pin.sh
TMP=$(mktemp -d)
cleanup() {
  rc=$?
  if ((rc)); then
    echo "D12-SIGN-ПОМИЛКА код=$rc" >&2
    for log in "$TMP"/*.log; do
      [[ ! -s "$log" ]] || { echo "--- $log" >&2; tail -n 24 "$log" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64d12sign \
  "$ROOT/scripts/test-x64d12sign.pas" >"$TMP/build.log" 2>&1 || {
    tail -50 "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 60s "$TMP/bin/test-x64d12sign" \
  "$TMP/physical" >"$TMP/test.log" 2>"$TMP/test.err" || {
    cat "$TMP/test.log" "$TMP/test.err" >&2; exit 1;
  }
grep -Fxq 'G6-256-D12-SIGN-PASS matrix=8 bytes=72 negative=8 recovery=1 elf=9' "$TMP/test.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
timeout 10s as --64 "$TMP/physical/matrix.s" -o "$TMP/ref.o"
timeout 10s objcopy -j .text -O binary "$TMP/ref.o" "$TMP/ref.bin"
test "$(wc -c <"$TMP/ref.bin")" -eq 72
cmp "$TMP/ref.bin" "$TMP/physical/matrix.bin"
count=0
for i in 0 1 2 3 4 5 6 7 8; do
  elf="$TMP/physical/case$i.elf"
  expected="$TMP/physical/case$i.sens"
  physical="$TMP/physical/case$i.input.sens"
  test -s "$elf" && test -s "$expected" && test -s "$physical"
  test "$(wc -c <"$expected")" -eq 1
  test "$(wc -c <"$physical")" -eq 3
  timeout 5s readelf -h "$elf" >"$TMP/elf.log"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/elf.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.log"
  timeout 5s readelf -l "$elf" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  chmod 700 "$elf"
  timeout 5s "$elf" >"$TMP/result.sens" 2>"$TMP/stderr.log"
  test ! -s "$TMP/stderr.log"
  cmp "$expected" "$TMP/result.sens"
  count=$((count+1))
done
tail -c +121 "$TMP/physical/case0.elf" >"$TMP/machine.bin"
timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
  "$TMP/machine.bin" >"$TMP/disasm.log"
grep -Eq 'shl[[:space:]]+eax,0x4' "$TMP/disasm.log"
grep -Eq 'movsx[[:space:]]+eax,ax' "$TMP/disasm.log"
grep -Eq 'sar[[:space:]]+eax,0x4' "$TMP/disasm.log"
closed=0; full=0; recovery=0
for i in 0 4 8; do
  elf="$TMP/physical/case$i.elf"
  expected="$TMP/physical/case$i.sens"
  rc=0
  timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$elf" \
    2>"$TMP/closed.log" || rc=$?
  test "$rc" -eq 1 && test ! -s "$TMP/closed.log"
  closed=$((closed+1))
  rc=0
  timeout 5s "$elf" >/dev/full 2>"$TMP/full.log" || rc=$?
  test "$rc" -eq 1 && test ! -s "$TMP/full.log"
  full=$((full+1))
  timeout 5s "$elf" >"$TMP/recovered.sens" 2>"$TMP/stderr.log"
  cmp "$expected" "$TMP/recovered.sens"
  recovery=$((recovery+1))
done
test "$count" -eq 9 && test "$closed" -eq 3 && \
  test "$full" -eq 3 && test "$recovery" -eq 3
echo "VERIFIED-D12-SIGN-PASS fpc=checked GNU-as=8/8 elf=$count closed=$closed full=$full recovery=$recovery oracle=HOST-ONLY energy=NOT-MEASURED"
