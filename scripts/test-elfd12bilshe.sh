#!/usr/bin/env bash
# G6.78 — signed D12 CMP/SETG ELF64 → фізичний D1 з pinned oracle.
set -Eeuo pipefail
trap 'echo "D12-БІЛЬШЕ-БЛОК рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for t in fpc timeout readelf objdump cmp mktemp grep git; do command -v "$t" >/dev/null || exit 127; done
grep -Fq 'більше? proof "CMP+SETG+MOVZX' sens-oracle/lib/machine/profile/current-domain-x86-64.lisp
grep -Fq '(11011 (ук більше?) (укр більше?)' sens-oracle/lib/domains/d5.lisp
grep -Fq '(schema . numeric-d12-start-extension-1)' sens-oracle/contracts/numeric-domains-ratification.lisp
ORACLE_BIN=$(printenv SENS_ORACLE_BIN || true)
REQUIRE_ORACLE=$(printenv REQUIRE_SENS_ORACLE || echo 0)
if [[ "$REQUIRE_ORACLE" == 1 ]]; then test -n "$ORACLE_BIN"; fi
if [[ -n "$ORACLE_BIN" ]]; then
  test "$(git -C sens-oracle rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
  test -x "$ORACLE_BIN"
fi
TMP=$(mktemp -d);trap 'rm -rf "$TMP"' EXIT
UNITS="$ROOT/build/m0.2/elfd12bilshe/units"
BIN="$ROOT/build/m0.2/elfd12bilshe/bin"
mkdir -p "$UNITS" "$BIN" "$TMP/cases"
FPC_BIN=$(printenv FPC || echo fpc)
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" -osensd12bilsheelf \
  "$ROOT/src/sensd12bilsheelf.lpr" >"$TMP/compile.out" 2>"$TMP/compile.err" || {
    cat "$TMP/compile.out" "$TMP/compile.err" >&2;exit 1; }
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" -otest-elfd12bilshe-fixtures \
  "$ROOT/scripts/test-elfd12bilshe-fixtures.pas" >"$TMP/generator.out" 2>"$TMP/generator.err" || {
    cat "$TMP/generator.out" "$TMP/generator.err" >&2;exit 1; }
timeout 30s "$BIN/test-elfd12bilshe-fixtures" "$TMP/cases" >"$TMP/vectors.tsv" 2>"$TMP/fixtures.err"
grep -Fq 'позитивів=14' "$TMP/fixtures.err"
MACHINE=0;ORACLE=0
while IFS=$'\t' read -r name left right truth; do
  a="$TMP/cases/$name-a.sens";b="$TMP/cases/$name-b.sens"
  elf="$TMP/$name.elf";again="$TMP/$name-again.elf"
  timeout 15s "$BIN/sensd12bilsheelf" --більше-D12 "$a" "$b" "$elf" >"$TMP/publish.out" 2>"$TMP/publish.err"
  test -x "$elf"
  grep -Fq 'machine=CMP/SETG/MOVZX' "$TMP/publish.out"
  timeout 15s "$BIN/sensd12bilsheelf" --більше-D12 "$a" "$b" "$again" >/dev/null
  cmp "$elf" "$again"
  readelf -h "$elf" >"$TMP/$name.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$name.header"
  tail -c +121 "$elf" >"$TMP/$name.code"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$name.code" >"$TMP/$name.dis"
  grep -Eiq 'cmp[[:space:]]+eax,' "$TMP/$name.dis"
  grep -Eiq 'setg[[:space:]]+al' "$TMP/$name.dis"
  grep -Eiq 'movzx[[:space:]]+eax,al' "$TMP/$name.dis"
  timeout 5s "$elf" >"$TMP/$name-machine.sens"
  cmp "$TMP/cases/$name-expected.sens" "$TMP/$name-machine.sens"
  MACHINE=$((MACHINE+1))
  if [[ -n "$ORACLE_BIN" ]]; then
    printf '(більше? %s %s)\n' "$left" "$right" >"$TMP/oracle-input.lisp"
    timeout 60s "$ORACLE_BIN" "$TMP/oracle-input.lisp" >"$TMP/$name.oracle" 2>"$TMP/$name.oracle.err" || {
      cat "$TMP/$name.oracle.err" >&2;exit 1; }
    test ! -s "$TMP/$name.oracle.err"
    printf '%s\n' "$truth" >"$TMP/$name.wanted"
    cmp "$TMP/$name.wanted" "$TMP/$name.oracle"
    ORACLE=$((ORACLE+1))
  fi
done <"$TMP/vectors.tsv"
test "$MACHINE" -eq 14
if [[ -n "$ORACLE_BIN" ]]; then test "$ORACLE" -eq 14; fi
NEG=0
reject() {
  local label=$1;shift
  local dest="$TMP/reject-$label.elf"
  if timeout 15s "$BIN/sensd12bilsheelf" "$@" "$dest" >"$TMP/rejected.out" 2>"$TMP/rejected.err"; then
    echo "D12-БІЛЬШЕ-ПОМИЛКА: прийнято $label" >&2;exit 1
  fi
  test ! -e "$dest";test ! -s "$TMP/rejected.out"
  grep -Fq 'ELF-D12-' "$TMP/rejected.err"
  NEG=$((NEG+1))
}
reject d1 --більше-D12 "$TMP/cases/bad1.sens" "$TMP/cases/01-b.sens"
reject d7 --більше-D12 "$TMP/cases/bad7.sens" "$TMP/cases/01-b.sens"
reject d24 --більше-D12 "$TMP/cases/bad24.sens" "$TMP/cases/01-b.sens"
reject corrupt --більше-D12 "$TMP/cases/corrupt.sens" "$TMP/cases/01-b.sens"
reject empty --більше-D12 "$TMP/cases/empty.sens" "$TMP/cases/01-b.sens"
reject missing --більше-D12 "$TMP/cases/missing.sens" "$TMP/cases/01-b.sens"
cp "$TMP/cases/01-a.sens" "$TMP/cases/fake.lisp"
reject projection --більше-D12 "$TMP/cases/fake.lisp" "$TMP/cases/01-b.sens"
reject mode --невідомий-D12 "$TMP/cases/01-a.sens" "$TMP/cases/01-b.sens"
cp "$TMP/02.elf" "$TMP/occupied.elf"
if timeout 10s "$BIN/sensd12bilsheelf" --більше-D12 "$TMP/cases/02-a.sens" \
  "$TMP/cases/02-b.sens" "$TMP/occupied.elf" >"$TMP/occupied.out" 2>"$TMP/occupied.err"; then
  echo 'D12-БІЛЬШЕ-ПОМИЛКА: переписано ELF' >&2;exit 1
fi
cmp "$TMP/02.elf" "$TMP/occupied.elf"
test ! -s "$TMP/occupied.out"
timeout 15s "$BIN/sensd12bilsheelf" --більше-D12 "$TMP/cases/02-a.sens" \
 "$TMP/cases/02-b.sens" "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/cases/02-expected.sens" "$TMP/recovered.sens"
echo "D12-БІЛЬШЕ-ГОТОВО real-ELF=$MACHINE негативи=$NEG oracle=$ORACLE machine=CMP/SETG/MOVZX D1=T5M energy=NOT_MEASURED"
