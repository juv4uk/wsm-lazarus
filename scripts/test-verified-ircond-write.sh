#!/usr/bin/env bash
# G6.267 — справжній checked FPC та Linux ELF64 для фізичного D3:110.
# Без Rust/Zig, нових workflow, підміни SENS-законів і фальшивих джоулів.
# Кожна програма проходить чинний pinned LowerPinnedIRCond, не echo-loop.
# Успіх Linux write(1,rsp,1) потребує RAX=1; інакше host exit(2).
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'G6.267-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc git timeout mktemp readelf objdump cmp grep tail; do
  command -v "$tool" >/dev/null || {
    echo "G6.267-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/sync-authority.sh
timeout 90s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = \
  2c498b35af53c085450eac6f51b87facf7f9aa47
TMP="$(mktemp -d)"
cleanup() {
  local status=$?
  if ((status)); then
    echo "G6.267-ПРОВАЛ: code=$status" >&2
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || tail -n 70 "$f" >&2
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-ircond "$ROOT/scripts/test-ircond.pas" \
  >"$TMP/build.log" 2>&1 || { tail -n 70 "$TMP/build.log" >&2; exit 1; }
HEAPTRC="log=$TMP/heap.log" timeout 90s "$TMP/bin/test-ircond" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err" || {
    cat "$TMP/fixtures.log" "$TMP/fixtures.err" >&2; exit 1;
  }
grep -Fq 'ELF64-PIE=28' "$TMP/fixtures.log"
grep -Fq 'негативи=23' "$TMP/fixtures.log"
test ! -s "$TMP/fixtures.err"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"

# 0 гілок; перший істинний; остання з 32; D3:000 після 32;
# вкладені D3:101 для повного 32-гілкового бюджету.
cases=(порожня одна-істинна-1 тридцятьдві-остання
       тридцятьдві-вичерпано тридцятьдві-вкладені-остання)
PASS=0; CLOSED=0; FULL=0; RECOVERY=0
for name in "${cases[@]}"; do
  exe="$ROOT/build/m0.2/ircond/$name.elf"
  expected="$ROOT/build/m0.2/ircond/$name.expected.sens"
  source="$ROOT/build/m0.2/ircond/$name.sens"
  test -s "$exe" && test -s "$expected" && test -s "$source"
  chmod 700 "$exe"
  timeout 5s readelf -h "$exe" >"$TMP/elf.log"
  grep -Eq 'Type:.*DYN' "$TMP/elf.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.log"
  timeout 5s readelf -l "$exe" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$exe" >"$TMP/code.bin"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/code.bin" >"$TMP/disasm.log"
  grep -Eq 'cmp[[:space:]]+rax,rdx' "$TMP/disasm.log"
  grep -Eq 'jne[[:space:]]+' "$TMP/disasm.log"
  grep -Eq 'mov[[:space:]]+edi,0x2' "$TMP/disasm.log"

  timeout 5s "$exe" >"$TMP/output.sens" 2>"$TMP/normal.err"
  cmp "$expected" "$TMP/output.sens"
  test ! -s "$TMP/normal.err"
  PASS=$((PASS+1))

  rc=0
  timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$exe" \
    2>"$TMP/closed.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/closed.err"
  CLOSED=$((CLOSED+1))

  rc=0
  timeout 5s "$exe" >/dev/full 2>"$TMP/full.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/full.err"
  FULL=$((FULL+1))

  timeout 5s "$exe" >"$TMP/recovered.sens" 2>"$TMP/recovery.err"
  cmp "$expected" "$TMP/recovered.sens"
  test ! -s "$TMP/recovery.err"
  RECOVERY=$((RECOVERY+1))
done
test "$PASS" -eq 5 && test "$CLOSED" -eq 5 &&
test "$FULL" -eq 5 && test "$RECOVERY" -eq 5
echo 'G6.267-VERIFIED-IRCOND-WRITE-PASS FPC=checked physical=28 negatives=23 ELF64=5 closed=5 full=5 recovery=5 oracle=NOT-RUN energy=NOT-MEASURED'
