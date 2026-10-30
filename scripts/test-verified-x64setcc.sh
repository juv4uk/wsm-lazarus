#!/usr/bin/env bash
# G6.247 — один перевірений FPC-прохід для x86-64 SETcc і 16 ELF64 PIE.
# Додається до наявного verified-агрегатора, без нового CI/apt.
# SETcc — механізм CPU; це НЕ закон, не проєкція та не оракул SENS.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'X64-SETCC-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in timeout fpc cmp git readelf objdump mktemp grep tail chmod; do
  command -v "$tool" >/dev/null || {
    echo "X64-SETCC-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
cleanup() {
  local rc=$? file
  if ((rc)); then
    echo "X64-SETCC-ПРОВАЛ код=$rc" >&2
    for file in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$file" ]] || { echo "--- $file" >&2; tail -n 24 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
timeout 180s "${FPC:-fpc}" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64setcc \
  "$ROOT/scripts/test-x64setcc.pas" >"$TMP/fpc.log" 2>&1 || {
    cat "$TMP/fpc.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 40s "$TMP/bin/test-x64setcc" \
  "$TMP/physical" >"$TMP/test.log" 2>"$TMP/test.err"
grep -Fq 'X64-SETCC-ПЕРЕВІРЕНО golden=4 negative=5 recovery=1 elf=16' "$TMP/test.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
count=0
closed=0
full=0
recovered=0
for cc in 4 5 12 13; do
  case "$cc" in
    4) mnemonic='sete';;
    5) mnemonic='setne';;
    12) mnemonic='setl';;
    13) mnemonic='setge';;
  esac
  for a in 0 1; do
    for b in 0 1; do
      elf="$TMP/physical/cc$cc-$a-$b.elf"
      expected="$TMP/physical/cc$cc-$a-$b.expected.sens"
      test -s "$elf" && test -s "$expected"
      timeout 5s readelf -h "$elf" >"$TMP/elf.log"
      grep -Eq 'Type:[[:space:]]+DYN' "$TMP/elf.log"
      grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.log"
      timeout 5s readelf -l "$elf" >"$TMP/segments.log"
      ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
      tail -c +121 "$elf" >"$TMP/machine.bin"
      timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
        "$TMP/machine.bin" >"$TMP/asm.log"
      grep -Eq "$mnemonic[[:space:]]+al" "$TMP/asm.log"
      grep -Eq 'cmp[[:space:]]+eax,ecx' "$TMP/asm.log"
      chmod 700 "$elf"
      timeout 5s "$elf" >"$TMP/actual.sens" 2>"$TMP/machine.err"
      test ! -s "$TMP/machine.err"
      cmp "$expected" "$TMP/actual.sens"
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
      timeout 5s "$elf" >"$TMP/recovery.sens" 2>"$TMP/recovery.err"
      test ! -s "$TMP/recovery.err"
      cmp "$expected" "$TMP/recovery.sens"
      recovered=$((recovered+1))
    done
  done
done
test "$count" -eq 16 && test "$closed" -eq 16 &&
  test "$full" -eq 16 && test "$recovered" -eq 16
echo "VERIFIED-X64-SETCC-PASS fpc=checked elf=$count closed=$closed full=$full recovery=$recovered golden=4 negative=5 physical=T5M oracle=NOT-RUN energy=NOT-MEASURED"
