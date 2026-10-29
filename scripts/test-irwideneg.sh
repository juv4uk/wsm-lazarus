#!/usr/bin/env bash
# G6.133 — справжній FPC/WideIR → machine NEG → T5M D12/D24.
# Повна фізична D6:010010(D12) форма, independent pinned SENS oracle.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
fail_log() {
  local rc=$?
  echo "ШИРОКИЙ-Д6-ЗНАК-ПОМИЛКА: рядок=$1 статус=$rc" >&2
  for f in "$TMP"/negative.err "$TMP"/generator.stderr "$TMP"/*.oracle.err "$TMP"/*.compile.err; do
    if [[ -f "$f" ]]; then
      echo "--- $f ---" >&2
      tail -n 5 "$f" >&2
    fi
  done
  exit "$rc"
}
trap 'fail_log "$LINENO"' ERR
trap 'rm -rf "$TMP"' EXIT
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]]
for tool in fpc git grep cmp timeout objdump readelf dd; do
  command -v "$tool" >/dev/null
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(version . "12.0")' external/sens/contracts/language-contract-12.lisp
# Pinned table may not be present in sparse materialized directory;
# read exactly HEAD's git object instead of inventing/copied authority.
git -C external/sens show HEAD:lib/domains/d6.lisp |
  grep -F '(010011 (ук змінити-знак) (укр змінити-знак)' >/dev/null
ORACLE=$(printenv SENS_ORACLE_BIN || true)
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
check_heap() {
  local f="$1"
  # With -gh Free Pascal may omit a report for a clean process.
  # A nonempty stderr must be the explicit 0-unfreed proof.
  if [[ -s "$f" ]]; then
    grep -Fq '0 unfreed memory blocks' "$f" || {
      cat "$f" >&2
      return 1
    }
  fi
}
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
FPC_BIN=$(printenv FPC || echo fpc)
for row in \
  'src/senswidenegelf.lpr senswidenegelf' \
  'src/sensd12negelf.lpr sensd12negelf' \
  'scripts/test-irwideneg.pas test-irwideneg'; do
  read -r source binary <<<"$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" "$ROOT/$source"
  test -x "$TMP/bin/$binary"
done
timeout 30s "$TMP/bin/test-irwideneg" "$TMP/physical" \
  >"$TMP/generator.stdout" 2>"$TMP/generator.stderr"
grep -Fq 'G6.133-NEG-FIXTURES-OK cases=14' "$TMP/generator.stdout"
check_heap "$TMP/generator.stderr"
test -s "$TMP/physical/cases.tsv"
PASS=0
while IFS=$'\t' read -r label input expected width; do
  test -n "$label"
  elf="$TMP/$label.elf"
  timeout 20s "$TMP/bin/senswidenegelf" --скомпілювати-D6-змінити-знак-D12 \
    "$TMP/physical/$label.sens" "$elf" \
    >"$TMP/$label.compile.out" 2>"$TMP/$label.compile.err"
  check_heap "$TMP/$label.compile.err"
  grep -Fq 'machine=NEG stdout=T5M-D12-D24' "$TMP/$label.compile.out"
  test -x "$elf"
  readelf -h "$elf" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  dd if="$elf" of="$TMP/$label.code" bs=1 skip=120 count=160 status=none
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$label.code" \
    >"$TMP/$label.dis"
  grep -Eiq 'neg[[:space:]]+eax' "$TMP/$label.dis"
  timeout 5s "$elf" >"$TMP/$label.actual.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.actual.sens"
  # The older backend compiles the exact same isolated signed D12 atom.
  # Comparing whole ELF enforces reuse rather than a second custom emitter.
  timeout 20s "$TMP/bin/sensd12negelf" --змінити-знак-D12 \
    "$TMP/physical/$label.atom.sens" "$TMP/$label.old.elf" \
    >/dev/null 2>"$TMP/$label.old.err"
  cmp "$elf" "$TMP/$label.old.elf"
  timeout 20s "$TMP/bin/senswidenegelf" --скомпілювати-D6-змінити-знак-D12 \
    "$TMP/physical/$label.sens" "$TMP/$label.repeat.elf" \
    >/dev/null 2>"$TMP/$label.repeat.err"
  cmp "$elf" "$TMP/$label.repeat.elf"
  if [[ -n "$ORACLE" ]]; then
    printf '(змінити-знак %s)\n' "$input" >"$TMP/$label.lisp"
    timeout 60s "$ORACLE" "$TMP/$label.lisp" >"$TMP/$label.oracle" \
      2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.expected.oracle"
    cmp "$TMP/$label.expected.oracle" "$TMP/$label.oracle"
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 14
# Critical witness -2048 -> D24: expected encoded file must be 5 bytes.
test "$(wc -c <"$TMP/physical/08.expected.sens")" -eq 5
test "$(wc -c <"$TMP/08.actual.sens")" -eq 5

NEG=0
reject() {
  local target="$TMP/rejected-$NEG.elf" rc=0
  timeout 20s "$TMP/bin/senswidenegelf" "$@" "$target" \
    >"$TMP/negative.out" 2>"$TMP/negative.err" || rc=$?
  test "$rc" -eq 2 || {
    echo "ШИРОКИЙ-Д6-ЗНАК: помилковий exit=$rc case=$NEG" >&2
    exit 1
  }
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/negative.out"
  grep -Fq 'ЕЛФ-D6-ЗНАК-ВІДМОВА:' "$TMP/negative.err"
  if grep -Fq 'unfreed memory blocks' "$TMP/negative.err"; then
    grep -Fq '0 unfreed memory blocks' "$TMP/negative.err"
  fi
  NEG=$((NEG+1))
}
MODE=--скомпілювати-D6-змінити-знак-D12
for invalid in other-d6 other-d5 other-d7 d1 d3-empty d7 d24 \
  missing extra nested two-roots dotted root-atom unclosed close-only \
  bad-t5m empty; do
  reject "$MODE" "$TMP/physical/$invalid.sens"
done
reject "$MODE" "$TMP/physical/fake.lisp"
reject "$MODE" "$TMP/physical/nonexistent.sens"
reject --вигадано "$TMP/physical/01.sens"
test "$NEG" -eq 20
cp "$TMP/01.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/senswidenegelf" "$MODE" "$TMP/physical/02.sens" \
  "$TMP/occupied.elf" >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2
test ! -s "$TMP/occupied.out"
cmp "$TMP/01.elf" "$TMP/occupied.elf"
ln -s "$TMP/not-present.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswidenegelf" "$MODE" "$TMP/physical/02.sens" \
  "$TMP/dangling.elf" >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2
test -L "$TMP/dangling.elf" && test ! -e "$TMP/not-present.elf"
timeout 20s "$TMP/bin/senswidenegelf" "$MODE" "$TMP/physical/08.sens" \
  "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/physical/08.expected.sens" "$TMP/recovered.sens"
echo "ШИРОКИЙ-Д6-ЗНАК-ГАРАЗД ELF=$PASS негативів=$NEG pinned-oracle=перевірений-якщо-встановлений old-backend=байтово-тотожно D12_to_D24=-2048→2048 machine=NEG енергія=НЕ-ВИМІРЯНО"
