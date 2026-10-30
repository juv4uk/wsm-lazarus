#!/usr/bin/env bash
# G6.257 — canonical фізичний D5:01010(D24,D24) через pinned WideIR до ELF64.
# Повторно використовує наявні SENS numeric + ELF; жодного Rust build на push.
# Якщо SENS_ORACLE_BIN задано — додатково вимагаємо pinned незалежний REPL.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'IR-D24-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for bin in timeout fpc git cmp readelf objdump mktemp grep chmod; do
  command -v "$bin" >/dev/null || {
    echo "IR-D24-БЛОК: немає $bin" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(01010 (ук додати) (укр додати)' external/sens/lib/domains/d5.lisp
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc)); then for f in "$TMP"/*.log "$TMP"/*.err; do
  [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 45 "$f" >&2; }
done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical" "$TMP/repeat"
FPC_BIN=${FPC:-fpc}
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-irwided24carry "$ROOT/scripts/test-irwided24carry.pas" \
  >"$TMP/build.log" 2>&1 || { cat "$TMP/build.log" >&2; exit 1; }
HEAPTRC="log=$TMP/heap.log" timeout 70s "$TMP/bin/test-irwided24carry" \
  "$ROOT/external/sens" "$TMP/physical" >"$TMP/fixture.log" \
  2>"$TMP/fixture.err" || { cat "$TMP/fixture.log" "$TMP/fixture.err" >&2; exit 1; }
grep -Fxq 'IR-D24-CARRY-OK positives=10 negative=12 recovery=1 source=T5M-D5-W24 IR=PINNED-WIDE ELF64=10 energy=NOT-MEASURED' "$TMP/fixture.log"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
test ! -s "$TMP/fixture.err"
test "$(wc -l < "$TMP/physical/cases.tsv")" -eq 10
PASS=0
ORACLE=0
while IFS=$'\t' read -r label left right expected; do
  [[ "$label" =~ ^[0-9][0-9]$ ]] || exit 1
  test -n "$left" && test -n "$right" && test -n "$expected"
  exe="$TMP/physical/$label.elf"
  source="$TMP/physical/$label.program.sens"
  physical="$TMP/physical/$label.expected.sens"
  test -s "$exe" && test -s "$source" && test -s "$physical"
  test "$(wc -c < "$physical")" -eq 5
  chmod 700 "$exe"
  timeout 5s readelf -h "$exe" >"$TMP/header.log"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 5s readelf -l "$exe" >"$TMP/segments.log"
  grep -Fq 'LOAD' "$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  timeout 5s "$exe" >"$TMP/$label.actual.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/$label.actual.sens" "$physical"
  if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
    test -x "$SENS_ORACLE_BIN"
    test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
    printf '(додати %s %s)\n' "$left" "$right" >"$TMP/$label.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.expected.txt"
    cmp "$TMP/$label.oracle.out" "$TMP/$label.expected.txt"
    ORACLE=$((ORACLE+1))
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 10
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
  test "$ORACLE" -eq 10
  ORACLE_STATE=PINNED-10
else
  ORACLE_STATE=NOT-RUN
fi
# Перевірити саме машинний ADD→ADC, а не тільки фізичний stdout.
tail -c +121 "$TMP/physical/01.elf" >"$TMP/machine.bin"
timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
  "$TMP/machine.bin" >"$TMP/disasm.log"
grep -Eq 'add[[:space:]]+eax,ecx' "$TMP/disasm.log"
grep -Eq 'adc[[:space:]]+edx,ebx' "$TMP/disasm.log"
# Перевірити відтворюваність повторного запуску того самого FPC fixture.
HEAPTRC="log=$TMP/repeat.heap" timeout 70s "$TMP/bin/test-irwided24carry" \
  "$ROOT/external/sens" "$TMP/repeat" >"$TMP/repeat.log" \
  2>"$TMP/repeat.err"
grep -Fq 'IR-D24-CARRY-OK positives=10 negative=12 recovery=1' "$TMP/repeat.log"
test -s "$TMP/repeat.heap"
grep -Fq '0 unfreed memory blocks' "$TMP/repeat.heap"
test ! -s "$TMP/repeat.err"
for label in 01 02 03 04 05 06 07 08 09 10; do
  cmp "$TMP/physical/$label.elf" "$TMP/repeat/$label.elf"
  cmp "$TMP/physical/$label.program.sens" "$TMP/repeat/$label.program.sens"
done
# Linux write не може мовчки завершитися нульовим статусом.
NEGWRITE=0
RECOVERY=0
for label in 01 04; do
  exe="$TMP/physical/$label.elf"
  expected="$TMP/physical/$label.expected.sens"
  rc=0
  ( exec 1>&-; timeout 5s "$exe" ) 2>"$TMP/closed.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/closed.err"
  NEGWRITE=$((NEGWRITE+1))
  rc=0
  timeout 5s "$exe" >/dev/full 2>"$TMP/full.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/full.err"
  NEGWRITE=$((NEGWRITE+1))
  timeout 5s "$exe" >"$TMP/recovered.sens" 2>"$TMP/recovered.err"
  test ! -s "$TMP/recovered.err"
  cmp "$TMP/recovered.sens" "$expected"
  RECOVERY=$((RECOVERY+1))
done
test "$NEGWRITE" -eq 4 && test "$RECOVERY" -eq 2
echo "VERIFIED-IR-D24-CARRY-PASS FPC=checked source=10 ELF64=$PASS T5M=byte-exact negative=12 write-negative=$NEGWRITE reproducible=10 oracle=$ORACLE_STATE energy=NOT-MEASURED"
