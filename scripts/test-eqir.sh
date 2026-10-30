#!/usr/bin/env bash
# G6.53 — справжній IR-lowering D3:101 → машинний ELF64 → pinned SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in git timeout cmp readelf; do
  command -v "$tool" >/dev/null || {
    echo "ЗНИЖЕННЯ-Д3-БЛОК: немає $tool" >&2; exit 127;
  }
done
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'ЗНИЖЕННЯ-Д3-БЛОК: немає Free Pascal' >&2; exit 127;
}
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ЗНИЖЕННЯ-Д3-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show HEAD:contracts/language-contract-12.lisp |
  grep -Fq '(eq-operands . admitted-atoms-only)'
git -C external/sens show HEAD:contracts/language-contract-12.lisp |
  grep -Fq '(eq-result . (D1:0 D1:1))'
grep -Fq '(101 (ук тотожне?)' external/sens/lib/domains/d3.lisp

OUT="$ROOT/build/m0.2/eqir"
mkdir -p "$OUT/bin" "$OUT/units"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$OUT/units" -FE"$OUT/bin" \
  -otest-eqir "$ROOT/scripts/test-eqir.pas"
timeout 90s "$OUT/bin/test-eqir"

ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || {
  echo 'ЗНИЖЕННЯ-Д3-БЛОК: відсутній незалежний pinned SENS REPL' >&2; exit 127;
}
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
COUNT=0
for name in d1-00 d1-01 d1-10 d1-11; do
  INPUT="$OUT/$name.sens"
  MACHINE="$OUT/$name.elf"
  EXPECT="$OUT/$name.expected"
  test -s "$INPUT" && test -s "$MACHINE" && test -s "$EXPECT"
  chmod 500 "$MACHINE"
  readelf -h "$MACHINE" | grep -F 'ELF64' >/dev/null
  readelf -h "$MACHINE" | grep -F 'Advanced Micro Devices X86-64' >/dev/null
  readelf -l "$MACHINE" | grep -F 'LOAD' >/dev/null
  timeout 5s "$MACHINE" >"$OUT/$name.machine" 2>"$OUT/$name.machine.err"
  test ! -s "$OUT/$name.machine.err"
  cmp "$EXPECT" "$OUT/$name.machine"
  timeout 60s "$ORACLE" "$INPUT" >"$OUT/$name.oracle" \
    2>"$OUT/$name.oracle.err" || {
      echo "ЗНИЖЕННЯ-Д3-ОРАКУЛ-ВІДМОВА: $name" >&2
      cat "$OUT/$name.oracle.err" >&2
      exit 1
    }
  test ! -s "$OUT/$name.oracle.err"
  cmp "$EXPECT" "$OUT/$name.oracle"
  cmp "$OUT/$name.machine" "$OUT/$name.oracle"
  COUNT=$((COUNT+1))
done
test "$COUNT" -eq 4
# Не відключати старий перевірений EQ-emitter: повна регресія обов'язкова.
timeout 240s bash ./scripts/test-elfeq.sh
echo "ЗНИЖЕННЯ-Д3-МЕХАНІЗМ-ГАРАЗД FPC=checked ELF64=4 D1xD1=$COUNT негативи=16 незалежний-SENS=$PIN"
