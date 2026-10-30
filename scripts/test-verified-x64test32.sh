#!/usr/bin/env bash
# G6.254: TEST r32,r32 — справжні FPC, GNU as, ELF64 і фізичні T5M.
# Host ISA не є SENS законом; energy=NOT-MEASURED.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
bash "$ROOT/scripts/check-pin.sh"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'TEST32-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=${FPC:-fpc}
for cmd in "$FPC_BIN" as objcopy readelf cmp timeout stat; do
  command -v "$cmd" >/dev/null || {
    echo "TEST32-БЛОК: відсутній $cmd" >&2; exit 127;
  }
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units"
timeout 120s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP" -otest-x64test32 \
  "$ROOT/scripts/test-x64test32.pas"
HEAPTRC="log=$TMP/heap.log" timeout 45s "$TMP/test-x64test32" "$TMP" \
  >"$TMP/protocol" 2>"$TMP/stderr"
grep -Fxq 'G6.254-X64TEST32-PASS matrix=64 golden=2 negative=4 recovery=1' "$TMP/protocol"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"

# ОДИН незалежний GNU-as/objcopy збір всіх 64 TEST, без циклу 64 компіляцій.
regs=(eax ecx edx ebx esp ebp esi edi)
{
  printf '.intel_syntax noprefix\n.text\n.global _start\n_start:\n'
  for dest in "${regs[@]}"; do
    for src in "${regs[@]}"; do
      printf '  test %s, %s\n' "$dest" "$src"
    done
  done
} >"$TMP/golden.s"
timeout 30s as --64 -o "$TMP/golden.o" "$TMP/golden.s"
objcopy -O binary --only-section=.text "$TMP/golden.o" "$TMP/golden.bin"
[[ "$(stat -c%s "$TMP/matrix.bin")" == 128 ]]
[[ "$(stat -c%s "$TMP/golden.bin")" == 128 ]]
cmp "$TMP/matrix.bin" "$TMP/golden.bin"

# TEST реально формує ZF → SETE → фізичний байт pinned T5M W1.
for label in nulyovyi nenulyovyi; do
  elf="$TMP/$label.elf"
  chmod u+x "$elf"
  readelf -W -h "$elf" >"$TMP/header"
  readelf -W -l "$elf" >"$TMP/phdr"
  grep -Eq 'Type:.*DYN' "$TMP/header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header"
  grep -Fq 'LOAD' "$TMP/phdr"
  timeout 5s "$elf" >"$TMP/actual.sens"
  cmp "$TMP/actual.sens" "$TMP/$label.expected.sens"

  # Успіх sys_write визначає машина, а не мок чи послаблений shell.
  set +e
  timeout 5s "$elf" >&- 2>/dev/null
  closed_rc=$?
  timeout 5s "$elf" >/dev/full 2>/dev/null
  full_rc=$?
  set -e
  [[ "$closed_rc" == 1 && "$full_rc" == 1 ]] || {
    echo "TEST32-ЗБІЙ: stdout guard $label closed=$closed_rc full=$full_rc" >&2
    exit 1
  }
done
echo 'VERIFIED-X64TEST32-PASS matrix=64 bytes=128 elf=2 negative=4 stdout=closed/full heap=0 energy=NOT-MEASURED'
