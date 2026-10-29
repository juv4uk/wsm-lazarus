#!/usr/bin/env bash
# G6.80: один checked x86-64 ELF64 для D12 ADD→IMUL, не два процеси.
# Семантичний oracle тільки independent pinned SENS REPL.
set -euo pipefail
trap 'code=$?; echo "D12-КОМПОЗИЦІЯ-ВІДМОВА code=$code рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'D12-КОМПОЗИЦІЯ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout cmp objdump readelf mktemp grep; do
  command -v "$tool" >/dev/null || {
    echo "D12-КОМПОЗИЦІЯ-БЛОК: немає $tool" >&2; exit 127;
  }
done
FPC_BIN=$(printenv FPC || echo fpc)
if [[ -v SENS_ORACLE_BIN ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = \
    1f1bf676eeac605e065035d9dd2adaae807f1788
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/свідки"
for entry in \
  'scripts/test-elfd12addmul.pas test-elfd12addmul' \
  'src/sensd12addmul-elf.lpr sensd12addmul-elf' \
  'src/senschyslo.lpr senschyslo'; do
  read -r path name <<< "$entry"
  if ! timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$path" > "$TMP/$name.build.out" 2> "$TMP/$name.build.err"; then
    cat "$TMP/$name.build.out" "$TMP/$name.build.err" >&2
    exit 1
  fi
  test -x "$TMP/bin/$name"
done
timeout 15s "$TMP/bin/test-elfd12addmul" "$TMP/свідки" \
  >"$TMP/matrix.tsv" 2>"$TMP/fixtures.stderr"
if ! grep -Fq 'D12-КОМПОЗИЦІЯ-СВІДКИ-ГАРАЗД пар=12' "$TMP/fixtures.stderr"; then
  cat "$TMP/fixtures.stderr" >&2; exit 1
fi
test "$(wc -l < "$TMP/matrix.tsv")" = 12
CLI="$TMP/bin/sensd12addmul-elf"
MODE=--додати-потім-помножити-D12
PASS=0
WIDE=0
ORACLE=0
while IFS=$'\t' read -r name a b c width; do
  test -n "$name"
  [[ "$width" == 12 || "$width" == 24 ]]
  timeout 15s "$CLI" "$MODE" \
    "$TMP/свідки/$name-a.sens" "$TMP/свідки/$name-b.sens" \
    "$TMP/свідки/$name-c.sens" "$TMP/$name.elf" \
    >"$TMP/compiler.out" 2>"$TMP/compiler.err"
  test ! -s "$TMP/compiler.err"
  grep -Fq 'D12-ОДИН-ELF-ГОТОВО' "$TMP/compiler.out"
  test -x "$TMP/$name.elf"
  readelf -h "$TMP/$name.elf" > "$TMP/$name.header"
  grep -Eq 'Type:.*DYN' "$TMP/$name.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$name.header"
  tail -c +121 "$TMP/$name.elf" > "$TMP/$name.code"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$name.code" \
    > "$TMP/$name.dis"
  grep -Eiq 'add[[:space:]]+eax,' "$TMP/$name.dis"
  grep -Eiq 'imul[[:space:]]+eax,' "$TMP/$name.dis"
  timeout 5s "$TMP/$name.elf" > "$TMP/$name.out.sens"
  cmp "$TMP/свідки/$name-expected.sens" "$TMP/$name.out.sens"
  "$TMP/bin/senschyslo" --в-укр "D$width" \
    "$TMP/$name.out.sens" > "$TMP/$name.ukr"
  if [[ -v SENS_ORACLE_BIN ]]; then
    # .lisp тут ЛИШЕ одноразова укр-проєкція oracle, не machine source.
    printf '(помножити (додати %s %s) %s)\n' "$a" "$b" "$c" \
      > "$TMP/$name.oracle.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$name.oracle.lisp" \
      > "$TMP/$name.oracle" 2>"$TMP/$name.oracle.err"
    test ! -s "$TMP/$name.oracle.err"
    cmp "$TMP/$name.ukr" "$TMP/$name.oracle"
    ORACLE=$((ORACLE+1))
  fi
  if [[ "$width" == 24 ]]; then WIDE=$((WIDE+1)); fi
  PASS=$((PASS+1))
done < "$TMP/matrix.tsv"
test "$PASS" -eq 12
test "$WIDE" -ge 2
if [[ -v SENS_ORACLE_BIN ]]; then test "$ORACLE" -eq 12; fi
NEG=0
reject() {
  local label=$1; shift
  local status=0
  timeout 15s "$CLI" "$@" "$TMP/$label.elf" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || status=$?
  test "$status" -ne 0 && test "$status" -ne 124
  test ! -e "$TMP/$label.elf"
  test ! -s "$TMP/reject.out"
  grep -Fq 'D12-ОДИН-ELF-ВІДМОВА:' "$TMP/reject.err"
  NEG=$((NEG+1))
}
reject plus "$MODE" "$TMP/свідки/overflow-up.sens" \
  "$TMP/свідки/one.sens" "$TMP/свідки/one.sens"
reject minus "$MODE" "$TMP/свідки/overflow-down.sens" \
  "$TMP/свідки/minus-one.sens" "$TMP/свідки/one.sens"
reject d1 "$MODE" "$TMP/свідки/bad-d1.sens" \
  "$TMP/свідки/01-b.sens" "$TMP/свідки/01-c.sens"
reject d24 "$MODE" "$TMP/свідки/01-a.sens" \
  "$TMP/свідки/bad-d24.sens" "$TMP/свідки/01-c.sens"
reject corrupt "$MODE" "$TMP/свідки/01-a.sens" \
  "$TMP/свідки/01-b.sens" "$TMP/свідки/corrupt.sens"
reject lisp "$MODE" "$TMP/свідки/fake.lisp" \
  "$TMP/свідки/01-b.sens" "$TMP/свідки/01-c.sens"
reject absent "$MODE" "$TMP/свідки/missing.sens" \
  "$TMP/свідки/01-b.sens" "$TMP/свідки/01-c.sens"
reject mode --інше-D12 "$TMP/свідки/01-a.sens" \
  "$TMP/свідки/01-b.sens" "$TMP/свідки/01-c.sens"
cp "$TMP/01.elf" "$TMP/occupied.elf"
status=0
timeout 15s "$CLI" "$MODE" "$TMP/свідки/01-a.sens" \
  "$TMP/свідки/01-b.sens" "$TMP/свідки/01-c.sens" \
  "$TMP/occupied.elf" > "$TMP/reject.out" 2>"$TMP/reject.err" || status=$?
test "$status" -ne 0
test ! -s "$TMP/reject.out"
cmp "$TMP/01.elf" "$TMP/occupied.elf"
timeout 5s "$TMP/01.elf" > "$TMP/repeat.sens"
cmp "$TMP/свідки/01-expected.sens" "$TMP/repeat.sens"
echo "D12-ОДИН-ELF-ГАРАЗД фізичних=$PASS W24=$WIDE oracle=$ORACLE негативів=$NEG ELF=ADD,IMUL разом T5M=точний RAPL=НЕ-ВИМІРЯНО"
