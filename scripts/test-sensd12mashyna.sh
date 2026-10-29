#!/usr/bin/env bash
# G6.69: справжні D12→ELF64 машинні ADD/IMUL, а не два емульовані обчислення.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'D12-АOT-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout readelf objdump cmp git; do
  command -v "$tool" >/dev/null || {
    echo "D12-AOT-БЛОК: немає $tool" >&2; exit 127;
  }
done
ORACLE_BIN=$(printenv SENS_ORACLE_BIN || true)
[[ -n "$ORACLE_BIN" && -x "$ORACLE_BIN" ]] || {
  echo 'D12-AOT-БЛОК: потрібен pinned незалежний SENS_ORACLE_BIN' >&2; exit 127;
}
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
test -f external/sens/contracts/language-contract-12.lisp

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/add" "$TMP/mul"
FPC_BIN=$(printenv FPC || echo fpc)
for pair in \
  'src/sensd12mashyna.lpr sensd12mashyna' \
  'scripts/test-elfd12add.pas test-elfd12add' \
  'scripts/test-elfd12mul-fixtures.pas test-elfd12mul-fixtures' \
  'src/senschyslo.lpr senschyslo'; do
  read -r src bin <<< "$pair"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$bin" "$ROOT/$src"
  test -x "$TMP/bin/$bin"
done
CLI="$TMP/bin/sensd12mashyna"
timeout 30s "$TMP/bin/test-elfd12add" "$TMP/add" >"$TMP/add-fixtures.stdout"
timeout 30s "$TMP/bin/test-elfd12mul-fixtures" "$TMP/mul" \
  >"$TMP/mul-fixtures.tsv" 2>"$TMP/mul-fixtures.stderr"
grep -Fq 'D12-MUL-UNIT-NEGATIVE-OK cases=3' "$TMP/mul-fixtures.stderr"

assert_machine() {
  local id="$1" width="$2" mode="$3" left="$4" right="$5" wanted="$6"
  timeout 20s "$CLI" "$mode" "$left" "$right" "$TMP/$id.elf" \
    >"$TMP/$id.compile.out" 2>"$TMP/$id.compile.err"
  test -x "$TMP/$id.elf"
  test ! -s "$TMP/$id.compile.err"
  grep -Fq 'НАТИВНИЙ-D12-ELF-ГОТОВО' "$TMP/$id.compile.out"
  readelf -h "$TMP/$id.elf" >"$TMP/$id.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$id.header"
  timeout 10s "$TMP/$id.elf" >"$TMP/$id.actual.sens" 2>"$TMP/$id.machine.err"
  test ! -s "$TMP/$id.machine.err"
  cmp "$wanted" "$TMP/$id.actual.sens"
  dd if="$TMP/$id.elf" of="$TMP/$id.code" bs=1 skip=120 status=none
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$id.code" >"$TMP/$id.dis"
  if [[ "$mode" == '--додати-D12' ]]; then
    grep -Eiq 'add[[:space:]]+eax,' "$TMP/$id.dis"
  else
    grep -Eiq 'imul.*eax' "$TMP/$id.dis"
  fi
  timeout 10s "$TMP/bin/senschyslo" --в-укр "D$width" "$TMP/$id.actual.sens" \
    >"$TMP/$id.ukr"
  timeout 60s "$ORACLE_BIN" "$TMP/$id.lisp" \
    >"$TMP/$id.oracle" 2>"$TMP/$id.oracle.err"
  test ! -s "$TMP/$id.oracle.err"
  cmp "$TMP/$id.ukr" "$TMP/$id.oracle"
  timeout 20s "$CLI" "$mode" "$left" "$right" "$TMP/$id-again.elf" \
    >"$TMP/$id-again.out" 2>"$TMP/$id-again.err"
  cmp "$TMP/$id.elf" "$TMP/$id-again.elf"
}

PASS=0
for row in '02:31:42:73' '03:-12:7:-5' '05:-2048:2047:-1' '08:2046:1:2047'; do
  IFS=: read -r label left right result <<< "$row"
  id="додавання-$label"
  printf '(додати %s %s)\n' "$left" "$right" >"$TMP/$id.lisp"
  assert_machine "$id" 12 --додати-D12 "$TMP/add/$label-l.sens" \
    "$TMP/add/$label-r.sens" "$TMP/add/$label-expected.sens"
  PASS=$((PASS+1))
done
while IFS=$'\t' read -r label width left right; do
  id="множення-$label"
  printf '(помножити %s %s)\n' "$left" "$right" >"$TMP/$id.lisp"
  assert_machine "$id" "$width" --помножити-D12 "$TMP/mul/$label-a.sens" \
    "$TMP/mul/$label-b.sens" "$TMP/mul/$label-expected.sens"
  PASS=$((PASS+1))
done <"$TMP/mul-fixtures.tsv"
test "$PASS" -eq 8

NEG=0
reject() {
  local tag="$1";shift
  local code=0
  timeout 20s "$CLI" "$@" "$TMP/відмова-$tag.elf" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || code=$?
  test "$code" -eq 2 || {
    echo "D12-AOT-ВІДМОВА: неправильний код $tag $code" >&2; exit 1;
  }
  test ! -e "$TMP/відмова-$tag.elf"
  test ! -s "$TMP/reject.out"
  grep -Fq 'НАТИВНИЙ-D12-ELF-ВІДМОВА:' "$TMP/reject.err"
  NEG=$((NEG+1))
}
cp "$TMP/add/02-l.sens" "$TMP/текст.lisp"
reject текст --додати-D12 "$TMP/текст.lisp" "$TMP/add/02-r.sens"
reject режим --функція-з-тексту "$TMP/add/02-l.sens" "$TMP/add/02-r.sens"
reject overflow --додати-D12 "$TMP/add/overplus-l.sens" "$TMP/add/overplus-r.sens"
reject d24 --помножити-D12 "$TMP/mul/bad-d24.sens" "$TMP/mul/boundary-b.sens"
reject d1 --помножити-D12 "$TMP/mul/d1.sens" "$TMP/mul/boundary-b.sens"
reject corrupt --додати-D12 "$TMP/add/corrupt.sens" "$TMP/add/02-r.sens"
reject empty --додати-D12 "$TMP/add/empty.sens" "$TMP/add/02-r.sens"
reject missing --помножити-D12 "$TMP/mul/missing.sens" "$TMP/mul/boundary-b.sens"
test "$NEG" -eq 8
cp "$TMP/додавання-02.elf" "$TMP/чужа.elf"
code=0
timeout 20s "$CLI" --помножити-D12 "$TMP/mul/negative-a.sens" \
  "$TMP/mul/negative-b.sens" "$TMP/чужа.elf" \
  >"$TMP/no-clobber.out" 2>"$TMP/no-clobber.err" || code=$?
test "$code" -eq 2
test ! -s "$TMP/no-clobber.out"
cmp "$TMP/чужа.elf" "$TMP/додавання-02.elf"
echo "D12-AOT-СПІЛЬНИЙ-ДРАЙВЕР-ГАРАЗД реальний-FPC=4 ELF=8 oracle=8 негативів=$NEG no-clobber=так D12→D24=перевірено"
