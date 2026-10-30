#!/usr/bin/env bash
# G6.252: один FPC gate для MOVSX, 64 незалежні GNU as opcode, 4 ELF64.
# Машинний host-тест не додає законів або текстового dispatch у SENS.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
for t in timeout as objcopy cmp readelf objdump mktemp grep tail chmod wc git; do
  command -v "$t" >/dev/null || { echo "MOVSX: немає $t" >&2; exit 127; }
done
FPC_BIN=$(printenv FPC || printf fpc)
command -v "$FPC_BIN" >/dev/null || exit 127
timeout 120s bash scripts/check-pin.sh
TMP=$(mktemp -d)
cleanup() {
  rc=$?
  if ((rc)); then
    echo "MOVSX-ПРОВАЛ код=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 25 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/work"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64movsx \
  "$ROOT/scripts/test-x64movsx.pas" >"$TMP/build.log" 2>&1 || {
  tail -50 "$TMP/build.log" >&2; exit 1;
}
HEAPTRC="log=$TMP/heap.log" timeout 60s "$TMP/bin/test-x64movsx" \
  "$TMP/work" >"$TMP/test.log" 2>"$TMP/test.err"
grep -Fxq 'G6-252-MOVSX-PASS matrix=64 negative=8 recovery=1 elf=4' "$TMP/test.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
timeout 10s as --64 "$TMP/work/reference.s" -o "$TMP/ref.o"
timeout 10s objcopy -j .text -O binary "$TMP/ref.o" "$TMP/ref.bin"
test "$(wc -c <"$TMP/ref.bin")" -eq 192
cmp "$TMP/ref.bin" "$TMP/work/actual.bin"
count=0; closed=0; full=0; recovered=0
for k in 0 1 2 3; do
  elf="$TMP/work/case$k.elf"
  expect="$TMP/work/case$k.sens"
  test -s "$elf" && test "$(wc -c <"$expect")" -eq 1
  timeout 5s readelf -h "$elf" >"$TMP/elf.log"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/elf.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.log"
  timeout 5s readelf -l "$elf" >"$TMP/phdr.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/phdr.log"
  tail -c +121 "$elf" >"$TMP/machine.bin"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine.bin" >"$TMP/disasm.log"
  grep -Eq 'movsx[[:space:]]+eax,' "$TMP/disasm.log"
  chmod 700 "$elf"
  timeout 5s "$elf" >"$TMP/result.sens" 2>"$TMP/stderr.log"
  test ! -s "$TMP/stderr.log"
  cmp "$expect" "$TMP/result.sens"
  count=$((count+1))
  rc=0
  timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$elf" \
    2>"$TMP/closed.err" || rc=$?
  test "$rc" -eq 1 && test ! -s "$TMP/closed.err"
  closed=$((closed+1))
  rc=0
  timeout 5s "$elf" >/dev/full 2>"$TMP/full.err" || rc=$?
  test "$rc" -eq 1 && test ! -s "$TMP/full.err"
  full=$((full+1))
  timeout 5s "$elf" >"$TMP/recovered.sens" 2>"$TMP/stderr.log"
  cmp "$expect" "$TMP/recovered.sens"
  recovered=$((recovered+1))
done
test "$count" -eq 4 && test "$closed" -eq 4 && \
  test "$full" -eq 4 && test "$recovered" -eq 4
echo "VERIFIED-MOVSX-PASS fpc=checked GNU-as=64/64 bytes=192 elf=$count closed=$closed full=$full recovery=$recovered oracle=NOT-RUN energy=NOT-MEASURED"
