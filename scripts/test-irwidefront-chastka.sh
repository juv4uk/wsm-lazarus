#!/usr/bin/env bash
# G6.144: pinned D5:10111 до ВЖЕ спільного verified WideIR, НЕ другий backend.
# Вхід лише canonical packed .sens; число тільки ратифікований D12.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
on_exit() {
  local rc=$? f
  if ((rc)); then
    echo "СПІЛЬНА-Д5-ЧАСТКА-RED: exit=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.compile.err "$TMP"/*.oracle.err \
             "$TMP"/negative.err "$TMP"/generator.err; do
      if [[ -s "$f" ]]; then echo "--- $f" >&2; tail -n 17 "$f" >&2; fi
    done
  fi
  rm -rf "$TMP"
}
trap on_exit EXIT
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д5-ЧАСТКА-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for exe in timeout fpc git cmp grep readelf objdump mktemp wc; do
  command -v "$exe" >/dev/null || {
    echo "Д5-ЧАСТКА-БЛОК: немає $exe" >&2; exit 127;
  }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show HEAD:lib/domains/d5.lisp |
  grep -Fq '(10111 (ук частка) (укр частка)'
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ "${REQUIRE_SENS_ORACLE:-0}" == 1 && -z "$ORACLE" ]]; then
  echo 'Д5-ЧАСТКА-БЛОК: потрібен незалежний pinned SENS REPL' >&2
  exit 127
fi
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
check_heap() {
  local file="$1"
  if grep -Fq 'unfreed memory blocks' "$file"; then
    grep -Fq '0 unfreed memory blocks' "$file" || {
      cat "$file" >&2
      return 1
    }
  fi
}
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
for spec in \
  'scripts/test-irwidequot.pas test-irwidequot' \
  'src/senswidequotelf.lpr senswidequotelf' \
  'src/senswidefrontelf.lpr senswidefrontelf'; do
  read -r source binary <<<"$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/$binary.build" 2>&1 || {
      cat "$TMP/$binary.build" >&2; exit 1;
    }
  test -x "$TMP/bin/$binary"
done
timeout 30s "$TMP/bin/test-irwidequot" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
check_heap "$TMP/generator.err"
test -s "$TMP/physical/cases.tsv"
test "$(wc -l <"$TMP/physical/cases.tsv")" -ge 14

MODE=--скомпілювати-фізичну-форму
EXACT=0; ORACLE_COUNT=0
while IFS=$'\t' read -r label operand; do
  test -n "$label"
  new="$TMP/$label.unified.elf"
  original="$TMP/$label.special.elf"
  timeout 25s "$TMP/bin/senswidefrontelf" "$MODE" \
    "$TMP/physical/$label.sens" "$new" \
    >"$TMP/$label.compile.out" 2>"$TMP/$label.compile.err"
  check_heap "$TMP/$label.compile.err"
  grep -Fq 'machine=pinned-exact-WideIR stdout=T5M' "$TMP/$label.compile.out"
  timeout 25s "$TMP/bin/senswidequotelf" --скомпілювати-D5-частку-D12 \
    "$TMP/physical/$label.sens" "$original" \
    >"$TMP/$label.special.out" 2>"$TMP/$label.special.err"
  check_heap "$TMP/$label.special.err"
  cmp "$new" "$original"
  test -x "$new"
  timeout 5s readelf -h "$new" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  tail -c +121 "$new" >"$TMP/$label.machine"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$label.machine" >"$TMP/$label.dis"
  grep -Eiq '\b(cqo|cqto)\b' "$TMP/$label.dis"
  grep -Eiq 'idiv[[:space:]]+rcx' "$TMP/$label.dis"
  timeout 5s "$new" >"$TMP/$label.actual.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/$label.actual.sens" "$TMP/physical/$label.expected.sens"
  timeout 25s "$TMP/bin/senswidefrontelf" "$MODE" \
    "$TMP/physical/$label.sens" "$TMP/$label.repeated.elf" \
    >/dev/null 2>"$TMP/$label.repeat.err"
  check_heap "$TMP/$label.repeat.err"
  cmp "$new" "$TMP/$label.repeated.elf"
  if [[ -n "$ORACLE" ]]; then
    printf '(частка %s %s)\n' "$operand" "$operand" >"$TMP/$label.lisp"
    timeout 60s "$ORACLE" "$TMP/$label.lisp" >"$TMP/$label.oracle" \
      2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '1\n' >"$TMP/$label.expected.oracle"
    cmp "$TMP/$label.expected.oracle" "$TMP/$label.oracle"
    ORACLE_COUNT=$((ORACLE_COUNT+1))
  fi
  EXACT=$((EXACT+1))
done <"$TMP/physical/cases.tsv"
test "$EXACT" -ge 14
if [[ -n "$ORACLE" ]]; then test "$EXACT" -eq "$ORACLE_COUNT"; fi

# Відхиляємо тільки інваріантно НЕПРАВИЛЬНІ форми.
# Підтримку signed D12 та unequal розширює інший агент (#731):
# НЕ називаємо їх мовними негативами і НЕ торкаємось його backend.
REJECT=0
reject() {
  local rc=0 target="$TMP/rejected-$REJECT.elf"
  timeout 25s "$TMP/bin/senswidefrontelf" "$@" "$target" \
    >"$TMP/negative.out" 2>"$TMP/negative.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/negative.out"
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/negative.err"
  check_heap "$TMP/negative.err"
  REJECT=$((REJECT+1))
}
for invalid in wrong-d7 wrong-width d1 d3-empty d7 missing extra nested \
  two-roots dotted root-atom unclosed close-only bad-t5m empty; do
  reject "$MODE" "$TMP/physical/$invalid.sens"
done
reject "$MODE" "$TMP/physical/fake.lisp"
reject "$MODE" "$TMP/physical/nonexistent.sens"
reject --вигадано "$TMP/physical/01.sens"
test "$REJECT" -eq 18

cp "$TMP/01.unified.elf" "$TMP/occupied.elf"
rc=0
timeout 25s "$TMP/bin/senswidefrontelf" "$MODE" \
  "$TMP/physical/02.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/01.unified.elf"
ln -s "$TMP/absent.elf" "$TMP/dangling.elf"
rc=0
timeout 25s "$TMP/bin/senswidefrontelf" "$MODE" \
  "$TMP/physical/03.sens" "$TMP/dangling.elf" \
  >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" && test ! -e "$TMP/absent.elf"
timeout 25s "$TMP/bin/senswidefrontelf" "$MODE" \
  "$TMP/physical/04.sens" "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/physical/04.expected.sens" "$TMP/recovered.sens"
echo "G6.144-SHARED-QUOT-PASS native=$EXACT identical=$EXACT oracle=$ORACLE_COUNT negatives=$REJECT no-clobber=2 recovery=1 energy=NOT-MEASURED"
# Уже чинний профільний gate 16 фізичних позитивів і 24 негативи.
timeout 500s bash scripts/test-irwidefront.sh
