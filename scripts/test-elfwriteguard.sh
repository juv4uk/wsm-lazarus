#!/usr/bin/env bash
# G6.145 — pinned D6:010010 → справжній NEG ELF64 → write(1) fail-closed.
# Енергію НЕ вимірюємо; незалежний upstream SENS використовується як oracle.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
finish() {
  local rc=$? line="$1" f
  if ((rc != 0)); then
    echo "ELF-ЗАПИС-ПРОВАЛ рядок=$line код=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.err; do
      if [[ -s "$f" ]]; then echo "--- $f" >&2;tail -n 12 "$f" >&2;fi
    done
  fi
  rm -rf "$TMP"
}
trap 'finish "$LINENO"' EXIT
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]]
for tool in fpc git timeout cmp readelf grep dd stat find; do
  command -v "$tool" >/dev/null
done
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show HEAD:lib/domains/d6.lisp |
  grep -F '(010010 (ук змінити-знак) (укр змінити-знак)' >/dev/null
ORACLE=${SENS_ORACLE_BIN:-}
if [[ "${REQUIRE_SENS_ORACLE:-0}" == 1 ]]; then test -n "$ORACLE";fi
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
FPC_BIN=${FPC:-fpc}
for pair in \
  'src/senswidezakhystelf.lpr senswidezakhystelf' \
  'src/senswidenegelf.lpr senswidenegelf' \
  'scripts/test-irwideneg.pas test-irwideneg' \
  'scripts/test-elfwriteguard.pas test-elfwriteguard'; do
  read -r src binary <<< "$pair"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$src" >"$TMP/$binary.build" 2>"$TMP/$binary.err" || {
      cat "$TMP/$binary.build" "$TMP/$binary.err" >&2
      exit 1
    }
  test -x "$TMP/bin/$binary"
done
timeout 30s "$TMP/bin/test-irwideneg" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fq 'G6.133-NEG-FIXTURES-OK cases=14' "$TMP/generator.out"
timeout 40s "$TMP/bin/test-elfwriteguard" "$TMP/physical/01.sens" \
  >"$TMP/unit.out" 2>"$TMP/unit.err"
grep -Fq 'G6.145-WRITE-GUARD-UNIT-OK negative=3' "$TMP/unit.out"
# Точні 11 host машинних байтів контрольованого epilogue — не SENS слова.
printf '\x39\xd0\x40\x0f\x95\xc7\x6a\x3c\x58\x0f\x05' \
  >"$TMP/checked-exit.bytes"
MODE=--скомпілювати-D6-безпечний-вивід
OLD_MODE=--скомпілювати-D6-змінити-знак-D12
PASS=0;ENOSPC=0;ORACLE_PASS=0
while IFS=$'\t' read -r tag argument expected width; do
  test -n "$tag"
  source="$TMP/physical/$tag.sens"
  new="$TMP/$tag.checked.elf"
  old="$TMP/$tag.legacy.elf"
  timeout 20s "$TMP/bin/senswidezakhystelf" "$MODE" "$source" "$new" \
    >"$TMP/$tag.status" 2>"$TMP/$tag.err"
  test -x "$new"
  grep -Fq 'write=checked' "$TMP/$tag.status"
  test "$(stat -c '%a' "$new")" = 700
  readelf -h "$new" | grep -Eq 'Type:[[:space:]]+DYN'
  test -z "$(readelf -l "$new" | grep -E 'INTERP|DYNAMIC' || true)"
  tail -c 11 "$new" >"$TMP/$tag.check.bytes"
  cmp "$TMP/checked-exit.bytes" "$TMP/$tag.check.bytes"
  timeout 5s "$new" >"$TMP/$tag.actual.sens" 2>"$TMP/$tag.machine.err"
  cmp "$TMP/physical/$tag.expected.sens" "$TMP/$tag.actual.sens"
  test ! -s "$TMP/$tag.machine.err"
  timeout 20s "$TMP/bin/senswidenegelf" "$OLD_MODE" "$source" "$old" \
    >"$TMP/$tag.legacy.out" 2>"$TMP/$tag.legacy.err"
  timeout 5s "$old" >"$TMP/$tag.legacy.sens"
  cmp "$TMP/$tag.actual.sens" "$TMP/$tag.legacy.sens"
  # /dev/full returns -ENOSPC to the real kernel sys_write; no success exit.
  rc=0
  timeout 5s "$new" >/dev/full 2>"$TMP/$tag.full.err" || rc=$?
  test "$rc" -eq 1
  test ! -s "$TMP/$tag.full.err"
  ENOSPC=$((ENOSPC+1))
  if [[ -n "$ORACLE" ]]; then
    printf '(змінити-знак %s)\n' "$argument" >"$TMP/$tag.lisp"
    timeout 60s "$ORACLE" "$TMP/$tag.lisp" \
      >"$TMP/$tag.oracle" 2>"$TMP/$tag.oracle.err"
    test ! -s "$TMP/$tag.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$tag.wanted"
    cmp "$TMP/$tag.wanted" "$TMP/$tag.oracle"
    ORACLE_PASS=$((ORACLE_PASS+1))
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 14
test "$ENOSPC" -eq 14
if [[ -n "$ORACLE" ]]; then test "$ORACLE_PASS" -eq 14;fi
test "$(wc -c <"$TMP/08.actual.sens")" -eq 5

# На поганому джерелі немає ані часткового ELF, ані позитивного stdout.
NEG=0
reject() {
  local target="$TMP/reject-$NEG.elf" rc=0
  timeout 20s "$TMP/bin/senswidezakhystelf" "$@" "$target" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/reject.out"
  grep -Fq 'ЕЛФ-D6-ЗНАК-ВІДМОВА:' "$TMP/reject.err"
  NEG=$((NEG+1))
}
reject "$MODE" "$TMP/physical/other-d6.sens"
reject "$MODE" "$TMP/physical/d24.sens"
reject "$MODE" "$TMP/physical/bad-t5m.sens"
reject "$MODE" "$TMP/physical/fake.lisp"
reject "$MODE" "$TMP/physical/missing-file.sens"
reject --вигаданий "$TMP/physical/01.sens"
test "$NEG" -eq 6
cp "$TMP/01.checked.elf" "$TMP/existing.elf"
rc=0
timeout 20s "$TMP/bin/senswidezakhystelf" "$MODE" \
  "$TMP/physical/02.sens" "$TMP/existing.elf" \
  >"$TMP/clobber.out" 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2
test ! -s "$TMP/clobber.out"
cmp "$TMP/existing.elf" "$TMP/01.checked.elf"
ln -s "$TMP/missing.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswidezakhystelf" "$MODE" \
  "$TMP/physical/02.sens" "$TMP/dangling.elf" \
  >"$TMP/clobber.out" 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2
test -L "$TMP/dangling.elf" && test ! -e "$TMP/missing.elf"
test -z "$(find "$TMP" -name 'sen??????' -print -quit)"
echo "G6.145-ELF-WRITE-GUARD-OK physical=$PASS machine=$PASS enospc=$ENOSPC oracle=$ORACLE_PASS negative=$NEG postpass-negative=3 D12-D24=yes joules=NOT-MEASURED"

# W12 фізично позичений і не інтерпретується test shell за unicode назвою.
# 1) Чому перевірка ENOSPC потребує саме запуску згенерованого ELF?
# 2) Чому результат двійковий T5M, а не людське десяткове число?
# 3) Чому перевірки за pinned REPL не можна замінити cmp двох ELF?
# 4) Як sys_exit(1) запобігає хибному позитиву у benchmark harness?
