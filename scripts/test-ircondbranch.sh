#!/usr/bin/env bash
# G6.100 — pinned ExactIR COND -> host JZ/JMP rel32 -> real ELF64 PIE.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'IR-ПЕРЕХОДИ-БЛОК: потрібен Linux x86_64' >&2; exit 127;
}
for tool in git fpc timeout cmp readelf objdump tail mktemp grep; do
  command -v "$tool" >/dev/null || {
    echo "IR-ПЕРЕХОДИ-БЛОК: немає $tool" >&2; exit 127;
  }
done
test "$(git -C external/sens rev-parse HEAD)" = 2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 120s bash scripts/check-pin.sh
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || {
  echo 'IR-ПЕРЕХОДИ-БЛОК: потрібен незалежний SENS REPL' >&2; exit 127;
}
test "$(git -C sens-oracle rev-parse HEAD)" = 2c498b35af53c085450eac6f51b87facf7f9aa47
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  for path in "$TMP"/build.log "$TMP"/test.log "$TMP"/test.err; do
    [[ ! -s "$path" ]] || { echo "--- $path" >&2; tail -n 70 "$path" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/phys"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-ircondbranch \
  "$ROOT/scripts/test-ircondbranch.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 60s "$TMP/bin/test-ircondbranch" "$TMP/phys" \
  >"$TMP/test.log" 2>"$TMP/test.err" || {
    cat "$TMP/test.log" "$TMP/test.err" >&2; exit 1;
  }
grep -Fq 'IR-ПЕРЕХОДИ-ГАРАЗД elfs=13 negative=11' "$TMP/test.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
COUNT=0
for exe in "$TMP/phys"/*.branch.elf; do
  stem="${exe%.branch.elf}"
  old="${stem}.legacy.elf"
  source="${stem}.sens"
  expected="${stem}.expected.sens"
  oracle_expected="${stem}.oracle.txt"
  test -s "$exe" && test -s "$old" && test -s "$source"
  test -s "$expected" && test -s "$oracle_expected"
  chmod 700 "$exe" "$old"
  timeout 5s readelf -h "$exe" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 5s readelf -l "$exe" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$exe" >"$TMP/code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/code" >"$TMP/asm.log"
  if [[ "${stem##*/}" != порожня ]]; then
    grep -Eq 'je[[:space:]]+' "$TMP/asm.log"
    grep -Eq 'jmp[[:space:]]+' "$TMP/asm.log"
  fi
  timeout 5s "$exe" >"$TMP/current.sens" 2>"$TMP/machine.err"
  test ! -s "$TMP/machine.err"
  cmp "$TMP/current.sens" "$expected"
  timeout 5s "$old" >"$TMP/old.sens" 2>"$TMP/old.err"
  test ! -s "$TMP/old.err"
  cmp "$TMP/current.sens" "$TMP/old.sens"
  timeout 60s "$ORACLE" "$source" >"$TMP/oracle.out" \
    2>"$TMP/oracle.err"
  test ! -s "$TMP/oracle.err"
  cmp "$TMP/oracle.out" "$oracle_expected"
  COUNT=$((COUNT+1))
done
test "$COUNT" -eq 13
echo 'IR-ПЕРЕХОДИ-ELF-ГАРАЗД фізичних=13 машинних-ELF=26 oracle-SENS=13 негативів=11 checked-FPC=так енергія=НЕ-ВИМІРЮВАЛАСЯ'
