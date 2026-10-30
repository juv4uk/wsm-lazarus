#!/usr/bin/env bash
# G6.192 — reuse pinned verified WideIR для D5:11011 signed greater.
# FPC перевіряє повний admission; shell виконує саме машинний ELF64.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for exe in fpc git timeout mktemp grep cmp readelf objdump chmod python3;do
  command -v "$exe" >/dev/null || {
    echo "VG-BLOCK missing $exe" >&2;exit 127;
  }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(11011 (ук більше?) (укр більше?)' external/sens/lib/domains/d5.lisp
TMP=$(mktemp -d)
finish(){
  rc=$?
  if ((rc));then
    echo "VG-FAIL test-exit=$rc" >&2
    for file in "$TMP"/*.log "$TMP"/*.err;do
      [[ ! -s "$file" ]] || { echo "--- $file" >&2;tail -n 24 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
timeout 240s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-verified-greater "$ROOT/scripts/test-verified-greater.pas" \
  >"$TMP/fpc.log" 2>"$TMP/fpc.err" || {
    cat "$TMP/fpc.log" "$TMP/fpc.err" >&2;exit 1;
  }
test -x "$TMP/bin/test-verified-greater"
timeout 720s "$TMP/bin/test-verified-greater" "$TMP/physical" \
  >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Fxq 'VG-PASS physical=16 negatives=9 recovery=1 old-new-elf=identical' "$TMP/generator.log"
if grep -Fq 'unfreed memory blocks' "$TMP/generator.err";then
  grep -Fq '0 unfreed memory blocks' "$TMP/generator.err"
else
  test ! -s "$TMP/generator.err"
fi
test "$(wc -l <"$TMP/physical/cases.tsv")" -eq 16
RESULTS=0
ORACLE=0
SENS_ORACLE_BIN=${SENS_ORACLE_BIN:-}
if [[ "${REQUIRE_SENS_ORACLE:-0}" == "1" ]];then
  test -n "$SENS_ORACLE_BIN"
fi
if [[ -n "$SENS_ORACLE_BIN" ]];then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
while IFS=$'\t' read -r label left right expected;do
  test -n "$label"
  test -s "$TMP/physical/$label.sens"
  elf="$TMP/physical/$label.elf"
  test -s "$elf"
  readelf -h "$elf" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  objdump -D "$elf" >"$TMP/$label.asm"
  grep -Eiq 'setg[[:space:]]+%al|setg[[:space:]]+al' "$TMP/$label.asm"
  chmod u+x "$elf"
  timeout 5s "$elf" >"$TMP/$label.actual.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.actual.sens"
  if [[ -n "$SENS_ORACLE_BIN" ]];then
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/physical/$label.lisp" \
      >"$TMP/$label.oracle.log" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.want"
    cmp "$TMP/$label.want" "$TMP/$label.oracle.log"
    ORACLE=$((ORACLE+1))
  fi
  RESULTS=$((RESULTS+1))
done <"$TMP/physical/cases.tsv"
test "$RESULTS" -eq 16
if [[ -n "$SENS_ORACLE_BIN" ]];then test "$ORACLE" -eq 16;fi
echo "VG-NATIVE-PASS fpc=checked pinned=12.0 physical=16 machine=16 same-elf=16 negatives=9 recovered=1 oracle=$ORACLE energy=NOT_MEASURED speedup=NOT_MEASURED"
# 1) Чому pinned D5:11011 є перевіркою identity, а не host dispatch?
# 2) Чому байти x86 ELF мають бути однаковими старого й нового шляхів?
# 3) Хто формує фактичний D1 output під час виконання ELF?
# 4) Чому зовнішній SENS REPL є незалежним oracle?
# 5) Чому цей тест не доводить швидкість, поки немає raw times?
