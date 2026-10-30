#!/usr/bin/env bash
# G6.55 — пряме ExactIR зниження, ELF64 parity і pinned SENS oracle.
set -euo pipefail
export LANG=C.UTF-8
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
FPC_BIN=${FPC:-fpc}
ORACLE=${SENS_ORACLE:-$ROOT/sens-oracle/target/debug/sens}
for tool in "$FPC_BIN" git timeout cmp readelf objdump; do
  command -v "$tool" >/dev/null || { echo "ПРЯМИЙ-IR-ELF-БЛОК: бракує $tool" >&2; exit 127; }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ПРЯМИЙ-IR-ELF-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
test -x "$ORACLE" || { echo 'ПРЯМИЙ-IR-ELF-БЛОК: немає pinned SENS CLI' >&2; exit 127; }
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN" || {
  echo 'ПРЯМИЙ-IR-ELF-БЛОК: upstream SENS має інший SHA' >&2; exit 1;
}
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp

# Чинна перевірка створює свідки та проходить старий selector/ExactIR шлях.
timeout 360s bash ./scripts/test-exactir-selector.sh
BASE="$ROOT/build/m0.2/selectort5m"
OUT="$ROOT/build/m0.2/ir-lowered-selector"
mkdir -p "$OUT/units" "$OUT/bin" "$OUT/verified"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$OUT/units" -FE"$OUT/bin" -otest-ir-lowered-selector \
  "$ROOT/scripts/test-ir-lowered-selector.pas"
timeout 100s "$OUT/bin/test-ir-lowered-selector" \
  "$ROOT/external/sens" "$BASE" "$OUT/verified" \
  >"$OUT/test.log" 2>"$OUT/test.err"
cat "$OUT/test.log"
test ! -s "$OUT/test.err" || { cat "$OUT/test.err" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
count=0
for name in перше-00 перше-01 перше-10 перше-11 \
            решта-00 решта-01 решта-10 решта-11; do
  elf="$OUT/verified/$name.elf"
  source="$BASE/$name.sens"
  test -s "$elf" && test -s "$source"
  cmp "$elf" "$BASE/$name.elf"
  chmod u+x "$elf"
  readelf -h "$elf" >"$TMP/head"
  readelf -l "$elf" >"$TMP/segments"
  grep -F ELF64 "$TMP/head" >/dev/null
  grep -E 'Type:.*DYN' "$TMP/head" >/dev/null
  grep -F 'Advanced Micro Devices X86-64' "$TMP/head" >/dev/null
  grep -F LOAD "$TMP/segments" >/dev/null
  ! grep -E 'INTERP|DYNAMIC' "$TMP/segments" >/dev/null
  tail -c +121 "$elf" >"$TMP/code"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" >"$TMP/asm"
  grep -F 'QWORD PTR [rsp],rax' "$TMP/asm" >/dev/null
  grep -F 'QWORD PTR [rsp+0x8],rcx' "$TMP/asm" >/dev/null
  grep -F 'imul' "$TMP/asm" >/dev/null
  timeout 5s "$elf" >"$TMP/answer.sens"
  cmp "$TMP/answer.sens" "$BASE/$name.expected.sens"
  cmp "$TMP/answer.sens" "$BASE/$name.native.sens"
  timeout 60s "$ORACLE" "$source" >"$TMP/$name.oracle" \
    2>"$TMP/$name.oracle.err"
  test ! -s "$TMP/$name.oracle.err"
  cmp "$TMP/$name.oracle" "$OUT/verified/$name.expected.oracle"
  test "$(wc -c <"$TMP/answer.sens")" -eq 1
  count=$((count+1))
done
test "$count" -eq 8

echo "ПРЯМЕ-ЗНИЖЕННЯ-СЕЛЕКТОРА-ГАРАЗД pinned=$PIN ELF64=$count byte-parity=так upstream-SENS=так"
