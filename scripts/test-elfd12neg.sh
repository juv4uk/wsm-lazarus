#!/usr/bin/env bash
# G6.76 — справжній машинний NEG D12; pinned MUL(-1,x) визначає закон.
set -Eeuo pipefail
trap 'echo "Д12-ЗНАК-ПОМИЛКА рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'Д12-ЗНАК-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for exe in timeout cmp readelf objdump mktemp grep; do
  command -v "$exe" >/dev/null || { echo "Д12-ЗНАК-БЛОК: немає $exe" >&2; exit 127; }
done
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'Д12-ЗНАК-БЛОК: потрібен реальний FPC' >&2; exit 127; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/witness"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osensd12negelf "$ROOT/src/sensd12negelf.lpr"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-elfd12neg "$ROOT/scripts/test-elfd12neg.pas"
timeout 30s "$TMP/bin/test-elfd12neg" "$TMP/witness"
CLI="$TMP/bin/sensd12negelf"
PASS=0
for label in 01 02 03 04 05 06 07 08 09 10; do
  timeout 15s "$CLI" --змінити-знак-D12 "$TMP/witness/$label-in.sens" \
    "$TMP/$label.elf" >"$TMP/status" 2>"$TMP/error" || {
      echo "Д12-ЗНАК-ПОЗИТИВ-ВІДМОВА випадок=$label" >&2
      cat "$TMP/error" >&2; exit 1;
    }
  test -x "$TMP/$label.elf"
  test ! -s "$TMP/error" || grep -Fq '0 unfreed memory blocks' "$TMP/error"
  grep -Fq 'machine-neg=1' "$TMP/status"
  readelf -h "$TMP/$label.elf" >"$TMP/header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header"
  timeout 5s "$TMP/$label.elf" >"$TMP/$label-actual.sens"
  cmp "$TMP/witness/$label-expected.sens" "$TMP/$label-actual.sens"
  PASS=$((PASS+1))
done
test "$PASS" -eq 10
# Реальні машинні байти F7 D8, а не готові літерали відповідей.
tail -c +121 "$TMP/08.elf" >"$TMP/code"
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" >"$TMP/disasm"
grep -Eiq 'neg[[:space:]]+eax' "$TMP/disasm"
# Два незалежні компіляції дають байтово той самий фізичний ELF.
timeout 15s "$CLI" --змінити-знак-D12 "$TMP/witness/08-in.sens" "$TMP/08-again.elf" >/dev/null
cmp "$TMP/08.elf" "$TMP/08-again.elf"
NEG=0
reject() {
  local out="$TMP/rejected-$NEG.elf"
  if timeout 15s "$CLI" "$@" "$out" >"$TMP/rejected.out" 2>"$TMP/rejected.err"; then
    echo 'Д12-ЗНАК-ПОМИЛКА: неприйнятне джерело створило ELF' >&2; exit 1
  fi
  test ! -e "$out"
  test ! -s "$TMP/rejected.out"
  grep -Fq 'ELF-D12-ВІДМОВА' "$TMP/rejected.err"
  NEG=$((NEG+1))
}
reject --змінити-знак-D12 "$TMP/witness/bad-d24.sens"
reject --змінити-знак-D12 "$TMP/witness/bad-d1.sens"
reject --змінити-знак-D12 "$TMP/witness/bad-d7.sens"
reject --змінити-знак-D12 "$TMP/witness/corrupt.sens"
reject --змінити-знак-D12 "$TMP/witness/empty.sens"
reject --змінити-знак-D12 "$TMP/witness/missing.sens"
cp "$TMP/witness/01-in.sens" "$TMP/fake.lisp"
reject --змінити-знак-D12 "$TMP/fake.lisp"
reject --змінити-знак-D24 "$TMP/witness/01-in.sens"
test "$NEG" -eq 8
cp "$TMP/01.elf" "$TMP/existing.elf"
if timeout 15s "$CLI" --змінити-знак-D12 "$TMP/witness/02-in.sens" \
  "$TMP/existing.elf" >"$TMP/rejected.out" 2>"$TMP/rejected.err"; then
  echo 'Д12-ЗНАК-ПОМИЛКА: перезапис створеного ELF' >&2; exit 1
fi
cmp "$TMP/existing.elf" "$TMP/01.elf"
test ! -s "$TMP/rejected.out"
NEG=$((NEG+1))
ln -s "$TMP/notpresent.elf" "$TMP/dangling.elf"
if timeout 15s "$CLI" --змінити-знак-D12 "$TMP/witness/02-in.sens" \
  "$TMP/dangling.elf" >"$TMP/rejected.out" 2>"$TMP/rejected.err"; then
  echo 'Д12-ЗНАК-ПОМИЛКА: symlink дозволив перезапис' >&2; exit 1
fi
test -L "$TMP/dangling.elf" && test ! -e "$TMP/notpresent.elf"
NEG=$((NEG+1))
test "$NEG" -eq 10
# Той самий pinned upstream REPL — незалежний семантичний оракул.
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
  PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
  ORACLE=0
  for row in '01:0:0' '02:1:-1' '03:-1:1' '04:17:-17' '05:-17:17' \
             '06:2047:-2047' '07:-2047:2047' '08:-2048:2048' \
             '09:1024:-1024' '10:-1024:1024'; do
    IFS=: read -r label value wanted <<< "$row"
    printf '(помножити -1 %s)\n' "$value" >"$TMP/$label.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.lisp" >"$TMP/oracle.out" 2>"$TMP/oracle.err" || {
      echo "Д12-ЗНАК-ОРАКУЛ-ВІДМОВА випадок=$label" >&2
      cat "$TMP/oracle.err" >&2; exit 1;
    }
    test ! -s "$TMP/oracle.err"
    printf '%s\n' "$wanted" >"$TMP/wanted"
    cmp "$TMP/wanted" "$TMP/oracle.out"
    ORACLE=$((ORACLE+1))
  done
  test "$ORACLE" -eq "$PASS"
  echo "Д12-ЗНАК-ОРАКУЛ-ГАРАЗД pinned=$PIN випадків=$ORACLE"
fi
echo "Д12-ЗНАК-ГАРАЗД машинних-ELF=$PASS негативів=$NEG D12-D24=точно енергія=НЕ_ВИМІРЯНА"
