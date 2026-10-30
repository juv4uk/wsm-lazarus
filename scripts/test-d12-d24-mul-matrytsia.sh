#!/usr/bin/env bash
# G6.157: 100 executable pinned D5:10110 signed D12×D12 -> exact D12/D24 T5M.
# Test-only host harness; no SENS law, emitter, English dispatch or fake energy.
# 1) Яка різниця між packed .sens і людською .lisp?
# 2) Навіщо перевіряти ELF64 тип та справжній stdout?
# 3) Де доведено promotion D12→D24?
# 4) Чому незалежний oracle мусить мати той самий pin?
# 5) Чому fail-closed перевіряє також відсутність нового ELF?
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д12-МАТРИЦЯ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for cmd in timeout fpc git cmp readelf mktemp grep wc; do
  command -v "$cmd" >/dev/null || { echo "Д12-МАТРИЦЯ-БЛОК: немає $cmd" >&2; exit 127; }
done
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
TMP="$(mktemp -d)"
cleanup() {
  code=$?
  if (( code )); then
    echo "Д12-МАТРИЦЯ-RED exit=$code" >&2
    for log in "$TMP"/*.build "$TMP"/*.err; do
      if [[ -s "$log" ]]; then echo "--- $log" >&2; tail -n 24 "$log" >&2; fi
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
check_heap() {
  if grep -Fq 'unfreed memory blocks' "$1"; then
    grep -Fq '0 unfreed memory blocks' "$1" || {
      cat "$1" >&2; return 1;
    }
  fi
}
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(10110 (ук помножити) (укр помножити)' external/sens/lib/domains/d5.lisp
ORACLE="$(printenv SENS_ORACLE_BIN || true)"
REQUIRE="$(printenv REQUIRE_SENS_ORACLE || echo 0)"
if [[ "$REQUIRE" == 1 ]]; then
  [[ -n "$ORACLE" && -x "$ORACLE" ]] || { echo 'Д12-МАТРИЦЯ-БЛОК: потрібен pinned SENS oracle' >&2; exit 127; }
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-d12-d24-mul-matrytsia "$ROOT/scripts/test-d12-d24-mul-matrytsia.pas" \
  >"$TMP/fixtures.build" 2>&1 || { cat "$TMP/fixtures.build" >&2; exit 1; }
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osenswidefrontelf "$ROOT/src/senswidefrontelf.lpr" \
  >"$TMP/frontend.build" 2>&1 || { cat "$TMP/frontend.build" >&2; exit 1; }
timeout 40s "$TMP/bin/test-d12-d24-mul-matrytsia" "$TMP/physical" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
check_heap "$TMP/fixtures.err"
cat "$TMP/fixtures.out"
grep -Fq 'Д12-МАТРИЦЯ-СВІДКИ-ГОТОВО: cases=100 d12=53 d24=47 negatives=10' "$TMP/fixtures.out" || {
  echo 'Д12-МАТРИЦЯ-RED: неправильна кількість або домен результату' >&2
  exit 1
}
test "$(wc -l < "$TMP/physical/cases.tsv")" -eq 100
MODE=--скомпілювати-фізичну-форму
COUNT=0; WIDE=0; ORACLE_COUNT=0
while IFS=$'\t' read -r label left right wanted width; do
  [[ -n "$label" && -n "$left" && -n "$right" && -n "$wanted" ]]
  elf="$TMP/$label.elf"
  timeout 35s "$TMP/bin/senswidefrontelf" "$MODE" \
    "$TMP/physical/$label.sens" "$elf" >"$TMP/compiler.out" 2>"$TMP/compiler.err"
  check_heap "$TMP/compiler.err"
  grep -Fq 'machine=pinned-exact-WideIR stdout=T5M' "$TMP/compiler.out"
  test -x "$elf"
  timeout 10s readelf -h "$elf" >"$TMP/header.out"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/header.out"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.out"
  timeout 10s "$elf" >"$TMP/actual.sens" 2>"$TMP/elf.err"
  test ! -s "$TMP/elf.err"
  cmp "$TMP/actual.sens" "$TMP/physical/$label.expected.sens"
  if [[ "$width" == 24 ]]; then
    test "$(wc -c < "$TMP/actual.sens")" -eq 5
    WIDE=$((WIDE+1))
  else
    test "$width" -eq 12
    test "$(wc -c < "$TMP/actual.sens")" -eq 3
  fi
  if [[ -n "$ORACLE" ]]; then
    printf '(помножити %s %s)\n' "$left" "$right" >"$TMP/oracle.lisp"
    timeout 60s "$ORACLE" "$TMP/oracle.lisp" >"$TMP/oracle.out" 2>"$TMP/oracle.err"
    test ! -s "$TMP/oracle.err"
    printf '%s\n' "$wanted" >"$TMP/oracle.expected"
    cmp "$TMP/oracle.out" "$TMP/oracle.expected"
    ORACLE_COUNT=$((ORACLE_COUNT+1))
  fi
  COUNT=$((COUNT+1))
done <"$TMP/physical/cases.tsv"
test "$COUNT" -eq 100 && test "$WIDE" -eq 47
if [[ "$REQUIRE" == 1 ]]; then test "$ORACLE_COUNT" -eq 100; fi
NEGATIVE=0
reject() {
  local source="$1" target="$2" status=0
  timeout 35s "$TMP/bin/senswidefrontelf" "$MODE" "$source" "$target" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || status=$?
  test "$status" -eq 2
  test ! -s "$TMP/reject.out"
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/reject.err"
  check_heap "$TMP/reject.err"
  NEGATIVE=$((NEGATIVE+1))
}
for bad in bad-head bad-width missing extra nested two-roots unclosed bad-t5m empty; do
  target="$TMP/reject-$bad.elf"
  reject "$TMP/physical/$bad.sens" "$target"
  test ! -e "$target" && test ! -L "$target"
done
reject "$TMP/physical/fake.lisp" "$TMP/fake.elf"
test ! -e "$TMP/fake.elf"
cp "$TMP/m0-0.elf" "$TMP/occupied.elf"
reject "$TMP/physical/m0-1.sens" "$TMP/occupied.elf"
cmp "$TMP/m0-0.elf" "$TMP/occupied.elf"
ln -s "$TMP/not-present.elf" "$TMP/dangling.elf"
reject "$TMP/physical/m0-2.sens" "$TMP/dangling.elf"
test -L "$TMP/dangling.elf" && test ! -e "$TMP/not-present.elf"
test "$NEGATIVE" -eq 12
echo "Д12-МАТРИЦЯ-PASS native=$COUNT d12=$((COUNT-WIDE)) d24=$WIDE oracle=$ORACLE_COUNT negative=$NEGATIVE energy=NOT-MEASURED"
