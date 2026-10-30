#!/usr/bin/env bash
# G6.84 — справжній x86-64 CMP/CMOVG signed min, exact D12 packed T5M.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'D12-MIN-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout readelf objdump cmp git; do
  command -v "$tool" >/dev/null || {
    echo "D12-MIN-БЛОК: немає $tool" >&2; exit 127;
  }
done
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show "$PIN:lib/domains/d6.lisp" |
  grep -F '(110101 (ук найменше) (укр найменше)' >/dev/null
# Машинний профіль — історичний механічний донор, НЕ мовний закон.
git -C external/sens show "$PIN:lib/machine/intel-core-i5-6400.lisp" |
  grep -F 'CMP/CMOV-min' >/dev/null
ORACLE=$(printenv SENS_ORACLE_BIN || true)
[[ -n "$ORACLE" && -x "$ORACLE" ]] || {
  echo 'D12-MIN-БЛОК: немає незалежного pinned SENS_ORACLE_BIN' >&2; exit 127;
}
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"

TMP=$(mktemp -d)
debug_failure() {
  local status=$?
  echo "D12-MIN-ЗБІЙ: line=$1 code=$status cmd=$BASH_COMMAND" >&2
  for f in "$TMP/fixtures.err" "$TMP/fixtures.tsv" "$TMP/"*.build.err \
           "$TMP/"*.oracle.err "$TMP/"*.actual.err "$TMP/rejected.err"; do
    if [[ -f "$f" ]]; then
      echo "--- $f ---" >&2
      tail -n 14 "$f" >&2
    fi
  done
  exit "$status"
}
trap 'debug_failure "$LINENO"' ERR
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/свідки"
FPC_BIN=$(printenv FPC || echo fpc)
for pair in \
  'src/sensd12naimensheelf.lpr sensd12naimensheelf' \
  'scripts/test-elfd12min-fixtures.pas test-elfd12min-fixtures' \
  'src/senschyslo.lpr senschyslo'; do
  read -r source target <<< "$pair"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
    "-o$target" "$ROOT/$source"
  test -x "$TMP/bin/$target"
done
CLI="$TMP/bin/sensd12naimensheelf"
timeout 30s "$TMP/bin/test-elfd12min-fixtures" "$TMP/свідки" \
  >"$TMP/fixtures.tsv" 2>"$TMP/fixtures.err"
grep -Fq 'D12-MIN-FIXTURES-OK cases=16' "$TMP/fixtures.err"

PASS=0
while IFS=$'\t' read -r label left right expected; do
  target="$TMP/$label.elf"
  timeout 20s "$CLI" --найменше-D12 "$TMP/свідки/$label-l.sens" \
    "$TMP/свідки/$label-r.sens" "$target" >"$TMP/$label.build.out" \
    2>"$TMP/$label.build.err"
  grep -Fq 'D12-MIN-ELF-OK machine=CMP/CMOVG' "$TMP/$label.build.out"
  test ! -s "$TMP/$label.build.err" && test -x "$target"
  readelf -h "$target" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  dd if="$target" of="$TMP/$label.code" bs=1 skip=120 status=none
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$label.code" \
    >"$TMP/$label.dis"
  grep -Eiq 'cmp[[:space:]]+eax,ecx' "$TMP/$label.dis"
  grep -Eiq 'cmov(g|nle)[[:space:]]+eax,ecx' "$TMP/$label.dis"
  timeout 10s "$target" >"$TMP/$label.actual.sens" \
    2>"$TMP/$label.actual.err"
  test ! -s "$TMP/$label.actual.err"
  cmp "$TMP/$label.actual.sens" "$TMP/свідки/$label-expected.sens"
  timeout 10s "$TMP/bin/senschyslo" --в-укр D12 \
    "$TMP/$label.actual.sens" >"$TMP/$label.ukr"
  printf '(найменше %s %s)\n' "$left" "$right" >"$TMP/$label.lisp"
  timeout 60s "$ORACLE" "$TMP/$label.lisp" \
    >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
  test ! -s "$TMP/$label.oracle.err"
  cmp "$TMP/$label.oracle" "$TMP/$label.ukr"
  timeout 20s "$CLI" --найменше-D12 "$TMP/свідки/$label-l.sens" \
    "$TMP/свідки/$label-r.sens" "$TMP/$label.again.elf" \
    >"$TMP/$label.again.out" 2>"$TMP/$label.again.err"
  cmp "$target" "$TMP/$label.again.elf"
  PASS=$((PASS+1))
done <"$TMP/fixtures.tsv"
test "$PASS" -eq 16

NEG=0
reject() {
  local label="$1";shift
  local rc=0 dest="$TMP/rejected-$label.elf"
  timeout 20s "$CLI" "$@" "$dest" >"$TMP/rejected.out" \
    2>"$TMP/rejected.err" || rc=$?
  test "$rc" -eq 2 || {
    echo "D12-MIN-НЕВІРНА-ВІДМОВА: $label code=$rc" >&2; exit 1;
  }
  test ! -e "$dest" && test ! -L "$dest"
  test ! -s "$TMP/rejected.out"
  grep -Fq 'D12-MIN-ВІДМОВА:' "$TMP/rejected.err"
  NEG=$((NEG+1))
}
right="$TMP/свідки/04-r.sens"
reject d1 --найменше-D12 "$TMP/свідки/bad1.sens" "$right"
reject d7 --найменше-D12 "$TMP/свідки/bad7.sens" "$right"
reject d24 --найменше-D12 "$TMP/свідки/bad24.sens" "$right"
reject corrupt --найменше-D12 "$TMP/свідки/corrupt.sens" "$right"
reject empty --найменше-D12 "$TMP/свідки/empty.sens" "$right"
reject missing --найменше-D12 "$TMP/свідки/missing.sens" "$right"
reject text --найменше-D12 "$TMP/свідки/projection.lisp" "$right"
reject mode --функція-з-назви "$TMP/свідки/04-l.sens" "$right"
test "$NEG" -eq 8

cp "$TMP/04.elf" "$TMP/зайнятий.elf"
status=0
timeout 20s "$CLI" --найменше-D12 "$TMP/свідки/13-l.sens" \
  "$TMP/свідки/13-r.sens" "$TMP/зайнятий.elf" \
  >"$TMP/no-clobber.out" 2>"$TMP/no-clobber.err" || status=$?
test "$status" -eq 2
test ! -s "$TMP/no-clobber.out"
cmp "$TMP/04.elf" "$TMP/зайнятий.elf"
echo "D12-MIN-CMOV-GARAZD FPC=3 ELF=$PASS pinned-SENS=$PASS negatives=$NEG no-clobber=yes T5M=exact energy=NOT_MEASURED"
