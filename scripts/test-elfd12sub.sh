#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { echo 'D12-SUB-ELF-БЛОК: потрібен Linux x86-64' >&2; exit 127; }
for tool in fpc objdump readelf timeout cmp; do command -v "$tool" >/dev/null; done
UNITS="$ROOT/build/m0.2/elfd12sub/units"; BIN="$ROOT/build/m0.2/elfd12sub/bin"
mkdir -p "$UNITS" "$BIN"
FPC_BIN=$(printenv FPC || echo fpc)
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" \
  -otest-elfd12sub "$ROOT/scripts/test-elfd12sub.pas"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" \
  -osensd12sub-elf "$ROOT/src/sensd12sub-elf.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" -FU"$UNITS" -FE"$BIN" \
  -osenschyslo "$ROOT/src/senschyslo.lpr"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
"$BIN/test-elfd12sub" "$TMP/cases" > "$TMP/vectors.tsv" 2> "$TMP/fixtures.stderr"
grep -Fq 'D12-SUB-UNIT-NEGATIVE-OK cases=3' "$TMP/fixtures.stderr"
grep -Fq '0 unfreed memory blocks' "$TMP/fixtures.stderr"
while IFS=$'\t' read -r label width left right; do
  "$BIN/sensd12sub-elf" --віднімати-D12 "$TMP/cases/$label-a.sens" \
    "$TMP/cases/$label-b.sens" "$TMP/$label.elf" > "$TMP/$label.publish"
  test -x "$TMP/$label.elf"
  "$BIN/sensd12sub-elf" --віднімати-D12 "$TMP/cases/$label-a.sens" \
    "$TMP/cases/$label-b.sens" "$TMP/$label-again.elf" >/dev/null
  cmp "$TMP/$label.elf" "$TMP/$label-again.elf"
  readelf -h "$TMP/$label.elf" > "$TMP/$label.header"
  grep -E 'Type:.*DYN' "$TMP/$label.header" >/dev/null
  dd if="$TMP/$label.elf" of="$TMP/$label.code" bs=1 skip=120 status=none
  objdump -D -b binary -m i386:x86-64 --adjust-vma=0x78 "$TMP/$label.code" > "$TMP/$label.dis"
  grep -Eiq 'sub.*%eax' "$TMP/$label.dis"
  timeout 5s "$TMP/$label.elf" > "$TMP/$label-machine.sens"
  cmp "$TMP/cases/$label-expected.sens" "$TMP/$label-machine.sens"
  "$BIN/senschyslo" --в-укр "D$width" "$TMP/$label-machine.sens" > "$TMP/$label.projection"
  if [[ -v SENS_ORACLE_BIN ]]; then
    printf '(відняти %s %s)\n' "$left" "$right" > "$TMP/$label.expression.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.expression.lisp" > "$TMP/$label.oracle" 2> "$TMP/$label.oracle.err" || {
      cat "$TMP/$label.oracle.err" >&2; echo "D12-SUB-ELF-ORACLE-FAIL: $label" >&2; exit 1;
    }
    cmp "$TMP/$label.projection" "$TMP/$label.oracle" || {
      cat "$TMP/$label.oracle.err" >&2; echo "D12-SUB-ELF-ORACLE-FAIL: $label" >&2; exit 1;
    }
  fi
done < "$TMP/vectors.tsv"
reject() {
  local name=$1; shift
  if "$BIN/sensd12sub-elf" --віднімати-D12 "$@" "$TMP/$name.elf" >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"; then
    echo "D12-SUB-ELF-ПОМИЛКА: прийнято $name" >&2; exit 1
  fi
  test ! -e "$TMP/$name.elf"; test ! -s "$TMP/$name.stdout"
  grep -Fq 'ELF-D12-ВІДНІМАННЯ-ПОМИЛКА:' "$TMP/$name.stderr"
}
reject d1 "$TMP/cases/d1.sens" "$TMP/cases/positive-b.sens"
reject d24 "$TMP/cases/bad-d24.sens" "$TMP/cases/positive-b.sens"
reject corrupt "$TMP/cases/corrupt.sens" "$TMP/cases/positive-b.sens"
reject projection "$TMP/cases/projection.lisp" "$TMP/cases/positive-b.sens"
cp "$TMP/positive.elf" "$TMP/occupied.elf"
if "$BIN/sensd12sub-elf" --віднімати-D12 "$TMP/cases/positive-a.sens" \
  "$TMP/cases/positive-b.sens" "$TMP/occupied.elf" > "$TMP/occupied.stdout" 2> "$TMP/occupied.stderr"; then
  echo 'D12-SUB-ELF-ПОМИЛКА: ціль перезаписана' >&2; exit 1
fi
cmp "$TMP/positive.elf" "$TMP/occupied.elf"; test ! -s "$TMP/occupied.stdout"
echo 'D12-SUB-ELF-OK machine=sub T5M=exact vectors=6 overflow=D12-to-D24 malformed=reject no-clobber=yes'

