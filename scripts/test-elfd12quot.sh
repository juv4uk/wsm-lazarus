#!/usr/bin/env bash
# G6.78 — справжній CQO + IDIV, шість canonical фізичних D12 позитивів.
set -euo pipefail
trap 'echo "D12-IDIV-БЛОК рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for exe in fpc timeout cmp objdump readelf grep git mktemp; do
  command -v "$exe" >/dev/null || { echo "D12-IDIV-БЛОК: немає $exe" >&2; exit 127; }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
# Sparse authority workspace не матеріалізує цей профіль; беремо
# його безпосередньо з ТОГО САМОГО pinned Git об'єкта, не з HEAD/main.
git -C external/sens show "${PIN}:lib/machine/profile/current-domain-x86-64.lisp" |
  grep -F 'CQO+IDIV / додатні 64-бітні цілі; рівні операнди' >/dev/null
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/cases"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-d12-idiv-fixtures "$ROOT/scripts/test-elfd12quot-fixtures.pas" >"$TMP/build1.log"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osensd12quot-elf "$ROOT/src/sensd12quot-elf.lpr" >"$TMP/build2.log"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osenschyslo "$ROOT/src/senschyslo.lpr" >"$TMP/build3.log"
timeout 30s "$TMP/bin/test-d12-idiv-fixtures" "$TMP/cases" >"$TMP/fixtures.stdout" 2>"$TMP/fixtures.stderr"
grep -Fq 'D12-IDIV-FIXTURES-OK cases=6' "$TMP/fixtures.stdout"
test ! -s "$TMP/fixtures.stderr"
PASS=0
for pair in '01:1' '02:2' '03:7' '04:31' '05:1024' '06:2047'; do
  IFS=: read -r label operand <<< "$pair"
  timeout 15s "$TMP/bin/sensd12quot-elf" --частка-D12 \
    "$TMP/cases/$label-l.sens" "$TMP/cases/$label-r.sens" \
    "$TMP/$label.elf" >"$TMP/$label.compile.out" 2>"$TMP/$label.compile.err"
  grep -Fq 'machine-cqo-idiv=1' "$TMP/$label.compile.out"
  test ! -s "$TMP/$label.compile.err"
  test -x "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  dd if="$TMP/$label.elf" of="$TMP/$label.code" bs=1 skip=120 status=none
  objdump -D -b binary -m i386:x86-64 --adjust-vma=0x78 \
    "$TMP/$label.code" >"$TMP/$label.dis"
  grep -Eq 'cqto|cqo' "$TMP/$label.dis"
  grep -Eq 'idiv.*%rcx' "$TMP/$label.dis"
  timeout 10s "$TMP/$label.elf" >"$TMP/$label.actual.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/$label.actual.sens" "$TMP/cases/$label-expected.sens"
  timeout 10s "$TMP/bin/senschyslo" --в-укр D12 \
    "$TMP/$label.actual.sens" >"$TMP/$label.projected"
  printf '1\n' >"$TMP/wanted"
  cmp "$TMP/$label.projected" "$TMP/wanted"
  if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
    test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
    printf '(частка %s %s)\n' "$operand" "$operand" >"$TMP/$label.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    cmp "$TMP/$label.oracle" "$TMP/$label.projected"
  fi
  timeout 15s "$TMP/bin/sensd12quot-elf" --частка-D12 \
    "$TMP/cases/$label-l.sens" "$TMP/cases/$label-r.sens" \
    "$TMP/$label.second.elf" >/dev/null
  cmp "$TMP/$label.second.elf" "$TMP/$label.elf"
  PASS=$((PASS+1))
done
test "$PASS" -eq 6
NEG=0
reject() {
  local name=$1; shift
  local dest="$TMP/$name.elf" status=0
  timeout 15s "$TMP/bin/sensd12quot-elf" --частка-D12 \
    "$@" "$dest" >"$TMP/negative.out" 2>"$TMP/negative.err" || status=$?
  test "$status" -eq 2
  test ! -e "$dest" && test ! -L "$dest"
  test ! -s "$TMP/negative.out"
  grep -Fq 'ELF-D12-ВІДМОВА:' "$TMP/negative.err"
  NEG=$((NEG+1))
}
reject zero "$TMP/cases/zero.sens" "$TMP/cases/zero.sens"
reject negative "$TMP/cases/negative.sens" "$TMP/cases/negative.sens"
reject unequal "$TMP/cases/01-l.sens" "$TMP/cases/unequal.sens"
reject wrong-d24 "$TMP/cases/bad24.sens" "$TMP/cases/01-r.sens"
reject wrong-d1 "$TMP/cases/bad1.sens" "$TMP/cases/01-r.sens"
reject wrong-d7 "$TMP/cases/bad7.sens" "$TMP/cases/01-r.sens"
reject corrupt "$TMP/cases/corrupt.sens" "$TMP/cases/01-r.sens"
reject empty "$TMP/cases/empty.sens" "$TMP/cases/01-r.sens"
reject missing "$TMP/cases/absent.sens" "$TMP/cases/01-r.sens"
cp "$TMP/cases/01-l.sens" "$TMP/cases/підміна.lisp"
reject lisp "$TMP/cases/підміна.lisp" "$TMP/cases/01-r.sens"
test "$NEG" -eq 10
cp "$TMP/01.elf" "$TMP/зайнятий.elf"
status=0
timeout 15s "$TMP/bin/sensd12quot-elf" --частка-D12 \
  "$TMP/cases/02-l.sens" "$TMP/cases/02-r.sens" "$TMP/зайнятий.elf" \
  >"$TMP/blocked.out" 2>"$TMP/blocked.err" || status=$?
test "$status" -eq 2 && test ! -s "$TMP/blocked.out"
cmp "$TMP/01.elf" "$TMP/зайнятий.elf"
ln -s "$TMP/missing.elf" "$TMP/symlink.elf"
status=0
timeout 15s "$TMP/bin/sensd12quot-elf" --частка-D12 \
  "$TMP/cases/03-l.sens" "$TMP/cases/03-r.sens" "$TMP/symlink.elf" \
  >"$TMP/link.out" 2>"$TMP/link.err" || status=$?
test "$status" -eq 2 && test ! -s "$TMP/link.out"
test -L "$TMP/symlink.elf" && test ! -e "$TMP/missing.elf"
timeout 15s "$TMP/bin/sensd12quot-elf" --частка-D12 \
  "$TMP/cases/04-l.sens" "$TMP/cases/04-r.sens" "$TMP/recovery.elf" >/dev/null
timeout 10s "$TMP/recovery.elf" >"$TMP/recovery.sens"
cmp "$TMP/recovery.sens" "$TMP/cases/04-expected.sens"
echo "D12-IDIV-Машинний-ГАРАЗД ELF=6 негативів=$NEG CQO=так IDIV=так oracle=${SENS_ORACLE_BIN:+pinned} recovery=так no-clobber=так T5M=точно"
