#!/usr/bin/env bash
# G6.134 — атомарний каталог 16 справжніх SENS ELF64, без partial output.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() {
  echo "АТОМ-ПАКЕТ-ТЕСТ-ПОМИЛКА: рядок=$1 статус=$2" >&2
  for f in "$TMP"/error "$TMP"/oracle.err "$TMP"/fixture.err; do
    if [[ -f "$f" ]]; then tail -n 15 "$f" >&2; fi
  done
}
trap 'fail "$LINENO" "$?"' ERR

[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]]
for x in fpc git timeout readelf cmp grep find; do command -v "$x" >/dev/null; done
timeout 60s ./scripts/check-pin.sh
timeout 60s ./scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
mkdir -p "$TMP"/{bin,units,physical,single}
FPC_BIN=$(printenv FPC || echo fpc)
for row in \
  'src/senswideatompaketelf.lpr senswideatompaketelf' \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'scripts/test-irwidefront.pas test-irwidefront'; do
  read -r src bin <<<"$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$bin" "$ROOT/$src"
  test -x "$TMP/bin/$bin"
done
timeout 30s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/fixture.log" 2>"$TMP/fixture.err"
grep -Fq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/fixture.log"
MODE=--скомпілювати-атомарний-пакет
FRONT=--скомпілювати-фізичну-форму
INPUTS=()
while IFS=$'\t' read -r name kind a b expected width; do
  INPUTS+=("$TMP/physical/$name.sens")
  timeout 30s "$TMP/bin/senswidefrontelf" "$FRONT" \
    "$TMP/physical/$name.sens" "$TMP/single/$name.elf" >/dev/null
done <"$TMP/physical/cases.tsv"
test "${#INPUTS[@]}" -eq 16

timeout 120s "$TMP/bin/senswideatompaketelf" "$MODE" "$TMP/published" \
  "${INPUTS[@]}" >"$TMP/success.log" 2>"$TMP/error"
grep -Fq 'АТОМ-ПАКЕТ-ГОТОВО: фізичних-ELF=16' "$TMP/success.log"
test -d "$TMP/published"
test "$(find "$TMP/published" -maxdepth 1 -type f -name '*.elf' | wc -l)" -eq 16
PASS=0
while IFS=$'\t' read -r name kind a b expected width; do
  test -x "$TMP/published/$name.elf"
  cmp "$TMP/published/$name.elf" "$TMP/single/$name.elf"
  readelf -h "$TMP/published/$name.elf" >"$TMP/header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/header"
  timeout 5s "$TMP/published/$name.elf" >"$TMP/actual.sens" 2>"$TMP/machine.err"
  test ! -s "$TMP/machine.err"
  cmp "$TMP/physical/$name.expected.sens" "$TMP/actual.sens"
  if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
    test -x "$SENS_ORACLE_BIN"
    test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
    case "$kind" in
      zero) printf '(нуль? %s)\n' "$a" >"$TMP/oracle.lisp" ;;
      less) printf '(менше? %s %s)\n' "$a" "$b" >"$TMP/oracle.lisp" ;;
      greater) printf '(більше? %s %s)\n' "$a" "$b" >"$TMP/oracle.lisp" ;;
      abs) printf '(модуль %s)\n' "$a" >"$TMP/oracle.lisp" ;;
      *) exit 1 ;;
    esac
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/oracle.lisp" \
      >"$TMP/oracle.out" 2>"$TMP/oracle.err"
    test ! -s "$TMP/oracle.err"
    printf '%s\n' "$expected" >"$TMP/oracle.expected"
    cmp "$TMP/oracle.expected" "$TMP/oracle.out"
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 16
test "$(find "$TMP" -maxdepth 1 -name '.senpak*' | wc -l)" -eq 0

NEG=0
reject() {
  local name="$1"; shift
  local rc=0
  timeout 40s "$TMP/bin/senswideatompaketelf" "$@" \
    >"$TMP/rejected.out" 2>"$TMP/error" || rc=$?
  test "$rc" -eq 2 || {
    echo "Неправильний exit для $name: $rc" >&2; return 1;
  }
  test ! -s "$TMP/rejected.out"
  grep -Fq 'АТОМ-ПАКЕТ-ВІДМОВА:' "$TMP/error"
  test "$(find "$TMP" -maxdepth 1 -name '.senpak*' | wc -l)" -eq 0
  NEG=$((NEG+1))
}
reject occupied "$MODE" "$TMP/published" "${INPUTS[@]}"
test "$(find "$TMP/published" -type f -name '*.elf' | wc -l)" -eq 16
reject late-bad "$MODE" "$TMP/bad-late" \
  "$TMP/physical/01.sens" "$TMP/physical/bad-zero-arity.sens"
test ! -e "$TMP/bad-late"
reject broken-t5m "$MODE" "$TMP/bad-t5m" "$TMP/physical/bad-t5m.sens"
test ! -e "$TMP/bad-t5m"
cp "$TMP/physical/01.sens" "$TMP/physical/fake.lisp"
reject projection "$MODE" "$TMP/bad-lisp" "$TMP/physical/fake.lisp"
test ! -e "$TMP/bad-lisp"
reject duplicate "$MODE" "$TMP/duplicate" \
  "$TMP/physical/01.sens" "$TMP/physical/01.sens"
test ! -e "$TMP/duplicate"
reject overlimit "$MODE" "$TMP/overlimit" "${INPUTS[@]}" "$TMP/physical/01.sens"
test ! -e "$TMP/overlimit"
reject missing "$MODE" "$TMP/missing" "$TMP/physical/no-such.sens"
test ! -e "$TMP/missing"
reject bad-mode --вигадано "$TMP/bad-mode" "$TMP/physical/01.sens"
test ! -e "$TMP/bad-mode"
reject no-parent "$MODE" "$TMP/no-parent/out" "$TMP/physical/01.sens"
test ! -e "$TMP/no-parent"
echo 'недоторканний' >"$TMP/occupied-file"
reject file "$MODE" "$TMP/occupied-file" "$TMP/physical/01.sens"
grep -Fq 'недоторканний' "$TMP/occupied-file"
ln -s "$TMP/no-such-target" "$TMP/dangling"
reject symlink "$MODE" "$TMP/dangling" "$TMP/physical/01.sens"
test -L "$TMP/dangling" && test ! -e "$TMP/no-such-target"
test "$NEG" -eq 11

# Два реальні процеси одночасно претендують на ОДНУ нову назву.
# Один отримує success, другий — відмову renameat2 без replacement.
mkdir -p "$TMP/race"
timeout 120s "$TMP/bin/senswideatompaketelf" "$MODE" "$TMP/race/final" \
  "${INPUTS[@]}" >"$TMP/race/a.out" 2>"$TMP/race/a.err" &
A=$!
timeout 120s "$TMP/bin/senswideatompaketelf" "$MODE" "$TMP/race/final" \
  "${INPUTS[@]}" >"$TMP/race/b.out" 2>"$TMP/race/b.err" &
B=$!
AR=0
BR=0
wait "$A" || AR=$?
wait "$B" || BR=$?
if [[ "$AR" -eq 0 && "$BR" -eq 2 ]]; then
  grep -Fq 'АТОМ-ПАКЕТ-ВІДМОВА:' "$TMP/race/b.err"
elif [[ "$BR" -eq 0 && "$AR" -eq 2 ]]; then
  grep -Fq 'АТОМ-ПАКЕТ-ВІДМОВА:' "$TMP/race/a.err"
else
  echo "гонка: очікували рівно одного переможця, маємо $AR/$BR" >&2; exit 1
fi
test "$(find "$TMP/race/final" -type f -name '*.elf' | wc -l)" -eq 16
for name in 01 08 15 16; do
  cmp "$TMP/race/final/$name.elf" "$TMP/single/$name.elf"
done
test "$(find "$TMP/race" -maxdepth 1 -name '.senpak*' | wc -l)" -eq 0

# Відновлення після preflight відмови: новий цілісний пакет.
timeout 120s "$TMP/bin/senswideatompaketelf" "$MODE" "$TMP/bad-late" \
  "${INPUTS[@]}" >"$TMP/recovery.out" 2>"$TMP/error"
test "$(find "$TMP/bad-late" -type f -name '*.elf' | wc -l)" -eq 16
echo "G6.134-АТОМ-КАТАЛОГ-ГОТОВО physical=$PASS machine=$PASS byte-identical=$PASS negatives=$NEG race=1-of-2 no-partial=так recovery=так oracle-if-pinned=$PASS energy=NOT-MEASURED"
