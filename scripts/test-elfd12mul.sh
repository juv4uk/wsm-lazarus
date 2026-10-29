#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { echo 'D12-MUL-ELF-БЛОК: потрібен Linux x86-64' >&2; exit 127; }
for tool in fpc objdump readelf timeout cmp; do command -v "$tool" >/dev/null; done
UNITS="$ROOT/build/m0.2/elfd12mul/units"
BIN="$ROOT/build/m0.2/elfd12mul/bin"
mkdir -p "$UNITS" "$BIN"
FPC_BIN=$(printenv FPC || echo fpc)
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" \
  -otest-elfd12mul-fixtures "$ROOT/scripts/test-elfd12mul-fixtures.pas"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" \
  -osensd12mul-elf "$ROOT/src/sensd12mul-elf.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" \
  -osenschyslo "$ROOT/src/senschyslo.lpr"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
"$BIN/test-elfd12mul-fixtures" "$TMP/cases" > "$TMP/widths.tsv" 2> "$TMP/fixtures.stderr"
grep -Fq 'D12-MUL-UNIT-NEGATIVE-OK cases=3' "$TMP/fixtures.stderr"
grep -Fq '0 unfreed memory blocks' "$TMP/fixtures.stderr"
while IFS=$'\t' read -r label width left right; do
  "$BIN/sensd12mul-elf" --помножити-D12 "$TMP/cases/$label-a.sens" \
    "$TMP/cases/$label-b.sens" "$TMP/$label.elf"
  test -x "$TMP/$label.elf"
  "$BIN/sensd12mul-elf" --помножити-D12 "$TMP/cases/$label-a.sens" \
    "$TMP/cases/$label-b.sens" "$TMP/$label-again.elf" >/dev/null
  cmp "$TMP/$label.elf" "$TMP/$label-again.elf"
  readelf -h "$TMP/$label.elf" > "$TMP/$label.header"
  grep -E 'Type:.*DYN' "$TMP/$label.header" >/dev/null
  dd if="$TMP/$label.elf" of="$TMP/$label.code" bs=1 skip=120 status=none
  objdump -D -b binary -m i386:x86-64 --adjust-vma=0x78 "$TMP/$label.code" > "$TMP/$label.dis"
  grep -Eiq 'imul.*%eax' "$TMP/$label.dis"
  timeout 5s "$TMP/$label.elf" > "$TMP/$label-machine.sens"
  cmp "$TMP/cases/$label-expected.sens" "$TMP/$label-machine.sens"
  test "$width" = 12 -o "$width" = 24
  "$BIN/senschyslo" --в-укр "D$width" "$TMP/$label-machine.sens" > "$TMP/$label.projection"
  if [[ -v SENS_ORACLE_BIN ]]; then
    printf '(помножити %s %s)\n' "$left" "$right" > "$TMP/$label.expression.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.expression.lisp" \
      > "$TMP/$label.oracle" 2> "$TMP/$label.oracle.err"
    cmp "$TMP/$label.projection" "$TMP/$label.oracle" || {
      cat "$TMP/$label.oracle.err" >&2
      echo "D12-MUL-ELF-ORACLE-FAIL: $label" >&2; exit 1;
    }
  fi
done < "$TMP/widths.tsv"
reject() {
  local name=$1; shift
  if "$BIN/sensd12mul-elf" --помножити-D12 "$@" "$TMP/$name.elf" >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"; then
    echo "D12-MUL-ELF-ПОМИЛКА: прийнято $name" >&2; exit 1
  fi
  test ! -e "$TMP/$name.elf"; test ! -s "$TMP/$name.stdout"
  grep -Fq 'ELF-D12-МНОЖЕННЯ-ПОМИЛКА:' "$TMP/$name.stderr"
}
reject d1 "$TMP/cases/d1.sens" "$TMP/cases/boundary-b.sens"
reject d24 "$TMP/cases/bad-d24.sens" "$TMP/cases/boundary-b.sens"
reject corrupt "$TMP/cases/corrupt.sens" "$TMP/cases/boundary-b.sens"
reject projection "$TMP/cases/projection.lisp" "$TMP/cases/boundary-b.sens"
cp "$TMP/boundary.elf" "$TMP/occupied.elf"
if "$BIN/sensd12mul-elf" --помножити-D12 "$TMP/cases/boundary-a.sens" \
  "$TMP/cases/boundary-b.sens" "$TMP/occupied.elf" > "$TMP/occupied.stdout" 2> "$TMP/occupied.stderr"; then
  echo 'D12-MUL-ELF-ПОМИЛКА: ціль перезаписана' >&2; exit 1
fi
cmp "$TMP/boundary.elf" "$TMP/occupied.elf"; test ! -s "$TMP/occupied.stdout"
echo 'D12-MUL-ELF-OK machine=imul T5M=exact vectors=4 malformed=reject no-clobber=yes'
