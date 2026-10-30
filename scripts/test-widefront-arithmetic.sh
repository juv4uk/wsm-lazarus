#!/usr/bin/env bash
# G6.131 — машинний D5 додати/відняти/помножити через спільний WideIR.
set -Eeuo pipefail
trap 'echo "Д5-СПІЛЬНИЙ-ЗЛАМ: рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for x in fpc git timeout readelf objdump cmp mktemp grep; do
  command -v "$x" >/dev/null || { echo "Д5-БЛОК: відсутній $x" >&2;exit 127; }
done
timeout 120s bash scripts/check-pin.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
for h in '01010 (ук додати)' '01011 (ук відняти)' '10110 (ук помножити)'; do
  grep -Fq "$h" external/sens/lib/domains/d5.lisp
done
ORACLE=$(printenv SENS_ORACLE_BIN || true)
if [[ "$(printenv REQUIRE_SENS_ORACLE || echo 0)" == 1 && -z "$ORACLE" ]]; then
  echo 'Д5-БЛОК: потрібен незалежний pinned SENS REPL' >&2;exit 127
fi
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP=$(mktemp -d)
finish() {
  local rc="$1" line="$2" f
  if [[ "$rc" -ne 0 ]]; then
    echo "Д5-СПІЛЬНИЙ-ПОМИЛКА рядок=$line код=$rc" >&2
    for f in "$TMP"/fixtures.out "$TMP"/fixtures.err "$TMP"/*.err "$TMP"/*.build "$TMP"/*.compile.out "$TMP"/negative.out; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 25 "$f" >&2; }
    done
  fi
  rm -rf "$TMP";exit "$rc"
}
trap 'finish "$?" "$LINENO"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
FPC_BIN=$(printenv FPC || echo fpc)
for spec in 'scripts/test-widefront-arithmetic.pas test-widefront-arithmetic' \
            'src/senswidefrontelf.lpr senswidefrontelf'; do
  read -r src bin <<<"$spec"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$bin" \
    "$ROOT/$src" >"$TMP/$bin.build" 2>&1 || {
      cat "$TMP/$bin.build" >&2;exit 1;
    }
  test -x "$TMP/bin/$bin"
done
timeout 30s "$TMP/bin/test-widefront-arithmetic" "$TMP/physical" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
grep -Fq 'Д5-СПІЛЬНИЙ-СВІДКИ-ГАРАЗД physical=12 negatives=8' "$TMP/fixtures.out"
if grep -Fq 'unfreed memory blocks' "$TMP/fixtures.err"; then
  grep -Fq '0 unfreed memory blocks' "$TMP/fixtures.err"
fi
MODE=--скомпілювати-фізичну-форму
PASS=0;ORACLE_COUNT=0;WIDE=0
while IFS=$'\t' read -r tag kind left right wanted width; do
  test -n "$tag"
  elf="$TMP/$tag.elf"
  timeout 25s "$TMP/bin/senswidefrontelf" "$MODE" \
    "$TMP/physical/$tag.sens" "$elf" \
    >"$TMP/$tag.compile.out" 2>"$TMP/$tag.err"
  test -x "$elf"
  grep -Fq 'machine=pinned-exact-WideIR stdout=T5M' "$TMP/$tag.compile.out"
  if grep -Fq 'unfreed memory blocks' "$TMP/$tag.err"; then
    grep -Fq '0 unfreed memory blocks' "$TMP/$tag.err"
  fi
  readelf -h "$elf" >"$TMP/$tag.header"
  grep -Eq 'Type:.*DYN' "$TMP/$tag.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$tag.header"
  readelf -l "$elf" >"$TMP/$tag.segments"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/$tag.segments"
  tail -c +121 "$elf" >"$TMP/$tag.machine"
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$tag.machine" >"$TMP/$tag.asm"
  case "$kind" in
    add) grep -Eiq 'add[[:space:]]+eax,' "$TMP/$tag.asm";surface=додати ;;
    sub) grep -Eiq 'sub[[:space:]]+eax,' "$TMP/$tag.asm";surface=відняти ;;
    mul) grep -Eiq 'imul[[:space:]]+eax,' "$TMP/$tag.asm";surface=помножити ;;
    *) echo "Д5-БЛОК: тестовий індекс $kind" >&2;exit 2 ;;
  esac
  timeout 5s "$elf" >"$TMP/$tag.actual.sens" 2>"$TMP/$tag.machine.err"
  test ! -s "$TMP/$tag.machine.err"
  cmp "$TMP/$tag.actual.sens" "$TMP/physical/$tag.expected.sens"
  if [[ "$width" == 24 ]]; then
    test "$(wc -c <"$TMP/$tag.actual.sens")" -eq 5
    WIDE=$((WIDE+1))
  else
    test "$(wc -c <"$TMP/$tag.actual.sens")" -eq 3
  fi
  timeout 25s "$TMP/bin/senswidefrontelf" "$MODE" \
    "$TMP/physical/$tag.sens" "$TMP/$tag.repeat.elf" \
    >"$TMP/$tag.repeat.out" 2>"$TMP/$tag.repeat.err"
  cmp "$elf" "$TMP/$tag.repeat.elf"
  if [[ -n "$ORACLE" ]]; then
    printf '(%s %s %s)\n' "$surface" "$left" "$right" >"$TMP/$tag.lisp"
    timeout 60s "$ORACLE" "$TMP/$tag.lisp" \
      >"$TMP/$tag.oracle.out" 2>"$TMP/$tag.oracle.err"
    test ! -s "$TMP/$tag.oracle.err"
    printf '%s\n' "$wanted" >"$TMP/$tag.wanted"
    cmp "$TMP/$tag.oracle.out" "$TMP/$tag.wanted"
    ORACLE_COUNT=$((ORACLE_COUNT+1))
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 12
test "$WIDE" -eq 4
if [[ -n "$ORACLE" ]]; then test "$ORACLE_COUNT" -eq 12;fi
NEG=0
reject() {
  local target="$TMP/rejected-$NEG.elf" rc=0
  timeout 20s "$TMP/bin/senswidefrontelf" "$@" "$target" \
    >"$TMP/negative.out" 2>"$TMP/negative.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/negative.out"
  grep -Fq 'ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА:' "$TMP/negative.err"
  NEG=$((NEG+1))
}
for name in wrong-arity wrong-domain wrong-head two-roots \
            unclosed bad-t5m empty; do
  reject "$MODE" "$TMP/physical/$name.sens"
done
reject "$MODE" "$TMP/physical/fake.lisp"
reject "$MODE" "$TMP/physical/missing.sens"
test "$NEG" -eq 9
echo "Д5-СПІЛЬНИЙ-ELF-ГАРАЗД physical=$PASS machine=$PASS повторних=$PASS D24=$WIDE oracle=$ORACLE_COUNT negatives=$NEG joules=НЕ-ВИМІРЯНО"

# Host test indexes are not SENS language dispatch. Owned physical W12,
# ELF, and FPC temporary .ppu/.o files are removed by EXIT trap.
# 1) Чому текстова українська проєкція не компілюється як .sens?
# 2) Чому порівнюємо всі ELF bytes при повторній емісії?
# 3) Чому D24 результат не можна скоротити до D12?
# 4) Де незалежний oracle і що саме він доводить?