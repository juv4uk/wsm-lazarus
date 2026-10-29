#!/usr/bin/env bash
# G6.130 — один FPC-процес, 16 незалежних canonical T5M -> native ELF64.
# Без нового runtime чи мовних законів. Справжнє виконання машинних файлів.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() {
  echo "ПАКЕТ-WIDEIR-ТЕСТ-ПОМИЛКА: рядок=$1 код=$2" >&2
  for f in "$TMP"/negative.err "$TMP"/compile.err "$TMP"/fixture.err; do
    if [[ -f "$f" ]]; then tail -n 12 "$f" >&2; fi
  done
}
trap 'fail "$LINENO" "$?"' ERR

for command_name in fpc git grep cmp timeout readelf sha256sum; do
  command -v "$command_name" >/dev/null
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]]
timeout 60s ./scripts/check-pin.sh
timeout 60s ./scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp

mkdir -p "$TMP"/{bin,units,physical,reference,batch}
FPC_BIN=$(printenv FPC || echo fpc)
for spec in \
  'src/senswidepaketelf.lpr senswidepaketelf' \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'scripts/test-irwidefront.pas test-irwidefront'; do
  read -r source executable <<<"$spec"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
    "-o$executable" "$ROOT/$source"
  test -x "$TMP/bin/$executable"
done
timeout 30s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/fixture.out" 2>"$TMP/fixture.err"
grep -Fq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/fixture.out"

MODE=--скомпілювати-пакет
FRONT_MODE=--скомпілювати-фізичну-форму
INPUTS=()
count=0
while IFS=$'\t' read -r label kind a b expected width; do
  [[ -n "$label" ]]
  INPUTS+=("$TMP/physical/$label.sens")
  timeout 25s "$TMP/bin/senswidefrontelf" "$FRONT_MODE" \
    "$TMP/physical/$label.sens" "$TMP/reference/$label.elf" \
    >"$TMP/reference/$label.log" 2>"$TMP/reference/$label.err"
  count=$((count+1))
done <"$TMP/physical/cases.tsv"
test "$count" -eq 16

timeout 120s "$TMP/bin/senswidepaketelf" "$MODE" "$TMP/batch" \
  "${INPUTS[@]}" >"$TMP/compile.out" 2>"$TMP/compile.err"
grep -Fq 'ПАКЕТ-WIDEIR-ГОТОВО: машинних-ELF=16' "$TMP/compile.out"
test "$(find "$TMP/batch" -maxdepth 1 -name '*.elf' -type f | wc -l)" -eq 16

PASS=0
while IFS=$'\t' read -r label kind a b expected width; do
  test -x "$TMP/batch/$label.elf"
  cmp "$TMP/batch/$label.elf" "$TMP/reference/$label.elf"
  readelf -h "$TMP/batch/$label.elf" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  timeout 5s "$TMP/batch/$label.elf" >"$TMP/$label.actual.sens" \
    2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.actual.sens"
  if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
    test -x "$SENS_ORACLE_BIN"
    test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
    case "$kind" in
      zero) printf '(нуль? %s)\n' "$a" >"$TMP/$label.lisp" ;;
      less) printf '(менше? %s %s)\n' "$a" "$b" >"$TMP/$label.lisp" ;;
      greater) printf '(більше? %s %s)\n' "$a" "$b" >"$TMP/$label.lisp" ;;
      abs) printf '(модуль %s)\n' "$a" >"$TMP/$label.lisp" ;;
      *) echo "невідомий вид тесту $kind" >&2; exit 1 ;;
    esac
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.expected.oracle"
    cmp "$TMP/$label.expected.oracle" "$TMP/$label.oracle.out"
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 16

NEG=0
reject() {
  local label="$1"; shift
  local rc=0
  timeout 40s "$TMP/bin/senswidepaketelf" "$@" \
    >"$TMP/negative.out" 2>"$TMP/negative.err" || rc=$?
  test "$rc" -eq 2 || {
    echo "негатив=$label: очікували 2, отримано $rc" >&2
    return 1
  }
  test ! -s "$TMP/negative.out"
  grep -Fq 'ПАКЕТ-WIDEIR-ВІДМОВА:' "$TMP/negative.err"
  NEG=$((NEG+1))
}
mkdir -p "$TMP"/{bad1,bad2,bad3,bad4,bad5,bad6,bad7,bad8,bad9,bad10}
reject preflight "$MODE" "$TMP/bad1" \
  "$TMP/physical/01.sens" "$TMP/physical/bad-zero-arity.sens"
test ! -e "$TMP/bad1/01.elf"
cp "$TMP/physical/01.sens" "$TMP/physical/false.lisp"
reject projection "$MODE" "$TMP/bad2" "$TMP/physical/false.lisp"
reject duplicates "$MODE" "$TMP/bad3" \
  "$TMP/physical/01.sens" "$TMP/physical/01.sens"
reject damaged "$MODE" "$TMP/bad4" "$TMP/physical/bad-t5m.sens"
cp "$TMP/reference/01.elf" "$TMP/bad5/01.elf"
reject occupied "$MODE" "$TMP/bad5" "$TMP/physical/01.sens"
cmp "$TMP/bad5/01.elf" "$TMP/reference/01.elf"
ln -s "$TMP/not-created" "$TMP/bad6/01.elf"
reject symlink "$MODE" "$TMP/bad6" "$TMP/physical/01.sens"
test -L "$TMP/bad6/01.elf" && test ! -e "$TMP/not-created"
mkdir "$TMP/bad7/01.elf"
reject directory "$MODE" "$TMP/bad7" "$TMP/physical/01.sens"
reject cap "$MODE" "$TMP/bad8" "${INPUTS[@]}" "$TMP/physical/01.sens"
reject invalid-mode --невідомий "$TMP/bad9" "$TMP/physical/01.sens"
reject missing "$MODE" "$TMP/bad10" "$TMP/physical/notpresent.sens"
reject no-directory "$MODE" "$TMP/missing-dir" "$TMP/physical/01.sens"
test "$NEG" -eq 11

# Після fail-closed семантичної відмови не лишається часткового ELF.
timeout 30s "$TMP/bin/senswidepaketelf" "$MODE" "$TMP/bad1" \
  "$TMP/physical/01.sens" >"$TMP/recovery.log" 2>"$TMP/recovery.err"
test -x "$TMP/bad1/01.elf"
cmp "$TMP/bad1/01.elf" "$TMP/reference/01.elf"

echo "G6.130-ПАКЕТ-WIDEIR-ГОТОВО physical=$PASS native=$PASS byte-identical=$PASS negatives=$NEG no-clobber=так recovery=так oracle-if-pinned=$PASS energy=NOT-MEASURED"
