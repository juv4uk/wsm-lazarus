#!/usr/bin/env bash
# G6.141 — signed D12 у packed D5:10111 програмі, verified WideIR,
# той самий x86-64 CQO/IDIV ELF, що чинний двоатомний механізм.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'Д5-ЧАСТКА-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for exe in fpc timeout git readelf objdump cmp grep mktemp dd; do
  command -v "$exe" >/dev/null || {
    echo "Д5-ЧАСТКА-БЛОК: немає $exe" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(10111 (ук частка) (укр частка)' external/sens/lib/domains/d5.lisp
git -C external/sens show "$PIN:lib/machine/profile/current-domain-x86-64.lisp" |
  grep -F 'CQO+IDIV / додатні 64-бітні цілі; рівні операнди' >/dev/null

ORACLE=$(printenv SENS_ORACLE_BIN || true)
if [[ "$(printenv REQUIRE_SENS_ORACLE || echo 0)" == 1 && -z "$ORACLE" ]]; then
  echo 'Д5-ЧАСТКА-БЛОК: pinned незалежний SENS REPL обов’язковий' >&2
  exit 127
fi
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi

TMP=$(mktemp -d)
finish() {
  local status="$1" line="$2" f
  if (( status != 0 )); then
    echo "Д5-ЧАСТКА-RED: код=$status рядок=$line" >&2
    for f in "$TMP"/*.build "$TMP"/*.err "$TMP"/*.oracle.err \
             "$TMP"/generator.out "$TMP"/negative.err; do
      [[ ! -s "$f" ]] || {
        echo "--- $f" >&2
        tail -n 18 "$f" >&2
      }
    done
  fi
  rm -rf "$TMP"
  exit "$status"
}
trap 'finish "$?" "$LINENO"' EXIT
trap 'echo "Д5-ЧАСТКА-КОМАНДА: рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
FPC_BIN=$(printenv FPC || echo fpc)
for spec in \
  'scripts/test-irwidequot.pas test-irwidequot' \
  'src/senswidequotelf.lpr senswidequotelf' \
  'src/sensd12quot-elf.lpr sensd12quot-elf'; do
  read -r source binary <<<"$spec"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/$binary.build" 2>&1 || {
      cat "$TMP/$binary.build" >&2;exit 1;
    }
  test -x "$TMP/bin/$binary"
done
timeout 30s "$TMP/bin/test-irwidequot" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fq 'G6.141-QUOT-FIXTURES-OK cases=22 negatives=21' \
  "$TMP/generator.out"
if grep -Fq 'unfreed memory blocks' "$TMP/generator.err"; then
  grep -Fq '0 unfreed memory blocks' "$TMP/generator.err"
fi

MODE=--скомпілювати-D5-частку-D12
PASS=0;ORACLE_COUNT=0
while IFS=$'\t' read -r label operand; do
  test -n "$label"
  elf="$TMP/$label.elf"
  timeout 20s "$TMP/bin/senswidequotelf" "$MODE" \
    "$TMP/physical/$label.sens" "$elf" \
    >"$TMP/$label.compile.out" 2>"$TMP/$label.compile.err"
  test -x "$elf"
  grep -Fq 'machine=CQO_IDIV stdout=T5M-D12' "$TMP/$label.compile.out"
  if grep -Fq 'unfreed memory blocks' "$TMP/$label.compile.err"; then
    grep -Fq '0 unfreed memory blocks' "$TMP/$label.compile.err"
  fi
  readelf -h "$elf" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  readelf -l "$elf" >"$TMP/$label.segments"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/$label.segments"
  dd if="$elf" of="$TMP/$label.machine" bs=1 skip=120 status=none
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$label.machine" >"$TMP/$label.asm"
  grep -Eiq '\b(cqo|cqto)\b' "$TMP/$label.asm"
  grep -Eiq 'idiv[[:space:]]+rcx' "$TMP/$label.asm"
  timeout 5s "$elf" >"$TMP/$label.actual.sens" 2>"$TMP/$label.exec.err"
  test ! -s "$TMP/$label.exec.err"
  test "$(wc -c <"$TMP/$label.actual.sens")" -eq 3
  cmp "$TMP/$label.actual.sens" "$TMP/physical/$label.expected.sens"
  timeout 20s "$TMP/bin/sensd12quot-elf" --частка-D12 \
    "$TMP/physical/$label-l.sens" "$TMP/physical/$label-r.sens" \
    "$TMP/$label.old.elf" >"$TMP/$label.old.out" 2>"$TMP/$label.old.err"
  grep -Fq 'machine-cqo-idiv=1' "$TMP/$label.old.out"
  cmp "$elf" "$TMP/$label.old.elf"
  timeout 20s "$TMP/bin/senswidequotelf" "$MODE" \
    "$TMP/physical/$label.sens" "$TMP/$label.repeat.elf" \
    >"$TMP/$label.repeat.out" 2>"$TMP/$label.repeat.err"
  cmp "$elf" "$TMP/$label.repeat.elf"
  if [[ -n "$ORACLE" ]]; then
    printf '(частка %s %s)\n' "$operand" "$operand" >"$TMP/$label.lisp"
    timeout 60s "$ORACLE" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '1\n' >"$TMP/$label.wanted"
    cmp "$TMP/$label.oracle.out" "$TMP/$label.wanted"
    ORACLE_COUNT=$((ORACLE_COUNT+1))
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 22
if [[ -n "$ORACLE" ]]; then test "$ORACLE_COUNT" -eq 22;fi

NEG=0
reject() {
  local source="$1" target="$TMP/rejected-$NEG.elf" rc=0
  timeout 20s "$TMP/bin/senswidequotelf" "$MODE" \
    "$source" "$target" \
    >"$TMP/negative.out" 2>"$TMP/negative.err" || rc=$?
  test "$rc" -eq 2 || {
    echo "Д5-ЧАСТКА: негатив=$NEG код=$rc" >&2;return 1;
  }
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/negative.out"
  grep -Fq 'ЕЛФ-Д5-ЧАСТКА-ВІДМОВА:' "$TMP/negative.err"
  NEG=$((NEG+1))
}
for name in wrong-d5 wrong-d6 wrong-d7 wrong-width \
            d1 d3-empty d7 missing extra nested two-roots dotted \
            root-atom unclosed close-only bad-t5m empty \
            zero unequal unequal-left; do
  reject "$TMP/physical/$name.sens"
done
reject "$TMP/physical/fake.lisp"
reject "$TMP/physical/відсутній.sens"
test "$NEG" -eq 22

# Атомарність і no-clobber перевіряємо на реальному діючому CLI.
cp "$TMP/01.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/senswidequotelf" "$MODE" \
  "$TMP/physical/02.sens" "$TMP/occupied.elf" \
  >"$TMP/no-clobber.out" 2>"$TMP/no-clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/no-clobber.out"
cmp "$TMP/occupied.elf" "$TMP/01.elf"
ln -s "$TMP/відсутній.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswidequotelf" "$MODE" \
  "$TMP/physical/03.sens" "$TMP/dangling.elf" \
  >"$TMP/link.out" 2>"$TMP/link.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/link.out"
test -L "$TMP/dangling.elf" && test ! -e "$TMP/відсутній.elf"
timeout 20s "$TMP/bin/senswidequotelf" "$MODE" \
  "$TMP/physical/04.sens" "$TMP/recovered.elf" >"$TMP/recovered.out"
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/physical/04.expected.sens"
echo "Д5-ЧАСТКА-ELF-ГОТОВО machine=$PASS побайтово=$PASS повтори=$PASS oracle=$ORACLE_COUNT негативи=$NEG no-clobber=2 recovery=1 joules=НЕ-ВИМІРЯНО"

# Тести не створюють жодного нового закону SENS: label/operand —
# host-індекси, усі actual outputs — фізичні D12/T5M байти.
# 1) Чому порівняння ELF важливіше за порівняння тільки числа?
# 2) Хто допускає точний D5:10111?
# 3) Чому українська проєкція потрібна лише незалежному oracle?
# 4) Чому невдалий компілятор не має створювати файлу?