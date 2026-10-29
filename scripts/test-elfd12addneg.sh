#!/usr/bin/env bash
# G6.83: два машинні арифметичні кроки ADD→NEG в одному ELF64.
# Незалежний pinned SENS REPL — єдиний семантичний oracle.
set -Eeuo pipefail
trap 'status=$?; echo "D12-ДВІ-ДІЇ-ПОМИЛКА код=$status рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'D12-ДВІ-ДІЇ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in python3 timeout cmp objdump readelf mktemp grep; do
  command -v "$tool" >/dev/null || {
    echo "D12-ДВІ-ДІЇ-БЛОК: немає $tool" >&2; exit 127;
  }
done
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'D12-ДВІ-ДІЇ-БЛОК: немає справжнього FPC' >&2; exit 127;
}
if [[ -v SENS_ORACLE_BIN ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = \
    1f1bf676eeac605e065035d9dd2adaae807f1788
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/свідки"
for entry in \
 'scripts/test-elfd12addneg.pas test-elfd12addneg' \
 'src/sensd12addneg-elf.lpr sensd12addneg-elf' \
 'src/senschyslo.lpr senschyslo'; do
  read -r path name <<< "$entry"
  if ! timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$path" >"$TMP/$name.build.out" 2>"$TMP/$name.build.err"; then
    cat "$TMP/$name.build.out" "$TMP/$name.build.err" >&2
    exit 1
  fi
  test -x "$TMP/bin/$name"
done
timeout 30s "$TMP/bin/test-elfd12addneg" "$TMP/свідки" \
  >"$TMP/matrix.tsv" 2>"$TMP/fixtures.err"
grep -Fq 'D12-ДВІ-ДІЇ-СВІДКИ-ГАРАЗД форм=14 проміжних-D24=4 кінцевих-D24=6' "$TMP/fixtures.err"
test "$(wc -l < "$TMP/matrix.tsv")" -eq 14
CLI="$TMP/bin/sensd12addneg-elf"
MODE=--додати-потім-змінити-знак-D12
PASS=0
WIDE=0
MIDWIDE=0
ORACLE=0
while IFS=$'\t' read -r label left right midwidth outwidth; do
  test -n "$label"
  [[ "$midwidth" == 12 || "$midwidth" == 24 ]]
  [[ "$outwidth" == 12 || "$outwidth" == 24 ]]
  timeout 15s "$CLI" "$MODE" \
    "$TMP/свідки/$label-a.sens" "$TMP/свідки/$label-b.sens" \
    "$TMP/$label.elf" >"$TMP/compiler.out" 2>"$TMP/compiler.err"
  test ! -s "$TMP/compiler.err"
  grep -Fq 'D12-ОДИН-ELF-ГОТОВО дії=ADD,NEG' "$TMP/compiler.out"
  test -x "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" >"$TMP/$label.header"
  grep -Eq 'Type:.*DYN' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  # Машинний код починається рівно MOV EAX; ADD EAX; NEG EAX,
  # а не memcpy precomputed T5M із текстового .lisp.
  python3 - "$TMP/$label.elf" <<'PY'
import pathlib, sys
image = pathlib.Path(sys.argv[1]).read_bytes()
assert image[:4] == b'\x7fELF'
assert image[120] == 0xB8 and image[125] == 0x05
assert image[130:132] == b'\xF7\xD8'
PY
  tail -c +121 "$TMP/$label.elf" >"$TMP/$label.code"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$label.code" >"$TMP/$label.dis"
  grep -Eiq 'add[[:space:]]+eax,' "$TMP/$label.dis"
  grep -Eiq 'neg[[:space:]]+eax' "$TMP/$label.dis"
  timeout 5s "$TMP/$label.elf" >"$TMP/$label.out.sens"
  cmp "$TMP/свідки/$label-expected.sens" "$TMP/$label.out.sens"
  "$TMP/bin/senschyslo" --в-укр "D$outwidth" \
    "$TMP/$label.out.sens" >"$TMP/$label.ukr"
  if [[ -v SENS_ORACLE_BIN ]]; then
    printf '(помножити -1 (додати %s %s))\n' "$left" "$right" \
      >"$TMP/$label.oracle.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.oracle.lisp" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    cmp "$TMP/$label.ukr" "$TMP/$label.oracle"
    ORACLE=$((ORACLE+1))
  fi
  if [[ "$midwidth" == 24 ]]; then MIDWIDE=$((MIDWIDE+1)); fi
  if [[ "$outwidth" == 24 ]]; then WIDE=$((WIDE+1)); fi
  PASS=$((PASS+1))
done <"$TMP/matrix.tsv"
test "$PASS" -eq 14 && test "$MIDWIDE" -eq 4 && test "$WIDE" -eq 6
if [[ -v SENS_ORACLE_BIN ]]; then test "$ORACLE" -eq 14; fi

# Повторна генерація як W12, так і W24: однакові повні ELF байти.
for label in 02 04 09; do
  timeout 15s "$CLI" "$MODE" "$TMP/свідки/$label-a.sens" \
    "$TMP/свідки/$label-b.sens" "$TMP/$label-repeated.elf" >"$TMP/status"
  cmp "$TMP/$label.elf" "$TMP/$label-repeated.elf"
done

NEG=0
reject() {
  local label=$1; shift
  local rc=0
  timeout 15s "$CLI" "$@" "$TMP/$label.elf" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -ne 0 && test "$rc" -ne 124
  test ! -e "$TMP/$label.elf" && test ! -s "$TMP/reject.out"
  grep -Fq 'D12-ОДИН-ELF-ВІДМОВА:' "$TMP/reject.err"
  NEG=$((NEG+1))
}
reject bad-d1 "$MODE" "$TMP/свідки/bad-d1.sens" "$TMP/свідки/01-b.sens"
reject bad-d7 "$MODE" "$TMP/свідки/01-a.sens" "$TMP/свідки/bad-d7.sens"
reject bad-d24 "$MODE" "$TMP/свідки/bad-d24.sens" "$TMP/свідки/01-b.sens"
reject corrupt "$MODE" "$TMP/свідки/01-a.sens" "$TMP/свідки/bad-byte.sens"
reject empty "$MODE" "$TMP/свідки/empty.sens" "$TMP/свідки/01-b.sens"
reject missing "$MODE" "$TMP/свідки/absent.sens" "$TMP/свідки/01-b.sens"
reject lisp "$MODE" "$TMP/свідки/fake.lisp" "$TMP/свідки/01-b.sens"
reject wrong-mode --невідомий "$TMP/свідки/01-a.sens" "$TMP/свідки/01-b.sens"
reject wrong-arity "$MODE" "$TMP/свідки/01-a.sens"
test "$NEG" -eq 9
cp "$TMP/01.elf" "$TMP/existing.elf"
rc=0
timeout 15s "$CLI" "$MODE" "$TMP/свідки/02-a.sens" \
  "$TMP/свідки/02-b.sens" "$TMP/existing.elf" >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
test "$rc" -ne 0 && test ! -s "$TMP/reject.out"
cmp "$TMP/01.elf" "$TMP/existing.elf"
NEG=$((NEG+1))
ln -s "$TMP/absent.elf" "$TMP/dangling.elf"
rc=0
timeout 15s "$CLI" "$MODE" "$TMP/свідки/02-a.sens" \
  "$TMP/свідки/02-b.sens" "$TMP/dangling.elf" >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
test "$rc" -ne 0 && test ! -e "$TMP/absent.elf" && test -L "$TMP/dangling.elf"
NEG=$((NEG+1))
test "$NEG" -eq 11
timeout 15s "$CLI" "$MODE" "$TMP/свідки/02-a.sens" \
  "$TMP/свідки/02-b.sens" "$TMP/recovery.elf" >"$TMP/recovery.status"
timeout 5s "$TMP/recovery.elf" >"$TMP/recovery.sens"
cmp "$TMP/recovery.sens" "$TMP/свідки/02-expected.sens"
echo "D12-ДВІ-ДІЇ-ГАРАЗД форм=$PASS проміжних-D24=$MIDWIDE фінальних-D24=$WIDE pinned-oracle=$ORACLE негативів=$NEG ELF=ADD,NEG T5M=точно RAPL=НЕ_ВИМІРЯНО"
