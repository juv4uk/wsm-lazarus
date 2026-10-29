#!/usr/bin/env bash
# G6.97: справжній FPC і Linux x86-64 ELF64; не мовний REPL і не RAPL.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'X64-ПЕРЕХОДИ-БЛОК: потрібен Linux x86_64' >&2; exit 127;
}
for tool in timeout fpc readelf objdump cmp mktemp chmod grep; do
  command -v "$tool" >/dev/null || {
    echo "X64-ПЕРЕХОДИ-БЛОК: немає $tool" >&2; exit 127;
  }
done
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  for p in "$TMP"/build.log "$TMP"/test.log "$TMP"/stderr.log; do
    [[ ! -s "$p" ]] || { echo "--- $p" >&2; tail -n 60 "$p" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64branch \
  "$ROOT/scripts/test-x64branch.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 30s "$TMP/bin/test-x64branch" "$TMP/data" \
  >"$TMP/test.log" 2>"$TMP/stderr.log" || {
    cat "$TMP/test.log" "$TMP/stderr.log" >&2; exit 1;
  }
grep -Fq 'X64-ПЕРЕХОДИ-ГАРАЗД golden=2 negative=8 recovery=1 elf=2' "$TMP/test.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
for bit in 0 1; do
  file="$TMP/data/branch-$bit.elf"
  expected="$TMP/data/branch-$bit.expected.sens"
  test -s "$file" && test -s "$expected"
  chmod 700 "$file"
  timeout 5s readelf -h "$file" >"$TMP/elf.log"
  grep -Eq 'Type:.*EXEC' "$TMP/elf.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.log"
  timeout 5s readelf -l "$file" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$file" >"$TMP/code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/code" >"$TMP/asm.log"
  grep -Eq 'je[[:space:]]+' "$TMP/asm.log"
  grep -Eq 'jmp[[:space:]]+' "$TMP/asm.log"
  timeout 5s "$file" >"$TMP/actual.sens"
  cmp "$TMP/actual.sens" "$expected"
done
echo 'X64-ПЕРЕХОДИ-ELF-ГАРАЗД golden=2 negative=8 executed=2 bytes=T5M energy=NOT-MEASURED'
