#!/usr/bin/env bash
# G6.241 — фізичний D12 SUB→ZERO?→D1: справжній x86-64 ELF64.
# Це профільний механічний доказ; незалежний SENS REPL лише за наявності oracle.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'SUBZERO-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for t in fpc timeout git readelf objdump grep cmp mktemp chmod tail; do
  command -v "$t" >/dev/null || { echo "SUBZERO-БЛОК: немає $t" >&2; exit 127; }
done
[[ -c /dev/full ]] || { echo 'SUBZERO-БЛОК: /dev/full відсутній' >&2; exit 127; }
timeout 120s bash scripts/check-pin.sh
grep -Fq '(01011 (ук відняти)' external/sens/lib/domains/d5.lisp
grep -Fq '(01000 (ук нуль?)' external/sens/lib/domains/d5.lisp
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
if ! timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh   -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin"   -otest-verified-subzero "$ROOT/scripts/test-verified-subzero.pas"   >"$TMP/fpc.log" 2>&1; then
  tail -n 70 "$TMP/fpc.log" >&2; exit 1
fi
test -x "$TMP/bin/test-verified-subzero"
timeout 30s "$TMP/bin/test-verified-subzero" "$TMP/physical"   >"$TMP/cases.tsv" 2>"$TMP/witness.err" || {
  tail -n 40 "$TMP/witness.err" >&2; exit 1;
}
grep -Fq 'SUBZERO-FPC-PASS positive=16 negative=8' "$TMP/witness.err"
PASS=0; CLOSED=0; FULL=0; RECOVERY=0; ORACLE=0
while IFS=$'\t' read -r label a b truth; do
  test -n "$label"
  test -s "$TMP/physical/$label.elf"
  test -s "$TMP/physical/$label.want.sens"
  chmod 700 "$TMP/physical/$label.elf"
  timeout 5s readelf -h "$TMP/physical/$label.elf" >"$TMP/header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header"
  tail -c +121 "$TMP/physical/$label.elf" >"$TMP/code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" >"$TMP/dis"
  grep -Eiq 'sub[[:space:]]+eax,' "$TMP/dis"
  grep -Eiq 'test[[:space:]]+eax,' "$TMP/dis"
  grep -Eiq 'sete[[:space:]]+al' "$TMP/dis"
  grep -Eiq 'movzx[[:space:]]+eax,' "$TMP/dis"
  timeout 5s "$TMP/physical/$label.elf" >"$TMP/output.sens" 2>"$TMP/error"
  test ! -s "$TMP/error"
  cmp "$TMP/physical/$label.want.sens" "$TMP/output.sens"
  PASS=$((PASS+1))
  rc=0
  timeout 5s "$TMP/physical/$label.elf" 1>&- 2>"$TMP/error" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/error"
  CLOSED=$((CLOSED+1))
  rc=0
  timeout 5s "$TMP/physical/$label.elf" >/dev/full 2>"$TMP/error" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/error"
  FULL=$((FULL+1))
  timeout 5s "$TMP/physical/$label.elf" >"$TMP/recovery.sens"
  cmp "$TMP/physical/$label.want.sens" "$TMP/recovery.sens"
  RECOVERY=$((RECOVERY+1))
  if [[ -n "$(printenv SENS_ORACLE_BIN || true)" ]]; then
    test -x "$SENS_ORACLE_BIN"
    test "$(git -C sens-oracle rev-parse HEAD)" = "$(git -C external/sens rev-parse HEAD)"
    printf '(нуль? (відняти %s %s))\n' "$a" "$b" >"$TMP/oracle.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/oracle.lisp" >"$TMP/oracle" 2>"$TMP/oracle.err"
    test ! -s "$TMP/oracle.err"
    if [[ "$truth" == 1 ]]; then wanted=ТАК; else wanted=НІ; fi
    awk '{ sub(/^sens\\[укр\\]> /, ""); if ($0=="1" || $0=="(т а к)") print "ТАК"; else if ($0=="0" || $0=="(н і)") print "НІ"; else print }' "$TMP/oracle" >"$TMP/normalized"
    printf '%s\n' "$wanted" >"$TMP/wanted"
    cmp "$TMP/wanted" "$TMP/normalized"
    ORACLE=$((ORACLE+1))
  fi
done <"$TMP/cases.tsv"
test "$PASS" -eq 16 && test "$CLOSED" -eq 16 && test "$FULL" -eq 16
test "$RECOVERY" -eq 16
if [[ -n "$(printenv SENS_ORACLE_BIN || true)" ]]; then test "$ORACLE" -eq 16; fi
echo "VERIFIED-SUBZERO-PASS elf=$PASS closed=$CLOSED full=$FULL recovery=$RECOVERY negative=8 oracle=$ORACLE energy=NOT-MEASURED"
