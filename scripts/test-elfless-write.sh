#!/usr/bin/env bash
# G6.214 — фізичний D1 stdout після реального x86-64 signed D12 CMP/SETL.
# Перевіряємо host Linux sys_write без нового SENS evaluator або закону.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д12-МЕНШЕ-WRITE-БЛОК: Linux x86-64 потрібен' >&2
  exit 127
}
for name in fpc timeout readelf objdump cmp grep tail mktemp; do
  command -v "$name" >/dev/null || {
    echo "Д12-МЕНШЕ-WRITE-БЛОК: не знайдено $name" >&2
    exit 127
  }
done
test -c /dev/full
timeout 90s bash "$ROOT/scripts/check-pin.sh"
grep -Fq '(11010 (ук менше?) (укр менше?)' external/sens/lib/domains/d5.lisp

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/свідки"
FPC_BIN="${FPC:-fpc}"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osensd12mensheelf "$ROOT/src/sensd12mensheelf.lpr" >"$TMP/compile.log"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-elfd12menshe-fixtures "$ROOT/scripts/test-elfd12menshe-fixtures.pas" \
  >"$TMP/fixture-build.log"
timeout 30s "$TMP/bin/test-elfd12menshe-fixtures" "$TMP/свідки" \
  >"$TMP/cases.tsv" 2>"$TMP/fixtures.err"
grep -Fq 'D12-LESS-FIXTURES-OK cases=14' "$TMP/fixtures.err"

GOOD=0
BAD=0
RECOVERY=0
for label in 01 03; do
  ELF="$TMP/$label.elf"
  timeout 15s "$TMP/bin/sensd12mensheelf" --менше-D12 \
    "$TMP/свідки/$label-l.sens" "$TMP/свідки/$label-r.sens" "$ELF" \
    >"$TMP/compiler.out" 2>"$TMP/compiler.err"
  test -x "$ELF"
  test ! -s "$TMP/compiler.err" || grep -Fq '0 unfreed memory blocks' "$TMP/compiler.err"
  grep -Fq 'machine=CMP/SETL' "$TMP/compiler.out"
  timeout 5s readelf -h "$ELF" >"$TMP/elf.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/elf.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.header"

  tail -c +121 "$ELF" >"$TMP/image.code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/image.code" >"$TMP/disassembly"
  grep -Eiq 'setl[[:space:]]+al' "$TMP/disassembly"
  grep -Eiq 'cmp[[:space:]]+rax,0x1' "$TMP/disassembly"
  grep -Eiq '[[:space:]]jne[[:space:]]' "$TMP/disassembly"

  timeout 5s "$ELF" >"$TMP/actual.sens" 2>"$TMP/machine.err"
  cmp "$TMP/свідки/$label-expected.sens" "$TMP/actual.sens"
  test ! -s "$TMP/machine.err"
  test "$(wc -c < "$TMP/actual.sens")" -eq 1
  GOOD=$((GOOD+1))

  # Закритий stdout: Linux write повертає -EBADF, а ELF має exit(2).
  rc=0
  timeout 5s "$ELF" 1>&- 2>"$TMP/machine.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/machine.err"
  BAD=$((BAD+1))

  # /dev/full: Linux write повертає -ENOSPC, теж exit(2).
  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/machine.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/machine.err"
  BAD=$((BAD+1))

  # Негатив не повинен псувати незмінний машинний образ або D1 T5M.
  timeout 5s "$ELF" >"$TMP/recovered.sens" 2>"$TMP/machine.err"
  cmp "$TMP/свідки/$label-expected.sens" "$TMP/recovered.sens"
  test ! -s "$TMP/machine.err"
  RECOVERY=$((RECOVERY+1))
done

test "$GOOD" -eq 2 && test "$BAD" -eq 4 && test "$RECOVERY" -eq 2
echo "Д12-МЕНШЕ-WRITE-ГАРАЗД positives=$GOOD negatives=$BAD recovery=$RECOVERY D1=T5M machine=CMP/SETL/CMP/JNE oracle=NOT-RUN energy=NOT-MEASURED"
