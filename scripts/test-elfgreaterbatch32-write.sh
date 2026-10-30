#!/usr/bin/env bash
# G6.222 — реальний машинний fail-closed для пакета 32 canonical D1 T5M.
# Точне signed D12 рішення лишається в наявному CPU CMP/SETG backend.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д12-БІЛЬШЕ32-WRITE-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
for cmd in fpc timeout readelf objdump cmp grep mktemp python3; do
  command -v "$cmd" >/dev/null || {
    echo "Д12-БІЛЬШЕ32-WRITE-БЛОК: відсутній $cmd" >&2
    exit 127
  }
done
test -c /dev/full
timeout 90s bash scripts/check-pin.sh

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/u-cli" "$TMP/u-fixtures" "$TMP/frames"
FPC_BIN="${FPC:-fpc}"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/u-cli" -FE"$TMP/bin" \
  -osensd12bilshpaket32elf "$ROOT/src/sensd12bilshpaket32elf.lpr" \
  >"$TMP/cli-build.log" 2>&1
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/u-fixtures" -FE"$TMP/bin" \
  -otest-elfd12bilshpaket32 "$ROOT/scripts/test-elfd12bilshpaket32.pas" \
  >"$TMP/fixture-build.log" 2>&1
timeout 30s "$TMP/bin/test-elfd12bilshpaket32" "$TMP/frames" \
  >"$TMP/cases.tsv" 2>"$TMP/fixtures.err"
grep -Fq 'D12-BILSH-PAKET32-FIXTURES-OK cases=16 batches=2 negatives=13' "$TMP/fixtures.err"
test "$(wc -l < "$TMP/cases.tsv")" -eq 16
ELF="$TMP/32-comparisons.elf"
timeout 15s "$TMP/bin/sensd12bilshpaket32elf" \
  --зібрати-D12-більше-пакет "$ELF" >"$TMP/compiler.out" 2>"$TMP/compiler.err"
test -x "$ELF"
test ! -s "$TMP/compiler.err"
grep -Fq 'пар=32 machine=CMP/SETG D1=T5M' "$TMP/compiler.out"
timeout 5s readelf -h "$ELF" >"$TMP/elf.header"
grep -Eq 'Type:[[:space:]]+DYN' "$TMP/elf.header"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.header"

# Машинний доказ: exact 32 у RAX після syscall, fail-closed JNE.
python3 - "$ELF" <<'PY'
from pathlib import Path
import sys
data=Path(sys.argv[1]).read_bytes()
assert data[:4]==b'\x7fELF'
code=data[120:]
assert b'\x45\x39\xc8\x0f\x9f\xc0\x0f\xb6\xc0' in code, 'немає signed CMP/SETG/MOVZX'
assert b'\xba\x20\x00\x00\x00\x0f\x05\x48\x83\xf8\x20\x75\x09' in code, 'немає write(32) / RAX=32 / JNE'
assert b'\xb8\x3c\x00\x00\x00\x31\xff\x0f\x05\xb8\x3c\x00\x00\x00\xbf\x02\x00\x00\x00\x0f\x05' in code, 'немає успіх/помилка Linux exit'
PY
dd if="$ELF" of="$TMP/code" bs=1 skip=120 count=620 status=none
timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
  "$TMP/code" >"$TMP/disassembly"
grep -Eiq 'setg[[:space:]]+al' "$TMP/disassembly"
grep -Eiq 'cmp[[:space:]]+rax,0x20' "$TMP/disassembly"
grep -Eiq '[[:space:]]jne[[:space:]]' "$TMP/disassembly"

GOOD=0
NEG=0
RECOVERY=0
for label in batch-a batch-b; do
  SOURCE="$TMP/frames/$label.frame"
  EXPECTED="$TMP/frames/$label.expected"
  test "$(wc -c < "$SOURCE")" -eq 192
  test "$(wc -c < "$EXPECTED")" -eq 32

  timeout 5s "$ELF" <"$SOURCE" >"$TMP/actual.sens" 2>"$TMP/machine.err"
  cmp "$EXPECTED" "$TMP/actual.sens"
  test ! -s "$TMP/machine.err"
  GOOD=$((GOOD+1))

  # -EBADF: відсутній stdout — код 2 замість неправдивого успіху.
  rc=0
  timeout 5s "$ELF" <"$SOURCE" 1>&- 2>"$TMP/machine.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/machine.err"
  NEG=$((NEG+1))

  # -ENOSPC: Linux /dev/full не опублікував повні 32 байти.
  rc=0
  timeout 5s "$ELF" <"$SOURCE" >/dev/full 2>"$TMP/machine.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/machine.err"
  NEG=$((NEG+1))

  timeout 5s "$ELF" <"$SOURCE" >"$TMP/recovered.sens" 2>"$TMP/machine.err"
  cmp "$EXPECTED" "$TMP/recovered.sens"
  test ! -s "$TMP/machine.err"
  RECOVERY=$((RECOVERY+1))
done
test "$GOOD" -eq 2 && test "$NEG" -eq 4 && test "$RECOVERY" -eq 2
echo "Д12-БІЛЬШЕ32-WRITE-ГАРАЗД positives=$GOOD negatives=$NEG recovery=$RECOVERY T5M=D1x32 machine=CMP/SETG/CMP/JNE oracle=NOT-RUN energy=NOT-MEASURED"
# 1) Чому 32 D1 — це рівно 32 packed T5M байти?
# 2) Хто визначає signed D12 закон, а хто Linux sys_write?
# 3) Чому closed fd1 не може мати статус 0?
# 4) Чому два recovery запускають незмінний ELF?
