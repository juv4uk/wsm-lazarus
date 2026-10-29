#!/usr/bin/env bash
# G6.99/G6.102: whole physical signed D12 D6:010100 → WideIR → real IDIV ELF.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  echo "D6-ОСТАЧА-ПОМИЛКА: exit=$rc" >&2
  for f in "$TMP"/*.compile.err "$TMP"/*.oracle.err "$TMP"/negative.err; do
    [[ ! -f "$f" ]] || { echo "--- $f" >&2; tail -n 18 "$f" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]]
for tool in timeout fpc git grep cmp readelf objdump dd mktemp; do
  command -v "$tool" >/dev/null || {
    echo "D6-ОСТАЧА-БЛОК: немає $tool" >&2; exit 127;
  }
done
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show HEAD:lib/domains/d6.lisp |
  grep -F '(010100 (ук остача) (укр остача)' >/dev/null
ORACLE="$(printenv SENS_ORACLE_BIN || true)"
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
check_heap() {
  [[ ! -s "$1" ]] || grep -Fq '0 unfreed memory blocks' "$1"
}
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
for row in \
  'src/senswiderestelf.lpr senswiderestelf' \
  'scripts/test-irwiderest.pas test-irwiderest'; do
  read -r source binary <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" "$ROOT/$source" \
    >"$TMP/$binary.build.log" 2>&1 || {
      cat "$TMP/$binary.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$binary"
done
timeout 30s "$TMP/bin/test-irwiderest" "$TMP/physical" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
grep -Fq 'G6.102-REST-FIXTURES-OK cases=28' "$TMP/fixtures.out"
check_heap "$TMP/fixtures.err"
MODE=--скомпілювати-D6-остача-D12
PASS=0
ORACLE_FAILURES=0
while IFS=$'\t' read -r label dividend divisor expected; do
  [[ -n "$label" ]]
  ELF="$TMP/$label.elf"
  timeout 20s "$TMP/bin/senswiderestelf" "$MODE" \
    "$TMP/physical/$label.sens" "$ELF" \
    >"$TMP/$label.compile.out" 2>"$TMP/$label.compile.err"
  check_heap "$TMP/$label.compile.err"
  grep -Fq 'machine=CQO_IDIV_RDX stdout=T5M-D12' "$TMP/$label.compile.out"
  test -x "$ELF"
  timeout 5s readelf -h "$ELF" >"$TMP/$label.readelf"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.readelf"
  dd if="$ELF" of="$TMP/$label.code" bs=1 skip=120 count=120 status=none
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$label.code" >"$TMP/$label.dis"
  grep -Eiq '\bcqo\b' "$TMP/$label.dis"
  grep -Eiq 'idiv[[:space:]]+rcx' "$TMP/$label.dis"
  grep -Eiq 'mov[[:space:]]+eax,edx' "$TMP/$label.dis"
  grep -Eiq 'add[[:space:]]+edx,ecx' "$TMP/$label.dis"
  grep -Eiq '\\bjns\\b' "$TMP/$label.dis"
  timeout 5s "$ELF" >"$TMP/$label.actual.sens" 2>"$TMP/$label.exec.err"
  test ! -s "$TMP/$label.exec.err"
  cmp "$TMP/$label.actual.sens" "$TMP/physical/$label.expected.sens"
  test "$(wc -c < "$TMP/$label.actual.sens")" -eq 3
  timeout 20s "$TMP/bin/senswiderestelf" "$MODE" \
    "$TMP/physical/$label.sens" "$TMP/$label.repeat.elf" \
    >/dev/null 2>"$TMP/$label.repeat.err"
  cmp "$ELF" "$TMP/$label.repeat.elf"
  if [[ -n "$ORACLE" ]]; then
    printf '(остача %s %s)\n' "$dividend" "$divisor" >"$TMP/$label.lisp"
    timeout 60s "$ORACLE" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.expected.oracle"
    if ! cmp "$TMP/$label.expected.oracle" "$TMP/$label.oracle"; then
      printf 'D6-ОСТАЧА-ORACLE-НЕЗБІГ: мітка=%s ділене=%s дільник=%s\n' \
        "$label" "$dividend" "$divisor" >&2
      printf '  очікувано: ' >&2
      cat "$TMP/$label.expected.oracle" >&2
      printf '  фактично:  ' >&2
      cat "$TMP/$label.oracle" >&2
      ORACLE_FAILURES=$((ORACLE_FAILURES+1))
    fi
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 28
if (( ORACLE_FAILURES != 0 )); then
  echo "D6-ОСТАЧА-ORACLE-RED розбіжностей=$ORACLE_FAILURES/$PASS" >&2
  exit 1
fi
NEG=0
reject() {
  local target="$TMP/rejected-$NEG.elf" rc=0
  timeout 20s "$TMP/bin/senswiderestelf" "$@" "$target" \
    >"$TMP/negative.out" 2>"$TMP/negative.err" || rc=$?
  if [[ "$rc" -ne 2 ]]; then
    echo "D6-ОСТАЧА: негатив=$NEG код=$rc" >&2; return 1
  fi
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/negative.out"
  grep -Fq 'ЕЛФ-D6-ОСТАЧА-ВІДМОВА:' "$TMP/negative.err"
  if grep -Fq 'unfreed memory blocks' "$TMP/negative.err"; then
    grep -Fq '0 unfreed memory blocks' "$TMP/negative.err"
  fi
  NEG=$((NEG+1))
}
for invalid in other-d6 other-d5 other-d7 d1 d3-empty d7 d24 \
  missing extra nested two-roots dotted root-atom unclosed close-only \
  bad-t5m empty div-zero d24-right d48-left \
  min-left min-right min-both; do
  reject "$MODE" "$TMP/physical/$invalid.sens"
done
reject "$MODE" "$TMP/physical/fake.lisp"
reject "$MODE" "$TMP/physical/nonexistent.sens"
reject --вигаданий-режим "$TMP/physical/01.sens"
test "$NEG" -eq 26
cp "$TMP/01.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/senswiderestelf" "$MODE" \
  "$TMP/physical/02.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/01.elf" "$TMP/occupied.elf"
ln -s "$TMP/missing-target.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswiderestelf" "$MODE" \
  "$TMP/physical/02.sens" "$TMP/dangling.elf" \
  >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test ! -e "$TMP/missing-target.elf" && test -L "$TMP/dangling.elf"
timeout 20s "$TMP/bin/senswiderestelf" "$MODE" \
  "$TMP/physical/14.sens" "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/physical/14.expected.sens"
echo "D6-ОСТАЧА-ГОТОВО native-elf=$PASS negatives=$NEG no-clobber=2 recovery=1 signed=yes pinned-oracle=when-provided energy=NOT-MEASURED"
