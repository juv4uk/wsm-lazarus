#!/usr/bin/env bash
# G6.75 — pinned Skylake ISA, тільки 15 байтів real D12 ADD ELF64.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
for tool in fpc timeout python3 git readelf objdump dd cmp; do
  command -v "$tool" >/dev/null || { echo "СКАЙЛЕЙК-БЛОК: немає $tool" >&2; exit 127; }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
ORACLE="$ROOT/sens-oracle/target/release/sens"
test -x "$ORACLE"
# Семантику підтверджує незмінний чинний 9-випадковий pinned REPL.
SENS_ORACLE_BIN="$ORACLE" timeout 240s bash scripts/test-elfd12add.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/свідки"
FPC_BIN=$(printenv FPC || printf fpc)
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osensd12elf "$ROOT/src/sensd12elf.lpr"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-elfd12add "$ROOT/scripts/test-elfd12add.pas"
timeout 20s "$TMP/bin/test-elfd12add" "$TMP/свідки"
PASS=0
for row in '02:31:42' '03:-12:7' '05:-2048:2047' '09:-2047:-1'; do
  IFS=: read -r name left right <<< "$row"
  timeout 20s "$TMP/bin/sensd12elf" --додати-D12 \
    "$TMP/свідки/$name-l.sens" "$TMP/свідки/$name-r.sens" \
    "$TMP/$name.elf" >"$TMP/$name.out" 2>"$TMP/$name.err"
  test ! -s "$TMP/$name.err"
  test -x "$TMP/$name.elf"
  readelf -h "$TMP/$name.elf" >"$TMP/$name.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$name.header"
  grep -F 'Advanced Micro Devices X86-64' "$TMP/$name.header" >/dev/null
  timeout 5s "$TMP/$name.elf" >"$TMP/$name.actual.sens" \
    2>"$TMP/$name.machine.err"
  test ! -s "$TMP/$name.machine.err"
  cmp "$TMP/$name.actual.sens" "$TMP/свідки/$name-expected.sens"
  timeout 20s python3 scripts/check-skylake-d12-elf.py \
    --корінь "$ROOT" --elf "$TMP/$name.elf" \
    --лівий "$left" --правий "$right" >"$TMP/$name.audit.out"
  grep -Fq 'СКАЙЛЕЙК-ISA-ГАРАЗД' "$TMP/$name.audit.out"
  PASS=$((PASS+1))
done
test "$PASS" -eq 4
# НЕ дизасемблюємо дані T5M lookup як інструкції.
dd if="$TMP/02.elf" of="$TMP/пролог.bin" bs=1 skip=120 count=15 status=none
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/пролог.bin" >"$TMP/пролог.asm"
grep -Eiq 'mov[[:space:]]+eax,' "$TMP/пролог.asm"
grep -Eiq 'add[[:space:]]+eax,' "$TMP/пролог.asm"
grep -Eiq 'and[[:space:]]+eax,' "$TMP/пролог.asm"
timeout 20s python3 scripts/check-skylake-d12-elf.py \
  --корінь "$ROOT" --elf "$TMP/02.elf" --лівий 31 --правий 42 \
  --самотест >"$TMP/самотест"
grep -Fq 'негативів=29' "$TMP/самотест"
printf '\177ELF' >"$TMP/підміна.elf"
status=0
timeout 20s python3 scripts/check-skylake-d12-elf.py \
  --корінь "$ROOT" --elf "$TMP/підміна.elf" --лівий 31 --правий 42 \
  >"$TMP/відмова.out" 2>"$TMP/відмова.err" || status=$?
test "$status" -eq 2 && test ! -s "$TMP/відмова.out"
grep -Fq 'СКАЙЛЕЙК-ISA-ВІДМОВА' "$TMP/відмова.err"
echo "СКАЙЛЕЙК-D12-ГАРАЗД справжніх-ELF=$PASS ISA-негативів=29 pinned-SENS-REPL=9 AVX=не-виконано ENERGY_NOT_MEASURED"
# $TMP — приватні тимчасові T5M/ELF і .ppu/.o, звільняються trap.
# Питання: чому читаємо лише 15 байтів? Де pinned SENS oracle?
# Як відхилено ELF mutation? Чому статичний профіль не є CPUID?
