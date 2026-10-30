#!/usr/bin/env bash
# G6.89: один сталий ELF64 PIE обирає D3:110 за 4 runtime D1.
# 16 окремих host stdin кадрів; 16 канонічних D2/T5M програм для oracle.
set -euo pipefail
trap 'code=$?; echo "Д1-УМОВА-ВІДМОВА код=$code рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(110 (ук за-умовою) (укр за-умовою)' \
  external/sens/lib/domains/d3.lisp
git -C external/sens show HEAD:contracts/language-contract-12.lisp |
  grep -Fq '(cond-clause . (test expression))'
git -C external/sens show HEAD:contracts/language-contract-12.lisp |
  grep -Fq '(cond-after-exhaustion . D3:000)'
git -C external/sens show HEAD:lib/machine/profile/current-domain-x86-64.lisp |
  grep -Fq '(домен-третій за-умовою control "CMP+Jcc")'
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'Д1-УМОВА-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
FPC_BIN=$(printenv FPC || echo fpc)
for tool in "$FPC_BIN" timeout cmp objdump readelf mktemp grep sha256sum; do
  command -v "$tool" >/dev/null || {
    echo "Д1-УМОВА-БЛОК: немає $tool" >&2; exit 127;
  }
done
if [[ -n "$(printenv SENS_ORACLE_BIN || true)" ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/свідки"
for entry in \
  'scripts/test-d1umovapotik.pas test-d1umovapotik' \
  'src/sensd1umovapotikelf.lpr sensd1umovapotikelf'; do
  read -r path exe <<< "$entry"
  if ! timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$path" >"$TMP/$exe.build.log" 2>&1; then
    cat "$TMP/$exe.build.log" >&2
    exit 1
  fi
  test -x "$TMP/bin/$exe"
done
timeout 15s "$TMP/bin/test-d1umovapotik" "$TMP/свідки" \
  > "$TMP/випадки.tsv" 2> "$TMP/свідки.err"
if ! grep -Fq 'Д1-УМОВА-СВІДКИ-ГАРАЗД четвірок=16 перша=8 друга=4 вичерпано=4' "$TMP/свідки.err"; then
  cat "$TMP/свідки.err" >&2; exit 1
fi
test "$(wc -l < "$TMP/випадки.tsv")" -eq 16
ELF="$TMP/динамічна-умова.elf"
timeout 15s "$TMP/bin/sensd1umovapotikelf" \
  --зібрати-D1-умову "$ELF" >"$TMP/compile.out" 2>"$TMP/compile.err"
test ! -s "$TMP/compile.err"
grep -Fq 'Д1-УМОВА-ПОТІК-ГОТОВО' "$TMP/compile.out"
test -x "$ELF"
readelf -h "$ELF" > "$TMP/elf.header"
grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/elf.header"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.header"
tail -c +121 "$ELF" > "$TMP/machine.bin"
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/machine.bin" > "$TMP/disasm"
grep -Eiq 'cmp[[:space:]]+(rax|al|BYTE PTR)' "$TMP/disasm"
grep -Eiq 'jne[[:space:]]' "$TMP/disasm"
grep -Eiq 'jmp[[:space:]]' "$TMP/disasm"
# 2 машинних syscalls + вихідний 1 байт, invalid paths exit 2.
HASH=$(sha256sum "$ELF" | cut -d' ' -f1)
PASS=0; FIRST=0; SECOND=0; EMPTY=0; ORACLE=0
while IFS=$'\t' read -r name t0 e0 t1 e1 expected source; do
  test -n "$name"
  test -s "$TMP/свідки/$name.frame"
  test -s "$TMP/свідки/$name.sens"
  timeout 5s "$ELF" < "$TMP/свідки/$name.frame" \
    > "$TMP/$name.output.sens" 2> "$TMP/$name.stderr"
  test ! -s "$TMP/$name.stderr"
  cmp "$TMP/свідки/$name.expected.sens" "$TMP/$name.output.sens"
  test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
  if [[ "$source" == 'перша' ]]; then FIRST=$((FIRST+1))
  elif [[ "$source" == 'друга' ]]; then SECOND=$((SECOND+1))
  elif [[ "$source" == 'вичерпано' ]]; then EMPTY=$((EMPTY+1))
  else exit 1; fi
  if [[ -n "$(printenv SENS_ORACLE_BIN || true)" ]]; then
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/свідки/$name.sens" \
      > "$TMP/$name.oracle" 2> "$TMP/$name.oracle.err"
    test ! -s "$TMP/$name.oracle.err"
    cmp "$TMP/свідки/$name.oracle.txt" "$TMP/$name.oracle"
    ORACLE=$((ORACLE+1))
  fi
  PASS=$((PASS+1))
done < "$TMP/випадки.tsv"
test "$PASS" -eq 16 && test "$FIRST" -eq 8 && \
  test "$SECOND" -eq 4 && test "$EMPTY" -eq 4
if [[ -n "$(printenv SENS_ORACLE_BIN || true)" ]]; then
  test "$ORACLE" -eq 16
fi
NEG=0
reject() {
  local input="$1" status=0
  timeout 5s "$ELF" < "$input" > "$TMP/reject.out" \
    2> "$TMP/reject.err" || status=$?
  if [[ "$status" != 2 ]]; then
    echo "Д1-УМОВА-БЛОК: помилковий exit=$status для $input" >&2; exit 1
  fi
  test ! -s "$TMP/reject.out"
  grep -Fq 'Д1-УМОВА-ПОТІК-ВІДМОВА:' "$TMP/reject.err"
  NEG=$((NEG+1))
}
for label in порожній короткий-1 короткий-2 короткий-3 зайвий \
  зіпсований-1 зіпсований-2 зіпсований-3 зіпсований-4 \
  неканонічний; do
  reject "$TMP/свідки/$label.frame"
done
reject "$TMP/свідки/текстова.lisp"
test "$NEG" -eq 11
# Контроль no-clobber і відтворюваних інструкцій.
cp "$ELF" "$TMP/occupied.elf"
status=0
timeout 15s "$TMP/bin/sensd1umovapotikelf" \
  --зібрати-D1-умову "$TMP/occupied.elf" > "$TMP/no-clobber.out" \
  2> "$TMP/no-clobber.err" || status=$?
test "$status" -ne 0
test ! -s "$TMP/no-clobber.out"
cmp "$ELF" "$TMP/occupied.elf"
ln -s "$ELF" "$TMP/occupied-link.elf"
status=0
timeout 15s "$TMP/bin/sensd1umovapotikelf" \
  --зібрати-D1-умову "$TMP/occupied-link.elf" > "$TMP/link.out" \
  2> "$TMP/link.err" || status=$?
test "$status" -ne 0 && test ! -s "$TMP/link.out"
test -L "$TMP/occupied-link.elf"
timeout 15s "$TMP/bin/sensd1umovapotikelf" \
  --зібрати-D1-умову "$TMP/recompiled.elf" >/dev/null
cmp "$ELF" "$TMP/recompiled.elf"
timeout 5s "$TMP/recompiled.elf" < "$TMP/свідки/пара-01.frame" \
  > "$TMP/recompiled.output"
cmp "$TMP/свідки/пара-01.expected.sens" "$TMP/recompiled.output"
echo "Д1-УМОВА-ПОТІК-ГАРАЗД фізичних=$PASS перша=$FIRST друга=$SECOND вичерпано=$EMPTY oracle=$ORACLE негативів=$NEG один-ELF=так D1-або-D3:000=точний RAPL=НЕ-ВИМІРЯНО"
