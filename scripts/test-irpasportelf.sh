#!/usr/bin/env bash
# G6: реальний FPC→pinned WideIR→ELF64 паспорт; жодного нового SENS закону.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc timeout git cmp readelf chmod grep wc mktemp; do
  command -v "$tool" >/dev/null || { echo "ПАСПОРТ-БЛОК: немає $tool" >&2; exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ПАСПОРТ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
TMP=$(mktemp -d)
trap 'rc=$?; printf "ПАСПОРТ-ДІАГНОСТИКА рядок=%s код=%s дія=%s\\n" "$LINENO" "$rc" "$BASH_COMMAND" >&2; for file in "$TMP"/*.passerr "$TMP"/*.passerr2 "$TMP"/*.report "$TMP"/*.err; do if [[ -s "$file" ]]; then echo "=== $file" >&2; tail -n 12 "$file" >&2 || true; fi; done' ERR
trap 'rc=$?; if ((rc)); then echo "ПАСПОРТ-ПРОВАЛ код=$rc" >&2; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"

for row in \
  'scripts/test-irwidefront.pas test-irwidefront' \
  'src/senswidepotikelf.lpr senswidepotikelf' \
  'src/sensirpasportelf.lpr sensirpasportelf'; do
  read -r source name <<< "$row"
  timeout 180s "${FPC:-fpc}" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>&1 || {
      cat "$TMP/$name.build" >&2
      exit 1
    }
  test -x "$TMP/bin/$name"
done
timeout 40s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/generate.out" 2>"$TMP/generate.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/generate.out"
MODE=--паспорт-фізичної-компіляції
ELFMODE=--скомпілювати-фізичний-потік
PASS=0
while IFS=$'\t' read -r label kind a b expected width; do
  [[ -n "$label" ]] || continue
  input="$TMP/physical/$label.sens"
  elf="$TMP/$label.elf"
  report="$TMP/$label.report"
  timeout 30s "$TMP/bin/sensirpasportelf" "$MODE" \
    <"$input" >"$report" 2>"$TMP/$label.passerr"
  timeout 30s "$TMP/bin/sensirpasportelf" "$MODE" \
    <"$input" >"$TMP/$label.report2" 2>"$TMP/$label.passerr2"
  cmp "$report" "$TMP/$label.report2"
  timeout 30s "$TMP/bin/senswidepotikelf" "$ELFMODE" \
    <"$input" >"$elf" 2>"$TMP/$label.elferr"
  readelf -h "$elf" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  ! readelf -l "$elf" | grep -Eq 'INTERP|DYNAMIC'
  # FPC -gh може друкувати лише нульовий підсумок HeapTrc у stderr.
  # Будь-який ненульовий витік чи діагностика — відмова.
  for diagnostic in "$TMP/$label.passerr" "$TMP/$label.passerr2" "$TMP/$label.elferr"; do
    if [[ -s "$diagnostic" ]]; then
      grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$diagnostic" || {
        cat "$diagnostic" >&2
        exit 1
      }
      ! grep -Eq '(^|[[:space:]])[1-9][0-9]* unfreed memory blocks' "$diagnostic"
    fi
  done
  size=$(wc -c <"$elf")
  machine=$((size - 120))
  input_size=$(wc -c <"$input")
  test "$machine" -gt 0
  grep -Fxq 'КОМПІЛЯТОР-ПАСПОРТ-1' "$report"
  grep -Fxq "вхід-байтів=$input_size" "$report"
  grep -Fxq "elf-байтів=$size" "$report"
  grep -Fxq "машинних-байтів=$machine" "$report"
  grep -Fxq 'тип-elf=3' "$report"
  grep -Fxq 'коренів=1' "$report"
  grep -Fxq 'енергія=НЕ-ВИМІРЯНО' "$report"
  grep -Eq '^голова-ширина=[56]$' "$report"
  grep -Eq '^голова-біти=[01]{5,6}$' "$report"
  grep -Eq '^непрозорих-листків=[0-9]+$' "$report"
  chmod 700 "$elf"
  timeout 5s "$elf" >"$TMP/$label.actual.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.actual.sens"
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 16

NEG=0
reject() {
  local source="$1" rc=0
  timeout 30s "$TMP/bin/sensirpasportelf" "$MODE" \
    <"$source" >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/reject.out"
  grep -Fq 'КОМПІЛЯТОР-ПАСПОРТ-ВІДМОВА:' "$TMP/reject.err"
  NEG=$((NEG+1))
}
for bad in bad-t5m two-roots unclosed root-atom dotted \
  bad-zero-arity bad-zero-d1 bad-zero-empty bad-less-arity \
  bad-greater-arity bad-abs-arity bad-abs-d3 bad-zero-d7 \
  bad-less-d1 bad-less-d24 bad-abs-d24; do
  reject "$TMP/physical/$bad.sens"
done
: >"$TMP/empty.sens"
printf '(нуль? 0)\n' >"$TMP/text-ukr.lisp"
head -c 65537 /dev/zero >"$TMP/oversize.sens"
for bad in empty.sens text-ukr.lisp oversize.sens; do
  reject "$TMP/$bad"
done
test "$NEG" -eq 19
# Успіх машинної компіляції не приховує невдалий host stdout.
# /dev/full приймає open, але відкидає Write з ENOSPC.
RC=0
timeout 30s "$TMP/bin/sensirpasportelf" "$MODE" \
  <"$TMP/physical/01.sens" >/dev/full 2>"$TMP/full.err" || RC=$?
test "$RC" -eq 2
grep -Fq 'КОМПІЛЯТОР-ПАСПОРТ-ВІДМОВА:' "$TMP/full.err"
RC=0
timeout 10s "$TMP/bin/sensirpasportelf" --хибний-режим \
  <"$TMP/physical/01.sens" >"$TMP/wrong.out" 2>"$TMP/wrong.err" || RC=$?
test "$RC" -eq 64
test ! -s "$TMP/wrong.out"
grep -Fq 'КОМПІЛЯТОР-ПАСПОРТ-ВІДМОВА:' "$TMP/wrong.err"
# Після відмови той самий фізичний свідок повинен повернути той самий паспорт.
timeout 30s "$TMP/bin/sensirpasportelf" "$MODE" \
  <"$TMP/physical/01.sens" >"$TMP/recovered.report" 2>"$TMP/recovered.err"
cmp "$TMP/01.report" "$TMP/recovered.report"
echo "КОМПІЛЯТОР-ПАСПОРТ-ПРОЙДЕНО фізичних=$PASS elf-виконань=$PASS негативів=$NEG запис-stdout-відмова=1 режим=1 energy=NOT_MEASURED"
