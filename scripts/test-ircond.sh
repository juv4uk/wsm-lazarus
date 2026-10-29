#!/usr/bin/env bash
# G6.57 — pinned ExactIR → дійсний x86-64 PIE із машинним JNE.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in git timeout cmp readelf; do
  command -v "$tool" >/dev/null || {
    echo "ТОЧНА-УМОВА-БЛОК: бракує $tool" >&2; exit 127;
  }
done
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'ТОЧНА-УМОВА-БЛОК: потрібен справжній FPC' >&2; exit 127;
}
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'ТОЧНА-УМОВА-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show HEAD:contracts/language-contract-12.lisp |
  grep -Fq '(cond-clause . (test expression))'
git -C external/sens show HEAD:contracts/language-contract-12.lisp |
  grep -Fq '(cond-after-exhaustion . D3:000)'
grep -Fq '(110 (ук за-умовою)' external/sens/lib/domains/d3.lisp

OUT="$ROOT/build/m0.2/ircond"
mkdir -p "$OUT/bin" "$OUT/units"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$OUT/units" -FE"$OUT/bin" \
  -otest-ircond "$ROOT/scripts/test-ircond.pas"
timeout 90s "$OUT/bin/test-ircond"
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || {
  echo 'ТОЧНА-УМОВА-БЛОК: незалежний pinned SENS REPL не зібрано' >&2; exit 127;
}
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
COUNT=0
for name in порожня одна-хибна одна-істинна-0 одна-істинна-1 \
            друга-істинна-0 друга-істинна-1 перша-істинна обидві-хибні \
            три-перша-істинна три-друга-істинна \
            три-третя-істинна три-всі-хибні; do
  SOURCE="$OUT/$name.sens"
  EXE="$OUT/$name.elf"
  EXPECT="$OUT/$name.expected.sens"
  test -s "$SOURCE" && test -s "$EXE" && test -s "$EXPECT"
  chmod 500 "$EXE"
  readelf -h "$EXE" | grep -Fq 'ELF64'
  readelf -h "$EXE" | grep -Fq 'Advanced Micro Devices X86-64'
  readelf -h "$EXE" | grep -Eq 'Type:.*DYN'
  readelf -l "$EXE" | grep -Fq 'LOAD'
  if readelf -l "$EXE" | grep -Eq 'INTERP|DYNAMIC'; then
    echo "ТОЧНА-УМОВА-БЛОК: стороння залежність у PIE $name" >&2; exit 1
  fi
  timeout 5s "$EXE" > "$OUT/$name.machine.sens" 2>"$OUT/$name.machine.err"
  test ! -s "$OUT/$name.machine.err"
  cmp "$EXPECT" "$OUT/$name.machine.sens"
  timeout 60s "$ORACLE" "$SOURCE" >"$OUT/$name.oracle.actual" \
    2>"$OUT/$name.oracle.err" || {
      echo "ТОЧНА-УМОВА-ОРАКУЛ-ВІДМОВА: $name" >&2
      cat "$OUT/$name.oracle.err" >&2
      exit 1
    }
  test ! -s "$OUT/$name.oracle.err"
  # Людський oracle-текст не визначає фізичні machine-result байти.
  cmp "$OUT/$name.oracle.txt" "$OUT/$name.oracle.actual"
  COUNT=$((COUNT+1))
done
test "$COUNT" -eq 12
# Не вимикати стару FPC/ELF D3:110 regression.
timeout 240s bash ./scripts/test-exactir-cond.sh
echo "ТОЧНА-УМОВА-IR-ГАРАЗД фізичний-T5M=12 незалежний-SENS=12 checked-FPC=так негативи=18"
