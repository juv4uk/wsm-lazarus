#!/usr/bin/env bash
# G6.221 — реальний Linux stdout gate фізичного багаторазового D12 ELF.
# Існуючий test-verified-all.sh підхоплює сценарій у PR-only fpc-headless.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д12-ПОТІК-WRITE-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
for tool in fpc timeout readelf objdump cmp mktemp grep wc dd tail; do
  command -v "$tool" >/dev/null || {
    echo "Д12-ПОТІК-WRITE-БЛОК: немає $tool" >&2; exit 127;
  }
done
test -c /dev/full
timeout 90s bash "$ROOT/scripts/check-pin.sh"
timeout 20s bash "$ROOT/scripts/check-no-lcl.sh"

TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc!=0)); then
  echo "Д12-ПОТІК-WRITE-ЗБІЙ код=$rc" >&2
  for f in "$TMP"/*.build.log "$TMP"/*.err; do
    if [[ -s "$f" ]]; then echo "-- $f" >&2; tail -25 "$f" >&2; fi
  done
fi
rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units-elf" "$TMP/units-witness" "$TMP/свідки"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/units-elf" -FE"$TMP/bin" \
  -osensd12potikelf "$ROOT/src/sensd12potikelf.lpr" \
  >"$TMP/elf.build.log" 2>&1
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/units-witness" -FE"$TMP/bin" \
  -otest-elfd12potik "$ROOT/scripts/test-elfd12potik.pas" \
  >"$TMP/witness.build.log" 2>&1
timeout 20s "$TMP/bin/test-elfd12potik" "$TMP/свідки" \
  >"$TMP/fixtures.tsv" 2>"$TMP/fixtures.err"
test "$(wc -l <"$TMP/fixtures.tsv")" -eq 13
test -f "$TMP/свідки/05.frame"
test -f "$TMP/свідки/05-expected.sens"

ELF="$TMP/динамічний.elf"
timeout 20s "$TMP/bin/sensd12potikelf" --зібрати-D12-потік "$ELF" \
  >"$TMP/compile.out" 2>"$TMP/compile.err"
test ! -s "$TMP/compile.err" && test -x "$ELF"
grep -Fq 'Д12-ПОТІК-ELF-ГОТОВО' "$TMP/compile.out"
timeout 5s readelf -h "$ELF" >"$TMP/header"
grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header"
dd if="$ELF" of="$TMP/machine" bs=1 skip=120 count=540 status=none
timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
  "$TMP/machine" >"$TMP/disassembly"
grep -Eiq 'add[[:space:]]+eax,r9d' "$TMP/disassembly"
grep -Eiq 'cmp[[:space:]]+rax,0x3' "$TMP/disassembly"
grep -Eiq '[[:space:]]jne[[:space:]]' "$TMP/disassembly"

GOOD=0
BAD=0
RECOVERY=0
for label in 02 03 05 09; do
  frame="$TMP/свідки/$label.frame"
  expected="$TMP/свідки/$label-expected.sens"
  timeout 5s "$ELF" <"$frame" >"$TMP/result.sens" 2>"$TMP/run.err"
  test ! -s "$TMP/run.err"
  cmp "$expected" "$TMP/result.sens"
  test "$(wc -c <"$TMP/result.sens")" -eq 3
  GOOD=$((GOOD+1))

  rc=0
  timeout 5s "$ELF" <"$frame" 1>&- 2>"$TMP/run.err" || rc=$?
  test "$rc" -eq 2
  grep -Fq 'Д12-ПОТІК-ВІДМОВА:' "$TMP/run.err"
  BAD=$((BAD+1))

  rc=0
  timeout 5s "$ELF" <"$frame" >/dev/full 2>"$TMP/run.err" || rc=$?
  test "$rc" -eq 2
  grep -Fq 'Д12-ПОТІК-ВІДМОВА:' "$TMP/run.err"
  BAD=$((BAD+1))

  timeout 5s "$ELF" <"$frame" >"$TMP/recovered.sens" 2>"$TMP/run.err"
  test ! -s "$TMP/run.err"
  cmp "$expected" "$TMP/recovered.sens"
  RECOVERY=$((RECOVERY+1))
done

# Невалідний вхід / переповнення й надалі відхиляються до stdout.
REJECT=0
for label in short1 badsecond overflow-up; do
  rc=0
  timeout 5s "$ELF" <"$TMP/свідки/$label.frame" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/reject.out"
  grep -Fq 'Д12-ПОТІК-ВІДМОВА:' "$TMP/reject.err"
  REJECT=$((REJECT+1))
done
test "$GOOD" -eq 4 && test "$BAD" -eq 8 &&
  test "$RECOVERY" -eq 4 && test "$REJECT" -eq 3
echo "Д12-ПОТІК-WRITE-PASS positives=$GOOD write-negatives=$BAD recovery=$RECOVERY input-negatives=$REJECT physical=D12-T5M machine=ADD/CMP/JNE oracle=NOT-RUN energy=NOT-MEASURED"
