#!/usr/bin/env bash
# G6.136: десятий профіль єдиного перевіреного WideIR → ELF64.
# Використовує ТІЛЬКИ вже злитий фізичний D6:010010 backend.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
failed() {
  local rc=$?
  echo "СПІЛЬНИЙ-Д6-ЗНАК-ПРОВАЛ: рядок=$1 код=$rc" >&2
  for f in "$TMP"/negative.err "$TMP"/generator.err "$TMP"/*.compile.err "$TMP"/*.oracle.err; do
    if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -n 12 "$f" >&2; fi
  done
  exit "$rc"
}
trap 'failed "$LINENO"' ERR
trap 'rm -rf "$TMP"' EXIT
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]]
for exe in timeout fpc git grep cmp readelf objdump mktemp; do
  command -v "$exe" >/dev/null
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show HEAD:lib/domains/d6.lisp |
  grep -F '(010010 (ук змінити-знак) (укр змінити-знак)' >/dev/null
git -C external/sens show HEAD:lib/domains/d6.lisp |
  grep -F '(010001 (ук непарне?) (укр непарне?)' >/dev/null
ORACLE="$(printenv SENS_ORACLE_BIN || true)"
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
check_heap() {
  local path="$1"
  if grep -Fq 'unfreed memory blocks' "$path"; then
    grep -Fq '0 unfreed memory blocks' "$path" || {
      cat "$path" >&2; return 1;
    }
  fi
}
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
for row in \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'src/senswidenegelf.lpr senswidenegelf' \
  'scripts/test-irwideneg.pas test-irwideneg'; do
  read -r source bin <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$bin" "$ROOT/$source" \
    >"$TMP/$bin.build.log" 2>&1 || {
      cat "$TMP/$bin.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$bin"
done
timeout 30s "$TMP/bin/test-irwideneg" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fq 'G6.133-NEG-FIXTURES-OK cases=14' "$TMP/generator.out"
check_heap "$TMP/generator.err"

PASS=0
while IFS=$'\t' read -r label value expected width; do
  [[ -n "$label" ]]
  shared="$TMP/$label.shared.elf"
  specialized="$TMP/$label.specialized.elf"
  timeout 20s "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму \
    "$TMP/physical/$label.sens" "$shared" \
    >"$TMP/$label.compile.out" 2>"$TMP/$label.compile.err"
  check_heap "$TMP/$label.compile.err"
  grep -Fq 'machine=pinned-exact-WideIR stdout=T5M' "$TMP/$label.compile.out"
  timeout 20s "$TMP/bin/senswidenegelf" --скомпілювати-D6-змінити-знак-D12 \
    "$TMP/physical/$label.sens" "$specialized" \
    >"$TMP/$label.special.out" 2>"$TMP/$label.special.err"
  check_heap "$TMP/$label.special.err"
  cmp "$shared" "$specialized"
  timeout 5s readelf -h "$shared" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  tail -c +121 "$shared" >"$TMP/$label.machine"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$label.machine" >"$TMP/$label.dis"
  grep -Eiq '\bneg[[:space:]]+eax' "$TMP/$label.dis"
  timeout 5s "$shared" >"$TMP/$label.actual.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.actual.sens"
  timeout 20s "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму \
    "$TMP/physical/$label.sens" "$TMP/$label.repeat.elf" \
    >/dev/null 2>"$TMP/$label.repeat.err"
  check_heap "$TMP/$label.repeat.err"
  cmp "$shared" "$TMP/$label.repeat.elf"
  if [[ -n "$ORACLE" ]]; then
    printf '(змінити-знак %s)\n' "$value" >"$TMP/$label.lisp"
    timeout 60s "$ORACLE" "$TMP/$label.lisp" >"$TMP/$label.oracle" \
      2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.expected.oracle"
    cmp "$TMP/$label.expected.oracle" "$TMP/$label.oracle"
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 14
test "$(wc -c < "$TMP/physical/08.expected.sens")" -eq 5
test "$(wc -c < "$TMP/08.actual.sens")" -eq 5

NEG=0
reject() {
  local target="$TMP/rejected-$NEG.elf" rc=0
  timeout 20s "$TMP/bin/senswidefrontelf" "$@" "$target" \
    >"$TMP/negative.out" 2>"$TMP/negative.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/negative.out"
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/negative.err"
  check_heap "$TMP/negative.err"
  NEG=$((NEG+1))
}
MODE=--скомпілювати-фізичну-форму
# "other-d5" і "other-d6" із генератора вже мають підтримані профілі,
# тому вони НЕ є мовними негативами цього СПІЛЬНОГО компілятора.
for invalid in other-d7 d1 d3-empty d7 d24 missing extra nested \
  two-roots dotted root-atom unclosed close-only bad-t5m empty; do
  reject "$MODE" "$TMP/physical/$invalid.sens"
done
reject "$MODE" "$TMP/physical/fake.lisp"
reject "$MODE" "$TMP/physical/nonexistent.sens"
reject --вигадано "$TMP/physical/01.sens"
test "$NEG" -eq 18

cp "$TMP/01.shared.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" "$MODE" \
  "$TMP/physical/02.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2
test ! -s "$TMP/occupied.out"
cmp "$TMP/01.shared.elf" "$TMP/occupied.elf"
ln -s "$TMP/nonexistent-destination.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" "$MODE" \
  "$TMP/physical/02.sens" "$TMP/dangling.elf" \
  >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2
test -L "$TMP/dangling.elf"
test ! -e "$TMP/nonexistent-destination.elf"
timeout 20s "$TMP/bin/senswidefrontelf" "$MODE" \
  "$TMP/physical/08.sens" "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/physical/08.expected.sens" "$TMP/recovered.sens"
echo "G6.136-WIDE-NEG-PASS ELF=14 repeat=14 byte-identical=14 negatives=18 no-clobber=2 recovered=1 D24=2048 oracle-if-pinned=14 energy=NOT-MEASURED"
# Старі 16 позитивів і 24 негативи мають НЕЗМІННИЙ обов'язковий gate.
timeout 480s bash scripts/test-irwidefront.sh
