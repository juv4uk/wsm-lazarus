#!/usr/bin/env bash
# G6.75: real FPC→CMP/SETL→Linux ELF64, independent pinned SENS oracle.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'D12-МЕНШЕ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout readelf objdump cmp git; do
  command -v "$tool" >/dev/null || {
    echo "D12-МЕНШЕ-БЛОК: потрібен $tool" >&2; exit 127;
  }
done
ORACLE=$(printenv SENS_ORACLE_BIN || true)
[[ -n "$ORACLE" && -x "$ORACLE" ]] || {
  echo 'D12-МЕНШЕ-БЛОК: потрібен SENS_ORACLE_BIN' >&2; exit 127;
}
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
grep -Fq '(11010 (ук менше?) (укр менше?)' external/sens/lib/domains/d5.lisp
grep -Fq '(домен-п' sens-oracle/lib/machine/profile/current-domain-x86-64.lisp
grep -Fq 'CMP+SETL+MOVZX' sens-oracle/lib/machine/profile/current-domain-x86-64.lisp

TMP=$(mktemp -d)
debug_failure() {
  local status=$?
  echo "D12-МЕНШЕ-ПОМИЛКА: line=$1 status=$status command=$BASH_COMMAND" >&2
  for item in "$TMP/свідки.stderr" "$TMP/матриця.tsv" "$TMP/negative.err" "$TMP/"*.build.err "$TMP/"*.oracle.err; do
    if [[ -f "$item" ]]; then
      echo "--- $item ---" >&2
      tail -n 10 "$item" >&2
    fi
  done
  exit "$status"
}
trap 'debug_failure "$LINENO"' ERR
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/свідки"
FPC_BIN=$(printenv FPC || echo fpc)
for row in \
  'src/sensd12mensheelf.lpr sensd12mensheelf' \
  'scripts/test-elfd12menshe-fixtures.pas test-elfd12menshe-fixtures'; do
  read -r source target <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$target" "$ROOT/$source"
  test -x "$TMP/bin/$target"
done
CLI="$TMP/bin/sensd12mensheelf"
timeout 30s "$TMP/bin/test-elfd12menshe-fixtures" "$TMP/свідки" \
  >"$TMP/матриця.tsv" 2>"$TMP/свідки.stderr"
grep -Fq 'D12-LESS-FIXTURES-OK cases=14' "$TMP/свідки.stderr"

PASS=0
while IFS=$'\t' read -r label left right bit; do
  target="$TMP/$label.elf"
  timeout 20s "$CLI" --менше-D12 "$TMP/свідки/$label-l.sens" \
    "$TMP/свідки/$label-r.sens" "$target" >"$TMP/$label.build.out" \
    2>"$TMP/$label.build.err"
  test -x "$target" && test ! -s "$TMP/$label.build.err"
  grep -Fq 'machine=CMP/SETL' "$TMP/$label.build.out"
  readelf -h "$target" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  dd if="$target" of="$TMP/$label.code" bs=1 skip=120 status=none
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$label.code" \
    >"$TMP/$label.dis"
  grep -Eiq 'cmp[[:space:]]+eax,' "$TMP/$label.dis"
  grep -Eiq 'setl[[:space:]]+al' "$TMP/$label.dis"
  grep -Eiq 'movzx[[:space:]]+eax,al' "$TMP/$label.dis"
  timeout 10s "$target" >"$TMP/$label.actual.sens" \
    2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/свідки/$label-expected.sens" "$TMP/$label.actual.sens"
  # Independent pinned SENS evaluator; input is only full укр projection.
  printf '(менше? %s %s)\n' "$left" "$right" >"$TMP/$label.lisp"
  timeout 60s "$ORACLE" "$TMP/$label.lisp" >"$TMP/$label.oracle" \
    2>"$TMP/$label.oracle.err"
  test ! -s "$TMP/$label.oracle.err"
  printf '%s\n' "$bit" >"$TMP/$label.expected.ukr"
  cmp "$TMP/$label.expected.ukr" "$TMP/$label.oracle"
  # Repeat compilation is byte-for-byte deterministic.
  timeout 20s "$CLI" --менше-D12 "$TMP/свідки/$label-l.sens" \
    "$TMP/свідки/$label-r.sens" "$TMP/$label-repeat.elf" \
    >"$TMP/$label.repeat.out" 2>"$TMP/$label.repeat.err"
  cmp "$target" "$TMP/$label-repeat.elf"
  PASS=$((PASS+1))
done <"$TMP/матриця.tsv"
test "$PASS" -eq 14

NEG=0
reject() {
  local name="$1";shift
  local rc=0 target="$TMP/відмовлено-$name.elf"
  timeout 20s "$CLI" "$@" "$target" >"$TMP/negative.out" \
    2>"$TMP/negative.err" || rc=$?
  test "$rc" -eq 2 || {
    echo "D12-МЕНШЕ-ПРОВАЛ: неправильний код $name: $rc" >&2
    cat "$TMP/negative.err" >&2
    exit 1
  }
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/negative.out"
  grep -Fq 'ELF-D12-МЕНШЕ-ВІДМОВА:' "$TMP/negative.err"
  NEG=$((NEG+1))
}
right="$TMP/свідки/02-r.sens"
reject d1 --менше-D12 "$TMP/свідки/bad-d1.sens" "$right"
reject d7 --менше-D12 "$TMP/свідки/bad-d7.sens" "$right"
reject d24 --менше-D12 "$TMP/свідки/bad-d24.sens" "$right"
reject corrupt --менше-D12 "$TMP/свідки/corrupt.sens" "$right"
reject empty --менше-D12 "$TMP/свідки/empty.sens" "$right"
reject missing --менше-D12 "$TMP/свідки/missing.sens" "$right"
reject text --менше-D12 "$TMP/свідки/projection.lisp" "$right"
reject mode --за-назвою "$TMP/свідки/02-l.sens" "$right"
test "$NEG" -eq 8
cp "$TMP/02.elf" "$TMP/зайнятий.elf"
rc=0
timeout 20s "$CLI" --менше-D12 "$TMP/свідки/01-l.sens" \
  "$TMP/свідки/01-r.sens" "$TMP/зайнятий.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2
test ! -s "$TMP/occupied.out"
cmp "$TMP/зайнятий.elf" "$TMP/02.elf"
echo "D12-МЕНШЕ-МАШИНА-ГАРАЗД реальний-FPC=2 ELF=$PASS pinned-оракул=$PASS негативів=$NEG cmp=так setl=так no-clobber=так енергія=НЕ-ВИМІРЯНА"
