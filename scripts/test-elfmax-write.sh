#!/usr/bin/env bash
# G6.216 — справжній x86-64 CMOVL та перевірка повного sys_write D12 T5M.
# Це host ABI guard; закон SENS залишається у pinned external/sens.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д12-МАКСИМУМ-WRITE-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
for tool in fpc timeout readelf objdump cmp mktemp grep tail; do
  command -v "$tool" >/dev/null || {
    echo "Д12-МАКСИМУМ-WRITE-БЛОК: не знайдено $tool" >&2
    exit 127
  }
done
test -c /dev/full
timeout 90s bash "$ROOT/scripts/check-pin.sh"
grep -Fq '(110111 (ук найбільше) (укр найбільше)' external/sens/lib/domains/d6.lisp

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/свідки"
FPC_BIN="${FPC:-fpc}"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osensd12naibilsheelf "$ROOT/src/sensd12naibilsheelf.lpr" >"$TMP/compile.log" 2>&1
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-elfd12max-fixtures "$ROOT/scripts/test-elfd12max-fixtures.pas" >"$TMP/fixtures-build.log" 2>&1
timeout 30s "$TMP/bin/test-elfd12max-fixtures" "$TMP/свідки" \
  >"$TMP/cases.tsv" 2>"$TMP/fixtures.err"
grep -Fq 'D12-MAX-FIXTURES-OK cases=16' "$TMP/fixtures.err"

GOOD=0
BAD=0
RECOVERY=0
for label in 04 13; do
  ELF="$TMP/$label.elf"
  timeout 15s "$TMP/bin/sensd12naibilsheelf" --найбільше-D12 \
    "$TMP/свідки/$label-l.sens" "$TMP/свідки/$label-r.sens" "$ELF" \
    >"$TMP/compiler.out" 2>"$TMP/compiler.err"
  test -x "$ELF"
  grep -Fq 'machine-cmp-cmovl=1' "$TMP/compiler.out"
  timeout 5s readelf -h "$ELF" >"$TMP/elf.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/elf.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.header"
  tail -c +121 "$ELF" >"$TMP/image.code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/image.code" >"$TMP/disassembly"
  grep -Eiq 'cmov(l|nge)[[:space:]]+eax,ecx' "$TMP/disassembly"
  grep -Eiq 'cmp[[:space:]]+rax,0x3' "$TMP/disassembly"
  grep -Eiq '[[:space:]]jne[[:space:]]' "$TMP/disassembly"

  timeout 5s "$ELF" >"$TMP/actual.sens" 2>"$TMP/machine.err"
  cmp "$TMP/свідки/$label-expected.sens" "$TMP/actual.sens"
  test "$(wc -c <"$TMP/actual.sens")" -eq 3
  test ! -s "$TMP/machine.err"
  GOOD=$((GOOD+1))

  # Закритий stdout: write повертає -EBADF, успіх заборонений.
  rc=0
  timeout 5s "$ELF" 1>&- 2>"$TMP/machine.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/machine.err"
  BAD=$((BAD+1))

  # /dev/full: write повертає -ENOSPC, успіх заборонений.
  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/machine.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/machine.err"
  BAD=$((BAD+1))

  # Невдала публікація не змінює ELF чи фізичний результат.
  timeout 5s "$ELF" >"$TMP/recovered.sens" 2>"$TMP/machine.err"
  cmp "$TMP/свідки/$label-expected.sens" "$TMP/recovered.sens"
  test ! -s "$TMP/machine.err"
  RECOVERY=$((RECOVERY+1))
done

test "$GOOD" -eq 2 && test "$BAD" -eq 4 && test "$RECOVERY" -eq 2
echo "Д12-МАКСИМУМ-WRITE-ГАРАЗД positives=$GOOD negatives=$BAD recovery=$RECOVERY D12=T5M machine=CMP/CMOVL/CMP/JNE oracle=NOT-RUN energy=NOT-MEASURED"
