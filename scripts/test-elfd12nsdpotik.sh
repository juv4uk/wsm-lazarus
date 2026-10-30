#!/usr/bin/env bash
# G6.119 — один native ELF64 зі знаковою семантикою pinned D6:010101.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'Д12-НСД-ПОТІК-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc cmp readelf objdump timeout git sha256sum grep wc python3; do
  command -v "$tool" >/dev/null || { echo "Д12-НСД-ПОТІК-БЛОК: бракує $tool" >&2; exit 127; }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
git -C external/sens show "$PIN:lib/domains/d6.lisp" |
  grep -Fq '(010101 (ук нсд) (укр найбільший-спільний-дільник)'
ORACLE=${SENS_ORACLE_BIN:-}
[[ -n "$ORACLE" && -x "$ORACLE" ]] || { echo 'Д12-НСД-ПОТІК-БЛОК: бракує pinned SENS_ORACLE_BIN' >&2; exit 127; }
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
TMP=$(mktemp -d)
cleanup() {
  local rc=$?
  if (( rc != 0 )); then
    echo "Д12-НСД-ПОТІК-ПОМИЛКА: код=$rc" >&2
    for file in "$TMP"/*.build.log "$TMP"/*.err; do
      [[ ! -s "$file" ]] || { echo "--- $file" >&2; tail -n 25 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/u-kernel" "$TMP/u-fixture" "$TMP/u-number" "$TMP/frames"
for triple in \
  'src/sensd12nsdpotikelf.lpr sensd12nsdpotikelf u-kernel' \
  'scripts/test-elfd12nsdpotik.pas test-elfd12nsdpotik u-fixture' \
  'src/senschyslo.lpr senschyslo u-number'; do
  read -r source target units <<<"$triple"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" "-o$target" \
    "$ROOT/$source" >"$TMP/$target.build.log" 2>&1 ||
    { cat "$TMP/$target.build.log" >&2; exit 1; }
  test -x "$TMP/bin/$target"
done
timeout 30s "$TMP/bin/test-elfd12nsdpotik" "$TMP/frames" \
  >"$TMP/valid.tsv" 2>"$TMP/fixtures.err"
grep -Fq 'D12-NSD-STDIN-FIXTURES-OK positives=29 rejects=22' "$TMP/fixtures.err"
test "$(wc -l < "$TMP/valid.tsv")" -eq 29
ELF="$TMP/один-нсд.elf"
timeout 20s "$TMP/bin/sensd12nsdpotikelf" --зібрати-D12-нсд-потік "$ELF" \
   >"$TMP/compile.out" 2>"$TMP/compile.err"
test ! -s "$TMP/compile.err"
grep -Fq 'machine=EUCLID_DIV D12=T5M-stdin2' "$TMP/compile.out"
test -x "$ELF"
readelf -h "$ELF" >"$TMP/readelf.log"
grep -Eq 'Type:.*DYN' "$TMP/readelf.log"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/readelf.log"
# Main machine gates — verify actual emitted bytes, not just the status banner.
python3 - "$ELF" <<'PY'
from pathlib import Path
import sys
image=Path(sys.argv[1]).read_bytes()
assert image[:4]==b'\x7fELF'
code=image[120:620]
for name,seq in {
    "exact six byte stdin":bytes.fromhex("ba070000000f054883f8060f85"),
    "blocked unproven D12 minimum":bytes.fromhex("4181f800f8ffff0f84"),
    "blocked unproven right minimum":bytes.fromhex("4181f900f8ffff0f84"),
    "SENS sign select":bytes.fromhex("4589ca4585d2450f44d041c1fa1f"),
    "signed absolute first":bytes.fromhex("4489c09931d029d0"),
    "signed absolute second":bytes.fromhex("4489c989cac1fa1f31d129d1"),
    "machine euclid":bytes.fromhex("85c90f84"),
    "real DIV":bytes.fromhex("31d2f7f189c889d1e9"),
    "signed result":bytes.fromhex("4431d04429d0"),
    "D12 signed upper guard":bytes.fromhex("3dff0700000f8f"),
    "D12 signed lower guard":bytes.fromhex("3d00f8ffff0f8c"),
    "T5M decode":bytes.fromhex("0fb60406"),
    "T5M encode":bytes.fromhex("8a0406"),
}.items():
    assert seq in code,name
print("Д12-НСД-МАШИНА-ГОТОВО: CMOVZ/CDQ/SAR/XOR/SUB/TEST/JZ/DIV/JMP/JG/JL + T5M")
PY
# Check valid instruction mnemonics using a disassembled code window.
dd if="$ELF" of="$TMP/code.bin" bs=1 skip=120 count=410 status=none
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code.bin" >"$TMP/disasm.log"
grep -Eiq 'cmove[[:space:]]+r10d,r8d' "$TMP/disasm.log"
grep -Eiq 'cdq' "$TMP/disasm.log"
grep -Eiq 'sar[[:space:]]+edx,0x1f' "$TMP/disasm.log"
grep -Eiq 'div[[:space:]]+ecx' "$TMP/disasm.log"
grep -Eiq 'jg[[:space:]]' "$TMP/disasm.log"
grep -Eiq 'jl[[:space:]]' "$TMP/disasm.log"
grep -Eiq 'test[[:space:]]+ecx,ecx' "$TMP/disasm.log"
grep -Eiq 'jmp[[:space:]]' "$TMP/disasm.log"
HASH=$(sha256sum "$ELF" | cut -d' ' -f1)
PASS=0
ORACLE_COUNT=0
while IFS=$'\t' read -r label left right expected; do
  test -n "$label"
  for repeat in 1 2; do
    timeout 6s "$ELF" <"$TMP/frames/$label.frame" \
      >"$TMP/$label.$repeat.actual.sens" 2>"$TMP/$label.$repeat.err"
    test ! -s "$TMP/$label.$repeat.err"
    cmp "$TMP/frames/$label-expected.sens" "$TMP/$label.$repeat.actual.sens"
    test "$(wc -c < "$TMP/$label.$repeat.actual.sens")" -eq 3
    test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
    PASS=$((PASS+1))
  done
  cmp "$TMP/$label.1.actual.sens" "$TMP/$label.2.actual.sens"
  "$TMP/bin/senschyslo" --в-укр D12 "$TMP/$label.1.actual.sens" \
    >"$TMP/$label.projected"
  printf '%s\n' "$expected" >"$TMP/$label.expected.ukr"
  cmp "$TMP/$label.expected.ukr" "$TMP/$label.projected"
  printf '(найбільший-спільний-дільник %s %s)\n' "$left" "$right" >"$TMP/$label.lisp"
  # Після fail-closed -2048 обидва десяткові operands потрапляють в D12.
  # Текстова проєкція лише людська; pinned SENS REPL є незалежним oracle.
  timeout 60s "$ORACLE" "$TMP/$label.lisp" \
    >"$TMP/$label.oracle.lisp" 2>"$TMP/$label.oracle.err"
  test ! -s "$TMP/$label.oracle.err"
  if ! cmp "$TMP/$label.oracle.lisp" "$TMP/$label.projected"; then
    echo "D6-НСД-ORACLE-РОЗБІЖНІСТЬ: label=$label left=$left right=$right" >&2
    echo "машина:" >&2
    cat "$TMP/$label.projected" >&2
    echo "pinned SENS:" >&2
    cat "$TMP/$label.oracle.lisp" >&2
    exit 1
  fi
  "$TMP/bin/senschyslo" --з-укр D12 "$TMP/$label.oracle.lisp" \
    "$TMP/$label.oracle.sens" >"$TMP/$label.encode.out"
  test ! -s "$TMP/$label.encode.out"
  cmp "$TMP/$label.oracle.sens" "$TMP/$label.1.actual.sens"
  ORACLE_COUNT=$((ORACLE_COUNT+1))
done <"$TMP/valid.tsv"
test "$PASS" -eq 58 && test "$ORACLE_COUNT" -eq 29
NEG=0
reject() {
  local name="$1" rc=0
  timeout 6s "$ELF" <"$TMP/frames/$name.frame" \
    >"$TMP/reject-$name.out" 2>"$TMP/reject-$name.err" || rc=$?
  test "$rc" -eq 2 || { echo "Д12-НСД-НЕВІРНА-ВІДМОВА: $name код=$rc" >&2; exit 1; }
  test ! -s "$TMP/reject-$name.out"
  grep -Fq 'Д12-НСД-ПОТІК-ВІДМОВА:' "$TMP/reject-$name.err"
  NEG=$((NEG+1))
}
for name in 25 26 27 28 29 32 36 37 38 39 \
  empty short1 short5 extra invalid243 \
  badfirst badsecond badthird badlast newline projection d1; do
  reject "$name"
done
test "$NEG" -eq 22
cp "$ELF" "$TMP/зайнятий.elf"
rc=0
timeout 10s "$TMP/bin/sensd12nsdpotikelf" --зібрати-D12-нсд-потік \
  "$TMP/зайнятий.elf" >"$TMP/no-clobber.out" 2>"$TMP/no-clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/no-clobber.out"
cmp "$ELF" "$TMP/зайнятий.elf"
ln -s "$TMP/nonexistent.elf" "$TMP/dangling.elf"
rc=0
timeout 10s "$TMP/bin/sensd12nsdpotikelf" --зібрати-D12-нсд-потік \
  "$TMP/dangling.elf" >"$TMP/symlink.out" 2>"$TMP/symlink.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" && test ! -e "$TMP/nonexistent.elf"
timeout 10s "$TMP/bin/sensd12nsdpotikelf" --зібрати-D12-нсд-потік \
  "$TMP/recovered.elf" >/dev/null
cmp "$ELF" "$TMP/recovered.elf"
timeout 6s "$TMP/recovered.elf" <"$TMP/frames/01.frame" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/frames/01-expected.sens"
echo "Д12-НСД-ПОТІК-ГОТОВО ELF=1 виконань=$PASS oracle=$ORACLE_COUNT негативів=$NEG no-clobber=так dynamic-D12=так T5M=точно RAPL=НЕ-ВИМІРЯНО"
