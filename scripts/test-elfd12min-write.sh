#!/usr/bin/env bash
# G6.216: реальні x86-64 ELF64 відхиляють неповний фізичний запис D12.
# Це тест Linux host ABI; незалежний SENS oracle перевіряється окремо.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д12-НАЙМЕНШЕ-WRITE-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
for cmd in fpc timeout readelf objdump cmp grep mktemp; do
  command -v "$cmd" >/dev/null || {
    echo "Д12-НАЙМЕНШЕ-WRITE-БЛОК: відсутній $cmd" >&2
    exit 127
  }
done
test -c /dev/full
timeout 90s bash "$ROOT/scripts/check-pin.sh"
grep -Fq '(110101 (ук найменше) (укр найменше)' external/sens/lib/domains/d6.lisp

TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then for p in "$TMP"/*.build.log "$TMP"/*.err; do if [[ -s "$p" ]]; then echo "--- $p" >&2; tail -n 20 "$p" >&2; fi; done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units-cli" "$TMP/units-fixtures" "$TMP/свідки"
FPC_BIN="${FPC:-fpc}"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units-cli" -FE"$TMP/bin" \
  -osensd12naimensheelf "$ROOT/src/sensd12naimensheelf.lpr" \
  >"$TMP/cli.build.log" 2>&1
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units-fixtures" -FE"$TMP/bin" \
  -otest-elfd12min-fixtures "$ROOT/scripts/test-elfd12min-fixtures.pas" \
  >"$TMP/fixtures.build.log" 2>&1
timeout 30s "$TMP/bin/test-elfd12min-fixtures" "$TMP/свідки" \
  >"$TMP/fixtures.tsv" 2>"$TMP/fixtures.err"
grep -Fq 'D12-MIN-FIXTURES-OK cases=16' "$TMP/fixtures.err"

GOOD=0
BAD=0
RECOVERY=0
# 04: два додатні аргументи; 13: крайній від'ємний і додатний.
for label in 04 13; do
  ELF="$TMP/$label.elf"
  timeout 20s "$TMP/bin/sensd12naimensheelf" --найменше-D12 \
    "$TMP/свідки/$label-l.sens" "$TMP/свідки/$label-r.sens" "$ELF" \
    >"$TMP/compiler.out" 2>"$TMP/compiler.err"
  test -x "$ELF"
  test ! -s "$TMP/compiler.err"
  grep -Fq 'D12-MIN-ELF-OK machine=CMP/CMOVG' "$TMP/compiler.out"
  timeout 5s readelf -h "$ELF" >"$TMP/header.txt"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/header.txt"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.txt"
  dd if="$ELF" of="$TMP/code.bin" bs=1 skip=120 status=none
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/code.bin" >"$TMP/disassembly"
  grep -Eiq 'cmov(g|nle)[[:space:]]+eax,ecx' "$TMP/disassembly"
  grep -Eiq 'cmp[[:space:]]+rax,0x3' "$TMP/disassembly"
  grep -Eiq '[[:space:]]jne[[:space:]]' "$TMP/disassembly"

  timeout 5s "$ELF" >"$TMP/actual.sens" 2>"$TMP/machine.err"
  cmp "$TMP/свідки/$label-expected.sens" "$TMP/actual.sens"
  test "$(wc -c <"$TMP/actual.sens")" -eq 3
  test ! -s "$TMP/machine.err"
  GOOD=$((GOOD+1))

  # -EBADF: закритий fd1 мусить дати host exit 2, без stderr.
  rc=0
  timeout 5s "$ELF" 1>&- 2>"$TMP/machine.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/machine.err"
  BAD=$((BAD+1))

  # -ENOSPC: /dev/full мусить бути помилкою, не удаваним успіхом.
  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/machine.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/machine.err"
  BAD=$((BAD+1))

  timeout 5s "$ELF" >"$TMP/recovered.sens" 2>"$TMP/machine.err"
  cmp "$TMP/свідки/$label-expected.sens" "$TMP/recovered.sens"
  cmp "$TMP/actual.sens" "$TMP/recovered.sens"
  test ! -s "$TMP/machine.err"
  RECOVERY=$((RECOVERY+1))
done
test "$GOOD" -eq 2 && test "$BAD" -eq 4 && test "$RECOVERY" -eq 2
echo "Д12-НАЙМЕНШЕ-WRITE-ГАРАЗД positives=$GOOD negatives=$BAD recovery=$RECOVERY machine=CMP/CMOVG/CMP/JNE D12=T5M oracle=NOT-RUN energy=NOT-MEASURED"
