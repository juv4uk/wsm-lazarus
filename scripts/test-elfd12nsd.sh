#!/usr/bin/env bash
# G6.101 — реальна FPC збірка і x86-64 Euclid DIV, pinned oracle.
set -Eeuo pipefail
trap 'echo "D12-НСД-ПОМИЛКА: рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'D12-НСД-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc timeout cmp objdump readelf git mktemp grep; do
  command -v "$tool" >/dev/null || { echo "D12-НСД-БЛОК: немає $tool" >&2; exit 127; }
done
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(010101 (ук нсд) (укр найбільший-спільний-дільник)' external/sens/lib/domains/d6.lisp
[[ -n "${SENS_ORACLE_BIN:-}" && -x "$SENS_ORACLE_BIN" ]] || {
  echo 'D12-НСД-БЛОК: необхідний виконуваний SENS_ORACLE_BIN' >&2; exit 127;
}
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/cases"
for row in   'scripts/test-elfd12nsd-fixtures.pas test-elfd12nsd-fixtures'   'src/sensd12nsdelf.lpr sensd12nsdelf'   'src/senschyslo.lpr senschyslo'; do
  read -r source target <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh     -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin"     "-o$target" "$ROOT/$source" >"$TMP/$target.build.log"
  test -x "$TMP/bin/$target"
done
timeout 30s "$TMP/bin/test-elfd12nsd-fixtures" "$TMP/cases"   >"$TMP/fixtures.stdout" 2>"$TMP/fixtures.stderr"
grep -Fq 'cases=8' "$TMP/fixtures.stdout"
test ! -s "$TMP/fixtures.stderr"
PASS=0
while read -r label left right expected; do
  out="$TMP/$label.elf"
  timeout 20s "$TMP/bin/sensd12nsdelf" --нсд-D12     "$TMP/cases/$label-l.sens" "$TMP/cases/$label-r.sens" "$out"     >"$TMP/$label.build.out" 2>"$TMP/$label.build.err"
  grep -Fq 'machine-euclid-div=1' "$TMP/$label.build.out"
  test ! -s "$TMP/$label.build.err" && test -x "$out"
  readelf -h "$out" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  dd if="$out" of="$TMP/$label.code" bs=1 skip=120 status=none
  objdump -D -b binary -m i386:x86-64 "$TMP/$label.code" >"$TMP/$label.dis"
  grep -Eq 'div[[:space:]]+%ecx' "$TMP/$label.dis"
  grep -Eq 'test[[:space:]]+%ecx,%ecx' "$TMP/$label.dis"
  grep -Eq 'je[[:space:]]' "$TMP/$label.dis"
  grep -Eq 'jmp[[:space:]]' "$TMP/$label.dis"
  timeout 10s "$out" >"$TMP/$label.actual.sens" 2>"$TMP/$label.run.err"
  test ! -s "$TMP/$label.run.err"
  cmp "$TMP/$label.actual.sens" "$TMP/cases/$label-expected.sens"
  test "$(wc -c < "$TMP/$label.actual.sens")" -eq 3
  timeout 10s "$TMP/bin/senschyslo" --в-укр D12 "$TMP/$label.actual.sens" >"$TMP/$label.projected"
  printf '%s\n' "$expected" >"$TMP/$label.want"
  cmp "$TMP/$label.want" "$TMP/$label.projected"
  printf '(найбільший-спільний-дільник %s %s)\n' "$left" "$right" >"$TMP/$label.lisp"
  timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.lisp"     >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
  test ! -s "$TMP/$label.oracle.err"
  cmp "$TMP/$label.want" "$TMP/$label.oracle"
  timeout 20s "$TMP/bin/sensd12nsdelf" --нсд-D12     "$TMP/cases/$label-l.sens" "$TMP/cases/$label-r.sens" "$TMP/$label.repeat.elf" >/dev/null
  cmp "$out" "$TMP/$label.repeat.elf"
  PASS=$((PASS+1))
done <<'CASES'
01 12 18 6
02 24 54 6
03 13 17 1
04 21 21 21
05 2047 2046 1
06 2047 2047 2047
07 144 36 36
08 987 610 1
CASES
test "$PASS" -eq 8
NEG=0
reject() {
  local name="$1"; shift
  local target="$TMP/vidmova-$name.elf" status=0
  timeout 20s "$TMP/bin/sensd12nsdelf" "$@" "$target"     >"$TMP/reject.stdout" 2>"$TMP/reject.stderr" || status=$?
  test "$status" -eq 2
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/reject.stdout"
  grep -Fq 'ELF-D12-' "$TMP/reject.stderr"
  NEG=$((NEG+1))
}
GOOD="$TMP/cases/01-l.sens"
reject zero --нсд-D12 "$TMP/cases/zero.sens" "$GOOD"
reject minus --нсд-D12 "$TMP/cases/negative.sens" "$GOOD"
reject d24 --нсд-D12 "$TMP/cases/bad24.sens" "$GOOD"
reject d1 --нсд-D12 "$TMP/cases/bad1.sens" "$GOOD"
reject d7 --нсд-D12 "$TMP/cases/bad7.sens" "$GOOD"
reject corrupt --нсд-D12 "$TMP/cases/corrupt.sens" "$GOOD"
reject empty --нсд-D12 "$TMP/cases/empty.sens" "$GOOD"
reject missing --нсд-D12 "$TMP/cases/absent.sens" "$GOOD"
cp "$GOOD" "$TMP/fake.lisp"
reject text --нсд-D12 "$TMP/fake.lisp" "$GOOD"
reject mode --невідоме-D12 "$GOOD" "$GOOD"
test "$NEG" -eq 10
cp "$TMP/01.elf" "$TMP/occupied.elf"
status=0
timeout 20s "$TMP/bin/sensd12nsdelf" --нсд-D12 "$GOOD" "$GOOD"   "$TMP/occupied.elf" >"$TMP/occupied.out" 2>"$TMP/occupied.err" || status=$?
test "$status" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/01.elf"
ln -s "$TMP/absent.elf" "$TMP/link.elf"
status=0
timeout 20s "$TMP/bin/sensd12nsdelf" --нсд-D12 "$GOOD" "$GOOD"   "$TMP/link.elf" >"$TMP/link.out" 2>"$TMP/link.err" || status=$?
test "$status" -eq 2 && test ! -s "$TMP/link.out"
test -L "$TMP/link.elf" && test ! -e "$TMP/absent.elf"
timeout 20s "$TMP/bin/sensd12nsdelf" --нсд-D12 "$GOOD" "$GOOD"   "$TMP/recovery.elf" >/dev/null
timeout 10s "$TMP/recovery.elf" >"$TMP/recovery.sens"
# Recovered executable for gcd(12,12) must return D12:12.
timeout 10s "$TMP/bin/senschyslo" --в-укр D12 "$TMP/recovery.sens" >"$TMP/recovery.ukr"
printf '12\n' >"$TMP/recovery.want"
cmp "$TMP/recovery.ukr" "$TMP/recovery.want"
echo "D12-НСД-ГОТОВО реальний-FPC=3 ELF=$PASS oracle=$PASS негативів=$NEG DIV=так no-clobber=так енергія=НЕ-ВИМІРЯНА"
