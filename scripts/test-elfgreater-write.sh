#!/usr/bin/env bash
# G6.215 — реальний x86-64 signed D12 CMP/SETG повертає фізичний D1 T5M.
# Linux sys_write є host-механізмом: лише повний один байт означає успіх.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д12-БІЛЬШЕ-WRITE-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
for cmd in fpc timeout readelf objdump cmp grep mktemp; do
  command -v "$cmd" >/dev/null || {
    echo "Д12-БІЛЬШЕ-WRITE-БЛОК: немає $cmd" >&2
    exit 127
  }
done
test -c /dev/full
timeout 90s bash "$ROOT/scripts/check-pin.sh"
grep -Fq '(11011 (ук більше?) (укр більше?)' external/sens/lib/domains/d5.lisp

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units-cli" "$TMP/units-fixture" "$TMP/свідки"
FPC_BIN="${FPC:-fpc}"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units-cli" -FE"$TMP/bin" \
  -osensd12bilsh-elf "$ROOT/src/sensd12bilsh-elf.lpr" >"$TMP/build-cli.log"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units-fixture" -FE"$TMP/bin" \
  -otest-elfd12bilsh "$ROOT/scripts/test-elfd12bilsh.pas" >"$TMP/build-fixture.log"
timeout 30s "$TMP/bin/test-elfd12bilsh" "$TMP/свідки" \
  >"$TMP/cases.tsv" 2>"$TMP/fixture.err"
test "$(wc -l < "$TMP/cases.tsv")" -eq 12
grep -Fq 'ЕЛФ-Д12-БІЛЬШЕ-СВІДКИ-ГОТОВО пар=12' "$TMP/fixture.err"

GOOD=0
BAD=0
RECOVERY=0
for label in 01 03; do
  ELF="$TMP/$label.elf"
  timeout 15s "$TMP/bin/sensd12bilsh-elf" --більше-D12 \
    "$TMP/свідки/$label-l.sens" "$TMP/свідки/$label-r.sens" "$ELF" \
    >"$TMP/compiler.out" 2>"$TMP/compiler.err"
  test -x "$ELF"
  grep -Fq 'machine=CMP/SETG T5M=D1' "$TMP/compiler.out"
  timeout 5s readelf -h "$ELF" >"$TMP/elf.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/elf.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.header"

  tail -c +121 "$ELF" >"$TMP/image.code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/image.code" >"$TMP/disassembly"
  grep -Eiq 'setg[[:space:]]+al' "$TMP/disassembly"
  grep -Eiq 'cmp[[:space:]]+rax,0x1' "$TMP/disassembly"
  grep -Eiq '[[:space:]]jne[[:space:]]' "$TMP/disassembly"

  timeout 5s "$ELF" >"$TMP/actual.sens" 2>"$TMP/machine.err"
  cmp "$TMP/свідки/$label-expected.sens" "$TMP/actual.sens"
  test ! -s "$TMP/machine.err"
  test "$(wc -c < "$TMP/actual.sens")" -eq 1
  GOOD=$((GOOD+1))

  # -EBADF: закритий fd1 має дати host exit=2, не успіх D1.
  rc=0
  timeout 5s "$ELF" 1>&- 2>"$TMP/machine.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/machine.err"
  BAD=$((BAD+1))

  # -ENOSPC: /dev/full також відхиляється на машинному рівні.
  rc=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/machine.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/machine.err"
  BAD=$((BAD+1))

  timeout 5s "$ELF" >"$TMP/recovered.sens" 2>"$TMP/machine.err"
  cmp "$TMP/свідки/$label-expected.sens" "$TMP/recovered.sens"
  test ! -s "$TMP/machine.err"
  RECOVERY=$((RECOVERY+1))
done
test "$GOOD" -eq 2 && test "$BAD" -eq 4 && test "$RECOVERY" -eq 2
echo "Д12-БІЛЬШЕ-WRITE-ГАРАЗД positives=$GOOD negatives=$BAD recovery=$RECOVERY D1=T5M machine=CMP/SETG/CMP/JNE oracle=NOT-RUN energy=NOT-MEASURED"
# Тип: borrowed RawByteString D12 на вході builder; FPC-managed owned ELF bytes
# на виході. Механічні байти D1 взяті зі спільного T5M codec, а не з Boolean.
# 1) Чому sys_write RAX повинен бути рівно 1?
# 2) Чому Linux exit=2 не є D1:1?
# 3) Чому потрібний recovery після обох негативів?
# 4) Де зберігаються exact-width бітові слова?
