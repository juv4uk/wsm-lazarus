#!/usr/bin/env bash
# G6.97 — один compiler entrypoint, 4 exact pinned SENS forms.
# Фізична програма, WideIR, машинний ELF64, independent pinned SENS oracle.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
fail() {
  local rc=$?
  echo "СПІЛЬНИЙ-WIDEIR-ПОМИЛКА: рядок=$1 статус=$rc" >&2
  for f in "$TMP"/negative.err "$TMP"/generator.stderr "$TMP"/*.oracle.err "$TMP"/*.compile.err; do
    if [[ -f "$f" ]]; then echo "--- $f ---" >&2; tail -n 5 "$f" >&2; fi
  done
  exit "$rc"
}
trap 'fail "$LINENO"' ERR
trap 'rm -rf "$TMP"' EXIT
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]]
for exe in fpc git grep cmp timeout objdump readelf dd; do
  command -v "$exe" >/dev/null
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
for word in '01000 (ук нуль?)' '11010 (ук менше?)' '11011 (ук більше?)'; do
  git -C external/sens show HEAD:lib/domains/d5.lisp | grep -F "$word" >/dev/null
done
git -C external/sens show HEAD:lib/domains/d6.lisp |
  grep -F '(010011 (ук модуль) (укр модуль)' >/dev/null
ORACLE=$(printenv SENS_ORACLE_BIN || true)
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
check_heap() {
  local f="$1"
  if [[ -s "$f" ]]; then
    grep -Fq '0 unfreed memory blocks' "$f" || { cat "$f" >&2; return 1; }
  fi
}
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
FPC_BIN=$(printenv FPC || echo fpc)
for row in \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'src/senswidezeroelf.lpr senswidezeroelf' \
  'src/senswidemenelf.lpr senswidemenelf' \
  'src/senswidebilsh-elf.lpr senswidebilsh-elf' \
  'src/senswidemodulelf.lpr senswidemodulelf' \
  'scripts/test-irwidefront.pas test-irwidefront'; do
  read -r source bin <<<"$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$bin" "$ROOT/$source"
  test -x "$TMP/bin/$bin"
done
timeout 30s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.stderr"
grep -Fq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/generator.out"
check_heap "$TMP/generator.stderr"

MODE=--скомпілювати-фізичну-форму
PASS=0
while IFS=$'\t' read -r label kind a b expected width; do
  test -n "$label"
  target="$TMP/$label.elf"
  timeout 20s "$TMP/bin/senswidefrontelf" "$MODE" "$TMP/physical/$label.sens" \
    "$target" >"$TMP/$label.compile.out" 2>"$TMP/$label.compile.err"
  check_heap "$TMP/$label.compile.err"
  grep -Fq 'machine=pinned-exact-WideIR stdout=T5M' "$TMP/$label.compile.out"
  test -x "$target"
  readelf -h "$target" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  dd if="$target" of="$TMP/$label.code" bs=1 skip=120 count=160 status=none
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$label.code" >"$TMP/$label.dis"
  case "$kind" in
    zero) grep -Eiq 'sete[[:space:]]+al' "$TMP/$label.dis" ;;
    less) grep -Eiq 'setl[[:space:]]+al' "$TMP/$label.dis" ;;
    greater) grep -Eiq 'setg[[:space:]]+al' "$TMP/$label.dis" ;;
    abs) grep -Eiq 'cdq' "$TMP/$label.dis"
      grep -Eiq 'xor[[:space:]]+eax,edx' "$TMP/$label.dis"
      grep -Eiq 'sub[[:space:]]+eax,edx' "$TMP/$label.dis" ;;
    *) echo "НЕПІДТРИМАНИЙ ТЕСТОВИЙ ІНДЕКС $kind" >&2; exit 2 ;;
  esac
  timeout 5s "$target" >"$TMP/$label.actual.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.actual.sens"

  # Reference CLI is already verified independent of this front.
  case "$kind" in
    zero)
      timeout 20s "$TMP/bin/senswidezeroelf" --скомпілювати-D5-нуль \
        "$TMP/physical/$label.sens" "$TMP/$label.old.elf" >"$TMP/$label.old.out" 2>"$TMP/$label.old.err" ;;
    less)
      timeout 20s "$TMP/bin/senswidemenelf" --скомпілювати-D5-менше-D12 \
        "$TMP/physical/$label.sens" "$TMP/$label.old.elf" >"$TMP/$label.old.out" 2>"$TMP/$label.old.err" ;;
    greater)
      timeout 20s "$TMP/bin/senswidebilsh-elf" --скомпілювати-D5-більше-D12 \
        "$TMP/physical/$label.sens" "$TMP/$label.old.elf" >"$TMP/$label.old.out" 2>"$TMP/$label.old.err" ;;
    abs)
      timeout 20s "$TMP/bin/senswidemodulelf" --скомпілювати-D6-модуль-D12 \
        "$TMP/physical/$label.sens" "$TMP/$label.old.elf" >"$TMP/$label.old.out" 2>"$TMP/$label.old.err" ;;
  esac
  check_heap "$TMP/$label.old.err"
  cmp "$target" "$TMP/$label.old.elf"
  timeout 20s "$TMP/bin/senswidefrontelf" "$MODE" \
    "$TMP/physical/$label.sens" "$TMP/$label.repeat.elf" >/dev/null 2>"$TMP/$label.repeat.err"
  cmp "$target" "$TMP/$label.repeat.elf"

  if [[ -n "$ORACLE" ]]; then
    case "$kind" in
      zero) printf '(нуль? %s)\n' "$a" >"$TMP/$label.lisp" ;;
      less) printf '(менше? %s %s)\n' "$a" "$b" >"$TMP/$label.lisp" ;;
      greater) printf '(більше? %s %s)\n' "$a" "$b" >"$TMP/$label.lisp" ;;
      abs) printf '(модуль %s)\n' "$a" >"$TMP/$label.lisp" ;;
    esac
    timeout 60s "$ORACLE" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.expected.oracle"
    cmp "$TMP/$label.expected.oracle" "$TMP/$label.oracle.out"
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 16
test "$(wc -c < "$TMP/physical/15.expected.sens")" -eq 5
test "$(wc -c < "$TMP/15.actual.sens")" -eq 5

NEG=0
reject() {
  local target="$TMP/rejected-$NEG.elf" rc=0
  timeout 20s "$TMP/bin/senswidefrontelf" "$@" "$target" \
    >"$TMP/negative.out" 2>"$TMP/negative.err" || rc=$?
  test "$rc" -eq 2 || {
    echo "СПІЛЬНИЙ-WIDEIR: неправильний exit=$rc для негативу $NEG" >&2; exit 1;
  }
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/negative.out"
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/negative.err"
  if grep -Fq 'unfreed memory blocks' "$TMP/negative.err"; then
    grep -Fq '0 unfreed memory blocks' "$TMP/negative.err"
  fi
  NEG=$((NEG+1))
}
for invalid in other-d5 other-d6 other-d7 bad-zero-arity bad-zero-empty \
  bad-zero-d1 bad-zero-d7 bad-less-arity bad-less-d24 bad-less-d1 \
  bad-greater-arity bad-greater-nested bad-abs-arity bad-abs-d24 bad-abs-d3 \
  two-roots dotted unclosed root-atom bad-t5m empty; do
  reject "$MODE" "$TMP/physical/$invalid.sens"
done
reject "$MODE" "$TMP/physical/fake.lisp"
reject "$MODE" "$TMP/physical/nonexistent.sens"
reject --вигадано "$TMP/physical/01.sens"
test "$NEG" -eq 24

cp "$TMP/01.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" "$MODE" "$TMP/physical/16.sens" \
  "$TMP/occupied.elf" >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/01.elf"
ln -s "$TMP/notpresent.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" "$MODE" "$TMP/physical/15.sens" \
  "$TMP/dangling.elf" >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" && test ! -e "$TMP/notpresent.elf"
timeout 20s "$TMP/bin/senswidefrontelf" "$MODE" "$TMP/physical/15.sens" \
  "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/physical/15.expected.sens" "$TMP/recovered.sens"
echo "СПІЛЬНИЙ-WIDEIR-ГАРАЗД physical=$PASS machine=$PASS oracle-if-pinned=$PASS negatives=$NEG D5=3 D6=1 D12-D24=так byte-identical=так joules=НЕ-ВИМІРЯНО"
