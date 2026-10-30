#!/usr/bin/env bash
# G6.162 — one source-backed Core1 multiply ELF, many runtime D12 frames.
# No SENS math is implemented here; the independent REPL is the oracle.
# 1) Why are physical anchors distinct from runtime frames?
# 2) Why must the same ELF produce both 3-byte and 5-byte T5M results?
# 3) What does Core1 source admission prove, and what does it not prove?
# 4) Why are malformed D12 anchors rejected before ELF publication?
# 5) Why is this test not an energy benchmark?
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'CORE1-МНОЖЕННЯ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for cmd in timeout fpc git cmp readelf mktemp grep wc ln cp; do
  command -v "$cmd" >/dev/null || { echo "CORE1-МНОЖЕННЯ-БЛОК: немає $cmd" >&2; exit 127; }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
# Admission is checked from physical core1.sens by the Pascal unit;
# never route execution through the human .lisp projection.
ORACLE="${SENS_ORACLE_BIN:-}"
REQUIRE="${REQUIRE_SENS_ORACLE:-0}"
if [[ "$REQUIRE" == 1 ]]; then
  [[ -n "$ORACLE" && -x "$ORACLE" ]] || { echo 'CORE1-МНОЖЕННЯ-БЛОК: потрібен SENS REPL oracle' >&2; exit 127; }
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP="$(mktemp -d)"
cleanup() {
  local status=$?
  if ((status)); then
    echo "CORE1-МНОЖЕННЯ-RED exit=$status" >&2
    for log in "$TMP"/*.build "$TMP"/*.err; do
      if [[ -s "$log" ]]; then echo "--- $log" >&2; tail -n 30 "$log" >&2; fi
    done
  fi
  python3 -c 'import pathlib,shutil,sys;shutil.rmtree(pathlib.Path(sys.argv[1]),ignore_errors=True)' "$TMP"
}
trap cleanup EXIT
check_heap() {
  if grep -Fq 'unfreed memory blocks' "$1"; then
    grep -Fq '0 unfreed memory blocks' "$1" || { cat "$1" >&2; return 1; }
  fi
  if grep -Fq 'ПОМИЛКА:' "$1"; then cat "$1" >&2; return 1; fi
}
mkdir -p "$TMP/bin" "$TMP/fixture-units" "$TMP/cli-units" "$TMP/physical"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/fixture-units" -FE"$TMP/bin" \
  -otest-core1mulpotikfixtures scripts/test-core1mulpotikfixtures.pas \
  >"$TMP/fixtures.build" 2>&1 || { cat "$TMP/fixtures.build" >&2; exit 1; }
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/cli-units" -FE"$TMP/bin" \
  -osenscore1mulpotikelf src/senscore1mulpotikelf.lpr \
  >"$TMP/cli.build" 2>&1 || { cat "$TMP/cli.build" >&2; exit 1; }
timeout 60s "$TMP/bin/test-core1mulpotikfixtures" "$TMP/physical" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
check_heap "$TMP/fixtures.err"
grep -Fq 'CORE1-МНОЖЕННЯ-ФІЗИЧНІ-СВІДКИ-ГОТОВО: cases=16' "$TMP/fixtures.out"
test "$(wc -l < "$TMP/physical/cases.tsv")" -eq 16
# A canonical but altered physical Core1 head must fail admission closed.
mkdir -p "$TMP/fake-repo/external/sens/lib"
cp "$TMP/physical/mutated-core1.sens" "$TMP/fake-repo/external/sens/lib/core1.sens"
timeout 60s "$TMP/bin/test-core1mulpotikfixtures" --reject-mutated "$TMP/fake-repo" \
  >"$TMP/mutated.out" 2>"$TMP/mutated.err"
check_heap "$TMP/mutated.err"
grep -Fq 'CORE1-МНОЖЕННЯ-ЗМІНЕНЕ-ДЖЕРЕЛО-ВІДХИЛЕНО' "$TMP/mutated.out"
ELF="$TMP/core1-mul.elf"
timeout 90s "$TMP/bin/senscore1mulpotikelf" \
  --зібрати-ядро1-множення-потік "$TMP/physical/anchor-left.sens" \
  "$TMP/physical/anchor-right.sens" "$ELF" >"$TMP/build.out" 2>"$TMP/build.err"
test -x "$ELF"
check_heap "$TMP/build.err"
grep -Fq 'stdin=2xT5M-D12 stdout=T5M-D12-or-D24' "$TMP/build.out"
readelf -h "$ELF" >"$TMP/header.out"
grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/header.out"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.out"
COUNT=0; WIDE=0; ORACLE_COUNT=0
while IFS=$'\t' read -r label left right decimal width; do
  [[ -n "$label" && -n "$decimal" ]]
  timeout 8s "$ELF" <"$TMP/physical/$label.frame" \
    >"$TMP/$label.actual.sens" 2>"$TMP/$label.elf.err"
  test ! -s "$TMP/$label.elf.err"
  cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.actual.sens"
  if [[ "$width" == 24 ]]; then
    test "$(wc -c < "$TMP/$label.actual.sens")" -eq 5; WIDE=$((WIDE+1))
  else
    test "$width" -eq 12 && test "$(wc -c < "$TMP/$label.actual.sens")" -eq 3
  fi
  if [[ -n "$ORACLE" ]]; then
    timeout 60s "$ORACLE" "$TMP/physical/$label.oracle.lisp" \
      >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    cmp "$TMP/physical/$label.oracle.expected" "$TMP/$label.oracle.out"
    ORACLE_COUNT=$((ORACLE_COUNT+1))
  fi
  COUNT=$((COUNT+1))
done <"$TMP/physical/cases.tsv"
test "$COUNT" -eq 16 && test "$WIDE" -eq 8
if [[ "$REQUIRE" == 1 ]]; then test "$ORACLE_COUNT" -eq 16; fi
# A second anchor must emit the same input-polymorphic machine image.
timeout 90s "$TMP/bin/senscore1mulpotikelf" \
  --зібрати-ядро1-множення-потік "$TMP/physical/anchor-right.sens" \
  "$TMP/physical/anchor-left.sens" "$TMP/second.elf" >"$TMP/second.out" 2>"$TMP/second.err"
check_heap "$TMP/second.err"
cmp "$ELF" "$TMP/second.elf"
reject() {
  local left="$1" right="$2" out="$3" status=0
  timeout 90s "$TMP/bin/senscore1mulpotikelf" \
    --зібрати-ядро1-множення-потік "$left" "$right" "$out" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || status=$?
  test "$status" -eq 2 && test ! -s "$TMP/reject.out"
  grep -Fq 'CORE1-D12-МНОЖЕННЯ-ПОТІК-ВІДМОВА:' "$TMP/reject.err"
  test ! -e "$out" && test ! -L "$out"
}
NEG=0
reject "$TMP/physical/bad-d24.sens" "$TMP/physical/anchor-right.sens" "$TMP/bad-d24.elf"; NEG=$((NEG+1))
reject "$TMP/physical/bad-pair.sens" "$TMP/physical/anchor-right.sens" "$TMP/bad-pair.elf"; NEG=$((NEG+1))
reject "$TMP/physical/bad-t5m.sens" "$TMP/physical/anchor-right.sens" "$TMP/bad-t5m.elf"; NEG=$((NEG+1))
reject "$TMP/physical/empty.sens" "$TMP/physical/anchor-right.sens" "$TMP/empty.elf"; NEG=$((NEG+1))
reject "$TMP/physical/fake.lisp" "$TMP/physical/anchor-right.sens" "$TMP/fake.elf"; NEG=$((NEG+1))
reject "$TMP/physical/anchor-left.sens" "$TMP/not-found.sens" "$TMP/missing.elf"; NEG=$((NEG+1))
cp "$ELF" "$TMP/occupied.elf"
status=0
timeout 90s "$TMP/bin/senscore1mulpotikelf" \
  --зібрати-ядро1-множення-потік "$TMP/physical/anchor-left.sens" \
  "$TMP/physical/anchor-right.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err" || status=$?
test "$status" -eq 2 && test ! -s "$TMP/occupied.out"
grep -Fq 'CORE1-D12-МНОЖЕННЯ-ПОТІК-ВІДМОВА:' "$TMP/occupied.err"
cmp "$ELF" "$TMP/occupied.elf"; NEG=$((NEG+1))
ln -s "$TMP/missing-target.elf" "$TMP/dangling.elf"
status=0
timeout 90s "$TMP/bin/senscore1mulpotikelf" \
  --зібрати-ядро1-множення-потік "$TMP/physical/anchor-left.sens" \
  "$TMP/physical/anchor-right.sens" "$TMP/dangling.elf" \
  >"$TMP/dangling.out" 2>"$TMP/dangling.err" || status=$?
test "$status" -eq 2 && test ! -s "$TMP/dangling.out"
grep -Fq 'CORE1-D12-МНОЖЕННЯ-ПОТІК-ВІДМОВА:' "$TMP/dangling.err"; NEG=$((NEG+1))
test -L "$TMP/dangling.elf" && test ! -e "$TMP/missing-target.elf"
test "$NEG" -eq 8
echo "CORE1-МНОЖЕННЯ-ПОТІК-PASS inputs=$COUNT d12=$((COUNT-WIDE)) d24=$WIDE oracle=$ORACLE_COUNT negatives=$NEG mutated-source=1 image=reused energy=NOT-MEASURED"
