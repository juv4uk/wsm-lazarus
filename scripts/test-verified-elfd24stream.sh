#!/usr/bin/env bash
# G6.265 — pinned physical D5 anchor → ОДИН native ELF64 з динамічними D24.
# Чинний FPC verified-all, без додаткових workflow, rustc чи apt.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'D24-ПОТІК-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for cmd in timeout fpc cmp git mktemp grep readelf objdump chmod wc stat; do
  command -v "$cmd" >/dev/null || {
    echo "D24-ПОТІК-БЛОК: немає $cmd" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(01010 (ук додати) (укр додати)' external/sens/lib/domains/d5.lisp
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc));then for f in "$TMP"/*.log "$TMP"/*.err;do
  [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 55 "$f" >&2; }
done;fi;rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/fixtures"
timeout 180s "${FPC:-fpc}" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
 -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
 -otest-elfd24stream "$ROOT/scripts/test-elfd24stream.pas" \
 >"$TMP/build.log" 2>&1 || { cat "$TMP/build.log" >&2;exit 1; }
test -x "$TMP/bin/test-elfd24stream"
HEAPTRC="log=$TMP/heap.log" timeout 90s \
 "$TMP/bin/test-elfd24stream" "$ROOT/external/sens" "$TMP/fixtures" \
 >"$TMP/fixture.log" 2>"$TMP/fixture.err" || {
 cat "$TMP/fixture.log" "$TMP/fixture.err" >&2;exit 1;
}
grep -Fxq 'D24-STREAM-ФІКСТУРИ-ГОТОВО source=1 ELF64=1 inputs=12 overflow=4 invalid=6 bad-anchors=6 reproducible=1 oracle=LOCAL-PINNED energy=NOT-MEASURED' "$TMP/fixture.log"
test ! -s "$TMP/fixture.err"
test -s "$TMP/heap.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
test "$(wc -l < "$TMP/fixtures/cases.tsv")" -eq 12
ELF="$TMP/fixtures/dynamic.elf"
test -s "$ELF"
chmod 700 "$ELF"
timeout 5s readelf -h "$ELF" >"$TMP/header.log"
grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header.log"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
timeout 5s readelf -l "$ELF" >"$TMP/segments.log"
grep -Fq 'LOAD' "$TMP/segments.log"
! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
test "$(stat -c %a "$ELF")" -eq 700
# DONOR реально залишився ADD→ADC, немає constant fold runtime sum.
tail -c +121 "$ELF" >"$TMP/code.bin"
timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
 "$TMP/code.bin" >"$TMP/disasm.log"
grep -Eq 'add[[:space:]]+eax,ecx' "$TMP/disasm.log"
grep -Eq 'adc[[:space:]]+edx,ebx' "$TMP/disasm.log"
PASS=0
while IFS=$'\t' read -r label left right answer;do
  [[ "$label" =~ ^ok-[0-9][0-9]$ ]] || exit 1
  test -n "$left" && test -n "$right" && test -n "$answer"
  INPUT="$TMP/fixtures/$label.input.sens"
  EXPECT="$TMP/fixtures/$label.expected.sens"
  test "$(wc -c < "$INPUT")" -eq 10
  test "$(wc -c < "$EXPECT")" -eq 5
  timeout 5s "$ELF" <"$INPUT" >"$TMP/$label.result.sens" \
    2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$EXPECT" "$TMP/$label.result.sens"
  PASS=$((PASS+1))
done <"$TMP/fixtures/cases.tsv"
test "$PASS" -eq 12
NEG=0
reject_runtime() {
  local label="$1" source="$2" rc=0
  timeout 5s "$ELF" <"$TMP/fixtures/$source.input.sens" \
    >"$TMP/$label.result.sens" 2>"$TMP/$label.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/$label.result.sens"
  test ! -s "$TMP/$label.err"
  NEG=$((NEG+1))
}
for i in 01 02 03 04;do
  reject_runtime "overflow-$i" "overflow-$i"
done
INVALID=0
for label in invalid-empty invalid-short invalid-long invalid-prefix \
 invalid-suffix invalid-second; do
  rc=0
  timeout 5s "$ELF" <"$TMP/fixtures/$label.sens" \
    >"$TMP/$label.actual.sens" 2>"$TMP/$label.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/$label.actual.sens"
  test ! -s "$TMP/$label.err"
  INVALID=$((INVALID+1))
done
test "$NEG" -eq 4 && test "$INVALID" -eq 6
# Broken stdout must fail closed even for a valid input.
CLOSED=0
for label in ok-01 ok-05; do
  rc=0
  ( exec 1>&-; timeout 5s "$ELF" <"$TMP/fixtures/$label.input.sens" ) \
    2>"$TMP/closed.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/closed.err"
  CLOSED=$((CLOSED+1))
done
FULL=0
for label in ok-01 ok-05;do
  rc=0
  timeout 5s "$ELF" <"$TMP/fixtures/$label.input.sens" \
    >/dev/full 2>"$TMP/full.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/full.err"
  FULL=$((FULL+1))
done
# Після всіх відмов той самий ELF повторно працює без нового compile.
timeout 5s "$ELF" <"$TMP/fixtures/ok-02.input.sens" \
 >"$TMP/recovered.sens" 2>"$TMP/recovered.err"
test ! -s "$TMP/recovered.err"
cmp "$TMP/recovered.sens" "$TMP/fixtures/ok-02.expected.sens"
echo "VERIFIED-D24-STREAM-PASS FPC=checked source=1 ELF64=1 dynamic=12 overflow=4 corrupt=6 source-negative=6 stdout-negative=4 recovery=1 T5M=byte-exact oracle=LOCAL-PINNED energy=NOT-MEASURED"
