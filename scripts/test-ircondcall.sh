#!/usr/bin/env bash
# G6.122 — verified pinned ExactIR D3 COND -> shared x86 CALL + JZ/JMP.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export LC_ALL=C.UTF-8 LANG=C.UTF-8
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'G6_122_BLOCK: Linux x86_64 required' >&2; exit 127;
}
for tool in fpc timeout git cmp readelf objdump grep tail mktemp; do
  command -v "$tool" >/dev/null || {
    echo "G6_122_BLOCK: missing $tool" >&2; exit 127;
  }
done
test "$(git -C external/sens rev-parse HEAD)" = 2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 120s bash scripts/check-pin.sh
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE"
test "$(git -C sens-oracle rev-parse HEAD)" = 2c498b35af53c085450eac6f51b87facf7f9aa47
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  for f in "$TMP"/*.log "$TMP"/*.err; do
    if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -n 85 "$f" >&2; fi
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/phys" "$TMP/bin" "$TMP/units"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-ircondcall \
  "$ROOT/scripts/test-ircondcall.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2;exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 90s \
  "$TMP/bin/test-ircondcall" "$TMP/phys" >"$TMP/test.log" \
  2>"$TMP/test.err" || {
    cat "$TMP/test.log" "$TMP/test.err" >&2;exit 1;
  }
grep -Fq 'G6_122_OK ELF=21 NEG=17 CALL_SITES=' "$TMP/test.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
COUNT=0
for exe in "$TMP"/phys/*.call.elf; do
  stem="${exe%.call.elf}"
  old="${stem}.old.elf"
  source="${stem}.sens"
  expected="${stem}.expected.sens"
  oracle_text="${stem}.oracle.txt"
  test -s "$exe" && test -s "$old" && test -s "$source"
  test -s "$expected" && test -s "$oracle_text"
  chmod 700 "$exe" "$old"
  timeout 5s readelf -h "$exe" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 5s readelf -l "$exe" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$exe" >"$TMP/machine.bin"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine.bin" >"$TMP/asm.log"
  grep -Eq '[[:space:]]ret' "$TMP/asm.log"
  grep -Eq '[[:space:]]sete[[:space:]]' "$TMP/asm.log"
  if [[ "${stem##*/}" != порожня ]]; then
    grep -Eq '[[:space:]]je[[:space:]]' "$TMP/asm.log"
    grep -Eq '[[:space:]]jmp[[:space:]]' "$TMP/asm.log"
  fi
  timeout 5s "$exe" >"$TMP/current.sens" 2>"$TMP/native.err"
  test ! -s "$TMP/native.err"
  cmp "$TMP/current.sens" "$expected"
  timeout 5s "$old" >"$TMP/old.sens" 2>"$TMP/old.err"
  test ! -s "$TMP/old.err"
  cmp "$TMP/current.sens" "$TMP/old.sens"
  timeout 60s "$ORACLE" "$source" >"$TMP/oracle.txt" 2>"$TMP/oracle.err"
  test ! -s "$TMP/oracle.err"
  cmp "$TMP/oracle.txt" "$oracle_text"
  COUNT=$((COUNT+1))
done
test "$COUNT" -eq 21
echo 'G6_122_ELF_OK checked-FPC=YES ELF_NEW=21 ELF_BASELINE=21 PINNED_SENS=21 NEGATIVE=17 SHARED_EQ=CALL_RET ENERGY=NOT_MEASURED'
