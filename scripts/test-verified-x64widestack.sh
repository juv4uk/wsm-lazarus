#!/usr/bin/env bash
# G6.241 — checked FPC + independent GNU as + two executed x86-64 PIE.
# No new workflow, Rust/Zig install, SENS semantic dispatch or energy claims.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ШИРОКИЙ-СТЕК-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout as objcopy cmp readelf objdump grep mktemp; do
  command -v "$tool" >/dev/null || {
    echo "ШИРОКИЙ-СТЕК-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
TMP=$(mktemp -d)
cleanup() {
  local rc=$? f
  if ((rc)); then
    echo "ШИРОКИЙ-СТЕК-ПРОВАЛ код=$rc" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ -s "$f" ]] || continue
      echo "--- $f" >&2; tail -n 55 "$f" >&2
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/data"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64widestack \
  "$ROOT/scripts/test-x64widestack.pas" >"$TMP/build.log" 2>&1 || {
  cat "$TMP/build.log" >&2; exit 1;
}
HEAPTRC="log=$TMP/heap.log" timeout 45s \
  "$TMP/bin/test-x64widestack" "$TMP/data" >"$TMP/test.log" 2>"$TMP/test.err"
grep -Fq 'G6.241-WIDESTACK-OK matrix=256 negative=16 elf=2' "$TMP/test.log"
test ! -s "$TMP/test.err"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"

timeout 30s as --64 "$TMP/data/wide-matrix.s" -o "$TMP/matrix.o"
timeout 30s objcopy -O binary -j .text "$TMP/matrix.o" "$TMP/matrix.gnu.bin"
cmp "$TMP/data/wide-matrix.fpc.bin" "$TMP/matrix.gnu.bin"

# Checked write epilogue: cmp eax,edx; setne dil; push 60; pop rax; syscall.
printf '\\x39\\xd0\\x40\\x0f\\x95\\xc7\\x6a\\x3c\\x58\\x0f\\x05' \
  >"$TMP/checked.bin"
for bit in 0 1; do
  target="$TMP/data/wide-$bit.elf"
  expected="$TMP/data/wide-$bit.expected.sens"
  test -s "$target" && test -s "$expected"
  timeout 30s as --64 "$TMP/data/wide-$bit.s" -o "$TMP/wide-$bit.o"
  timeout 30s objcopy -O binary -j .text "$TMP/wide-$bit.o" "$TMP/wide-$bit.gnu.bin"
  cmp "$TMP/data/wide-$bit.fpc.bin" "$TMP/wide-$bit.gnu.bin"
  chmod 700 "$target"
  timeout 5s readelf -h "$target" >"$TMP/elf-$bit.log"
  grep -Eq 'Type:.*DYN' "$TMP/elf-$bit.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf-$bit.log"
  timeout 5s readelf -l "$target" >"$TMP/segments-$bit.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments-$bit.log"
  tail -c 11 "$target" | cmp - "$TMP/checked.bin"
  tail -c +121 "$target" >"$TMP/code-$bit.bin"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/code-$bit.bin" >"$TMP/disasm-$bit.log"
  grep -Eq 'mov[[:space:]]+QWORD PTR \\[rsp\\],r8' "$TMP/disasm-$bit.log"
  grep -Eq 'mov[[:space:]]+r8,QWORD PTR \\[rsp\\]' "$TMP/disasm-$bit.log"

  timeout 5s "$target" >"$TMP/actual-$bit.sens" 2>"$TMP/native-$bit.err"
  cmp "$expected" "$TMP/actual-$bit.sens"
  test ! -s "$TMP/native-$bit.err"

  rc=0
  timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$target" \
    2>"$TMP/closed-$bit.err" || rc=$?
  test "$rc" -eq 1 && test ! -s "$TMP/closed-$bit.err"

  rc=0
  timeout 5s "$target" >/dev/full 2>"$TMP/full-$bit.err" || rc=$?
  test "$rc" -eq 1 && test ! -s "$TMP/full-$bit.err"

  timeout 5s "$target" >"$TMP/recovery-$bit.sens" 2>"$TMP/recovery-$bit.err"
  cmp "$expected" "$TMP/recovery-$bit.sens"
  test ! -s "$TMP/recovery-$bit.err"
done
echo 'G6.241-VERIFIED-WIDESTACK-PASS matrix=256 negative=16 GNU-as=258 ELF=2 closed=2 full=2 recovery=2 oracle=NOT-RUN energy=NOT-MEASURED'
