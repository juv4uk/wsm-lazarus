#!/usr/bin/env bash
# G6.91 — одна ПОВНА фізична D5:10110(D12:-1,D12) → WideIR → NEG.
set -Eeuo pipefail
trap 'echo "IR-Д5-ЗНАК-ВІДМОВА рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'IR-Д5-ЗНАК-БЛОК Linux x86-64' >&2; exit 127; }
for cmd in fpc readelf objdump cmp timeout git awk grep mktemp; do
  command -v "$cmd" >/dev/null || { echo "IR-Д5-ЗНАК-БЛОК немає $cmd" >&2; exit 127; }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(10110 (ук помножити) (укр помножити)' external/sens/lib/domains/d5.lisp
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/phys"
FPC_BIN=${FPC:-fpc}
for pair in \
 'scripts/test-irwidegn.pas test-irwidegn' \
 'src/senswidegnelf.lpr senswidegnelf' \
 'src/sensd12negelf.lpr sensd12negelf'; do
  read -r src name <<<"$pair"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
     -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
     "-o$name" "$ROOT/$src" >"$TMP/fpc.log" 2>&1 || {
     cat "$TMP/fpc.log" >&2; exit 1; }
done
timeout 30s "$TMP/bin/test-irwidegn" "$TMP/phys"
test -s "$TMP/phys/cases.tsv"
PASS=0
while IFS=$'\t' read -r label decimal wanted width; do
  timeout 12s "$TMP/bin/senswidegnelf" --скомпілювати-D5-знак \
    "$TMP/phys/$label.sens" "$TMP/$label.elf" \
    >"$TMP/build.stdout" 2>"$TMP/build.stderr" || {
      cat "$TMP/build.stderr" >&2; exit 1; }
  test ! -s "$TMP/build.stderr"
  grep -Fq 'machine=NEG output=T5M' "$TMP/build.stdout"
  test -x "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  timeout 5s "$TMP/$label.elf" >"$TMP/$label.result.sens"
  cmp "$TMP/phys/$label.expected.sens" "$TMP/$label.result.sens"
  if [[ "$width" == 24 ]]; then
    test "$(wc -c <"$TMP/$label.result.sens")" -eq 5
  else
    test "$(wc -c <"$TMP/$label.result.sens")" -eq 3
  fi
  # Backend однаковий біт-у-біт із вже злитим прямим D12 NEG.
  timeout 12s "$TMP/bin/sensd12negelf" --змінити-знак-D12 \
    "$TMP/phys/$label.atom.sens" "$TMP/$label.direct.elf" >"$TMP/direct.out"
  cmp "$TMP/$label.direct.elf" "$TMP/$label.elf"
  # Саме nативна machine NEG, а не обчислена таблиця відповідей.
  tail -c +121 "$TMP/$label.elf" >"$TMP/$label.instructions"
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$label.instructions" >"$TMP/$label.disasm"
  grep -Eiq 'neg[[:space:]]+eax' "$TMP/$label.disasm"
  if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
    test -x "$SENS_ORACLE_BIN"
    test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
    printf '(помножити -1 %s)\n' "$decimal" >"$TMP/$label.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err" || {
        echo "IR-Д5-ЗНАК-ORACLE-BLOCK $label" >&2
        cat "$TMP/$label.oracle.err" >&2; exit 1; }
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$wanted" >"$TMP/$label.wanted"
    cmp "$TMP/$label.wanted" "$TMP/$label.oracle"
  fi
  PASS=$((PASS+1))
done <"$TMP/phys/cases.tsv"
test "$PASS" -eq 10
# Детермінованість цілого ELF64 і заборона перезапису вже існуючого.
timeout 12s "$TMP/bin/senswidegnelf" --скомпілювати-D5-знак \
  "$TMP/phys/08.sens" "$TMP/08.again.elf" >/dev/null
cmp "$TMP/08.again.elf" "$TMP/08.elf"
NEG=0
reject() {
  local dst="$TMP/refused-$NEG.elf"
  if timeout 12s "$TMP/bin/senswidegnelf" "$@" "$dst" \
      >"$TMP/reject.out" 2>"$TMP/reject.err"; then
    echo "IR-Д5-ЗНАК-БАГ: прийнято негатив $NEG" >&2; exit 1
  fi
  test ! -e "$dst"
  test ! -s "$TMP/reject.out"
  test -s "$TMP/reject.err"
  NEG=$((NEG+1))
}
for bad in wrong-head wrong-head-domain first-zero first-one \
  first-D1 first-D24 second-D1 second-D3 second-D7 second-D24 \
  missing extra two-roots nested unclosed bare corrupt empty; do
  reject --скомпілювати-D5-знак "$TMP/phys/$bad.sens"
done
reject --скомпілювати-D5-знак "$TMP/phys/projection.lisp"
reject --скомпілювати-D5-знак "$TMP/phys/no-such-file.sens"
reject --невідоме "$TMP/phys/01.sens"
test "$NEG" -eq 21
cp "$TMP/02.elf" "$TMP/already.elf"
if timeout 12s "$TMP/bin/senswidegnelf" --скомпілювати-D5-знак \
   "$TMP/phys/08.sens" "$TMP/already.elf" \
   >"$TMP/no-clobber.out" 2>"$TMP/no-clobber.err"; then
  echo 'IR-Д5-ЗНАК-ПЕРЕЗАПИС!' >&2; exit 1
fi
cmp "$TMP/already.elf" "$TMP/02.elf"
test ! -s "$TMP/no-clobber.out"
echo "IR-Д5-ЗНАК-ГАРАЗД ELF=$PASS WideIR=так machine-NEG=так D12-D24=точно негативи=$NEG oracle=${SENS_ORACLE_BIN:+підтверджено} енергія=НЕ-ВИМІРЯНА"
