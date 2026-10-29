#!/usr/bin/env bash
# G6.87: signed D12 MAX — справжній CMP+CMOVL в машинному ELF64 PIE.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'D12-MAX-БЛОК: потрібний Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout git readelf objdump cmp mktemp grep; do
  command -v "$tool" >/dev/null || { echo "D12-MAX-БЛОК: немає $tool" >&2; exit 127; }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
# Читаємо ратифіковану адресу Д6 з ТОГО САМОГО gitlink, без текстового dispatch.
git -C external/sens show "$PIN:lib/domains/d6.lisp" |
  grep -F '(110111 (ук найбільше) (укр найбільше)' >/dev/null
ORACLE=${SENS_ORACLE_BIN:-}
[[ -n "$ORACLE" && -x "$ORACLE" ]] || { echo 'D12-MAX-БЛОК: немає pinned SENS oracle' >&2; exit 127; }
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
TMP=$(mktemp -d)
trap 'echo "D12-MAX-ЗБІЙ рядок=$LINENO команда=$BASH_COMMAND" >&2; for f in "$TMP"/build-*.log "$TMP"/*.err; do if [[ -f "$f" ]]; then tail -n 18 "$f" >&2; fi; done' ERR
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/fixtures"
for pair in \
  'src/sensd12naibilsheelf.lpr sensd12naibilsheelf' \
  'scripts/test-elfd12max-fixtures.pas test-elfd12max-fixtures' \
  'src/senschyslo.lpr senschyslo'; do
  read -r source target <<< "$pair"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$target" \
    "$ROOT/$source" >"$TMP/build-$target.log" 2>&1
  test -x "$TMP/bin/$target"
done
CLI="$TMP/bin/sensd12naibilsheelf"
timeout 30s "$TMP/bin/test-elfd12max-fixtures" "$TMP/fixtures" \
  >"$TMP/vectors.tsv" 2>"$TMP/fixtures.err"
grep -Fq 'D12-MAX-FIXTURES-OK cases=16' "$TMP/fixtures.err"
PASS=0
while IFS=$'\t' read -r label left right expected; do
  test -n "$label" && test -n "$expected"
  timeout 20s "$CLI" --найбільше-D12 "$TMP/fixtures/$label-l.sens" \
    "$TMP/fixtures/$label-r.sens" "$TMP/$label.elf" \
    >"$TMP/$label.build.out" 2>"$TMP/$label.build.err"
  grep -Fq 'machine-cmp-cmovl=1' "$TMP/$label.build.out"
  test ! -s "$TMP/$label.build.err"
  test -x "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  dd if="$TMP/$label.elf" of="$TMP/$label.code" bs=1 skip=120 status=none
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$label.code" >"$TMP/$label.dis"
  grep -Eiq 'cmp[[:space:]]+eax,ecx' "$TMP/$label.dis"
  grep -Eiq 'cmov(l|nge)[[:space:]]+eax,ecx' "$TMP/$label.dis"
  timeout 10s "$TMP/$label.elf" >"$TMP/$label.actual.sens" 2>"$TMP/$label.actual.err"
  test ! -s "$TMP/$label.actual.err"
  cmp "$TMP/fixtures/$label-expected.sens" "$TMP/$label.actual.sens"
  timeout 10s "$TMP/bin/senschyslo" --в-укр D12 \
    "$TMP/$label.actual.sens" >"$TMP/$label.projected"
  printf '%s\n' "$expected" >"$TMP/$label.expected.txt"
  cmp "$TMP/$label.projected" "$TMP/$label.expected.txt"
  printf '(найбільше %s %s)\n' "$left" "$right" >"$TMP/$label.lisp"
  timeout 60s "$ORACLE" "$TMP/$label.lisp" \
    >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
  test ! -s "$TMP/$label.oracle.err"
  cmp "$TMP/$label.oracle" "$TMP/$label.projected"
  timeout 20s "$CLI" --найбільше-D12 "$TMP/fixtures/$label-l.sens" \
    "$TMP/fixtures/$label-r.sens" "$TMP/$label.again.elf" \
    >"$TMP/$label.again.out" 2>"$TMP/$label.again.err"
  cmp "$TMP/$label.again.elf" "$TMP/$label.elf"
  PASS=$((PASS+1))
done <"$TMP/vectors.tsv"
test "$PASS" -eq 16
NEG=0
reject() {
  local name="$1"; shift
  local rc=0 target="$TMP/rejected-$name.elf"
  timeout 20s "$CLI" "$@" "$target" >"$TMP/rejected.out" \
    2>"$TMP/rejected.err" || rc=$?
  test "$rc" -eq 2 && test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/rejected.out"
  grep -Fq 'ELF-D12-ВІДМОВА:' "$TMP/rejected.err"
  NEG=$((NEG+1))
}
right="$TMP/fixtures/04-r.sens"
reject d1 --найбільше-D12 "$TMP/fixtures/bad1.sens" "$right"
reject d7 --найбільше-D12 "$TMP/fixtures/bad7.sens" "$right"
reject d24 --найбільше-D12 "$TMP/fixtures/bad24.sens" "$right"
reject corrupt --найбільше-D12 "$TMP/fixtures/corrupt.sens" "$right"
reject empty --найбільше-D12 "$TMP/fixtures/empty.sens" "$right"
reject missing --найбільше-D12 "$TMP/fixtures/nonexistent.sens" "$right"
reject projection --найбільше-D12 "$TMP/fixtures/projection.lisp" "$right"
reject mode --не-допущено-D12 "$TMP/fixtures/04-l.sens" "$right"
test "$NEG" -eq 8
cp "$TMP/04.elf" "$TMP/protected.elf"
rc=0
timeout 20s "$CLI" --найбільше-D12 "$TMP/fixtures/11-l.sens" \
  "$TMP/fixtures/11-r.sens" "$TMP/protected.elf" \
  >"$TMP/blocked.out" 2>"$TMP/blocked.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/blocked.out"
cmp "$TMP/protected.elf" "$TMP/04.elf"
ln -s "$TMP/missing-target.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$CLI" --найбільше-D12 "$TMP/fixtures/13-l.sens" \
  "$TMP/fixtures/13-r.sens" "$TMP/dangling.elf" \
  >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/dangling.out"
test -L "$TMP/dangling.elf" && test ! -e "$TMP/missing-target.elf"
timeout 20s "$CLI" --найбільше-D12 "$TMP/fixtures/15-l.sens" \
  "$TMP/fixtures/15-r.sens" "$TMP/recovered.elf" >"$TMP/recovered.out"
timeout 10s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/fixtures/15-expected.sens" "$TMP/recovered.sens"
echo "D12-MAX-CMOVL-OK FPC=checked ELF=$PASS oracle=pinned-SENS negatives=$NEG machine=CMP/CMOVL T5M=exact no-clobber=yes recovery=yes energy=NOT_MEASURED"
