#!/usr/bin/env bash
# G6.149 — один pinned WideIR-компілятор, чотири verified native профілі.
# Повний запис машинної T5M відповіді повинен бути перевіреним Linux I/O.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
finish() {
  local rc=$? f
  if ((rc != 0)); then
    echo "СПІЛЬНИЙ-ЗАПИС-ПРОВАЛ рядок=$1 код=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 12 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap 'finish "$LINENO"' EXIT
for tool in fpc git timeout cmp readelf grep stat tail od tr mktemp;do
  command -v "$tool" >/dev/null || { echo "Немає $tool" >&2;exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
timeout 120s ./scripts/check-pin.sh
timeout 120s ./scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
for word in '01000 (ук нуль?)' '11010 (ук менше?)' '11011 (ук більше?)'; do
  git -C external/sens show HEAD:lib/domains/d5.lisp |
    grep -F "$word" >/dev/null
done
git -C external/sens show HEAD:lib/domains/d6.lisp |
  grep -F '(010011 (ук модуль) (укр модуль)' >/dev/null
ORACLE=${SENS_ORACLE_BIN:-}
if [[ "${REQUIRE_SENS_ORACLE:-0}" == 1 ]]; then test -n "$ORACLE";fi
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
FPC_BIN=${FPC:-fpc}
# Усі front-end отримують один checked FPC build і ті самі pinned таблиці.
for pair in \
  'src/senswidezakhystzahalelf.lpr senswidezakhystzahalelf' \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'scripts/test-irwidefront.pas test-irwidefront'; do
  read -r src executable <<< "$pair"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$executable" \
    "$ROOT/$src" >"$TMP/$executable.build" 2>"$TMP/$executable.err" || {
      cat "$TMP/$executable.build" "$TMP/$executable.err" >&2
      exit 1
    }
  test -x "$TMP/bin/$executable"
done
timeout 45s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/fixtures.out"
check_heap() {
  local file="$1"
  if grep -Fq 'unfreed memory blocks' "$file";then
    grep -Fq '0 unfreed memory blocks' "$file"
  fi
}
check_heap "$TMP/fixtures.err"
MODE=--скомпілювати-захищену-форму
OLDMODE=--скомпілювати-фізичну-форму
PASS=0; FULL=0; ORACLE_PASS=0; ZERO=0;LESS=0;GREATER=0;ABS=0
while IFS=$'\t' read -r label kind a b expected width;do
  test -n "$label"
  src="$TMP/physical/$label.sens"
  elf="$TMP/$label.checked.elf"
  legacy="$TMP/$label.old.elf"
  timeout 20s "$TMP/bin/senswidezakhystzahalelf" "$MODE" \
    "$src" "$elf" >"$TMP/$label.out" 2>"$TMP/$label.err"
  grep -Fq 'write=checked' "$TMP/$label.out"
  check_heap "$TMP/$label.err"
  test -x "$elf"
  test "$(stat -c '%a' "$elf")" = 700
  readelf -h "$elf" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$label.header"
  readelf -l "$elf" >"$TMP/$label.segments"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/$label.segments"
  # Останні 11 байтів — доведений machine cmp eax,edx/setne dil/exit.
  test "$(tail -c 11 "$elf" | od -An -tx1 | tr -d ' \n')" = \
    '39d0400f95c76a3c580f05'
  timeout 5s "$elf" >"$TMP/$label.actual.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.actual.sens"
  timeout 20s "$TMP/bin/senswidefrontelf" "$OLDMODE" \
    "$src" "$legacy" >"$TMP/$label.legacy.out" 2>"$TMP/$label.legacy.err"
  test "$(( $(stat -c '%s' "$elf") - $(stat -c '%s' "$legacy") ))" -eq 11
  timeout 5s "$legacy" >"$TMP/$label.legacy.sens"
  cmp "$TMP/$label.actual.sens" "$TMP/$label.legacy.sens"
  # Linux kernel повертає -ENOSPC при записі у /dev/full.
  rc=0
  timeout 5s "$elf" >/dev/full 2>"$TMP/$label.full.err" || rc=$?
  test "$rc" -eq 1
  test ! -s "$TMP/$label.full.err"
  FULL=$((FULL+1))
  if [[ -n "$ORACLE" ]];then
    case "$kind" in
      zero) printf '(нуль? %s)\n' "$a" >"$TMP/$label.lisp" ;;
      less) printf '(менше? %s %s)\n' "$a" "$b" >"$TMP/$label.lisp" ;;
      greater) printf '(більше? %s %s)\n' "$a" "$b" >"$TMP/$label.lisp" ;;
      abs) printf '(модуль %s)\n' "$a" >"$TMP/$label.lisp" ;;
      *) exit 71 ;;
    esac
    timeout 60s "$ORACLE" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.expected.oracle"
    cmp "$TMP/$label.expected.oracle" "$TMP/$label.oracle"
    ORACLE_PASS=$((ORACLE_PASS+1))
  fi
  case "$kind" in
    zero) ZERO=$((ZERO+1));;
    less) LESS=$((LESS+1));;
    greater) GREATER=$((GREATER+1));;
    abs) ABS=$((ABS+1));;
    *) exit 72;;
  esac
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 16 && test "$FULL" -eq 16
test "$ZERO" -eq 4 && test "$LESS" -eq 4
test "$GREATER" -eq 4 && test "$ABS" -eq 4
if [[ -n "$ORACLE" ]];then test "$ORACLE_PASS" -eq 16;fi
test "$(stat -c '%s' "$TMP/15.actual.sens")" -eq 5

# Незнайомі координати, зламані рамки та проєкції — до публікації ELF.
NEG=0
reject() {
  local target="$TMP/negative-$NEG.elf" rc=0
  timeout 20s "$TMP/bin/senswidezakhystzahalelf" "$@" "$target" \
    >"$TMP/negative.out" 2>"$TMP/negative.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/negative.out"
  grep -Fq 'ВІДМОВА:' "$TMP/negative.err"
  check_heap "$TMP/negative.err"
  NEG=$((NEG+1))
}
for invalid in other-d5 other-d6 other-d7 bad-zero-arity bad-zero-empty \
  bad-zero-d1 bad-zero-d7 bad-less-arity bad-less-d24 bad-less-d1 \
  bad-greater-arity bad-greater-nested bad-abs-arity bad-abs-d24 bad-abs-d3 \
  two-roots dotted unclosed root-atom bad-t5m empty;do
  reject "$MODE" "$TMP/physical/$invalid.sens"
done
reject "$MODE" "$TMP/physical/fake.lisp"
reject "$MODE" "$TMP/physical/nonexistent.sens"
reject --вигадано "$TMP/physical/01.sens"
test "$NEG" -eq 24
cp "$TMP/01.checked.elf" "$TMP/existing.elf"
rc=0
timeout 20s "$TMP/bin/senswidezakhystzahalelf" "$MODE" \
  "$TMP/physical/02.sens" "$TMP/existing.elf" \
  >"$TMP/clobber.out" 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/clobber.out"
cmp "$TMP/01.checked.elf" "$TMP/existing.elf"
ln -s "$TMP/notthere.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswidezakhystzahalelf" "$MODE" \
  "$TMP/physical/03.sens" "$TMP/dangling.elf" \
  >"$TMP/clobber.out" 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/notthere.elf" && test ! -s "$TMP/clobber.out"
timeout 20s "$TMP/bin/senswidezakhystzahalelf" "$MODE" \
  "$TMP/physical/04.sens" "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/physical/04.expected.sens" "$TMP/recovered.sens"
echo "СПІЛЬНИЙ-WIDEIR-ЗАПИС-ГАРАЗД physical=$PASS machine=$PASS enospc=$FULL oracle=$ORACLE_PASS negative=$NEG profiles=4 D12-D24=yes no-clobber=yes energy=NOT-MEASURED"

# Відокремлюємо типи: canonical .sens — фізичні T5M байти;
# kind/label — ЛИШЕ host індекси тесту; .lisp — pinned укр проєкція.
# Result/ELF: owned машиною перевірений output; TMP видаляє EXIT trap.
# Питання: 1) Чому oracle не визначає закон із тексту тесту?
# 2) Чому відмова ENOSPC повинна мати exit(1)?
# 3) Чому порівнюємо стару й нову фізичну T5M відповідь?
# 4) Чому ELF table offsets не можна змістити без RIP patch?
# 5) Чому загальний compiler не означає виконання довільного Core1?
