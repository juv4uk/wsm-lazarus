#!/usr/bin/env bash
# G6.120: один native x86-64 ELF64/PIE; 14 різних runtime D12 фізичних пар.
# Позитивна семантика перевіряється незалежним pinned SENS oracle.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д6-ПОТІК-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in timeout fpc git readelf objdump cmp sha256sum python3 mktemp; do
  command -v "$tool" >/dev/null || {
    echo "Д6-ПОТІК-БЛОК: немає $tool" >&2; exit 127;
  }
done
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(010100 (ук остача) (укр остача)' \
  external/sens/lib/domains/d6.lisp
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP="$(mktemp -d)"
trap 'rc=$?; if (( rc != 0 )); then
  echo "Д6-ПОТІК-ПОМИЛКА code=$rc" >&2
  for f in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 40 "$f" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units-cli" "$TMP/units-rest" \
  "$TMP/units-anchor" "$TMP/frames" "$TMP/anchor"
for item in \
  'src/sensd12restpotikelf.lpr sensd12restpotikelf units-cli' \
  'scripts/test-elfd12restpotik.pas test-elfd12restpotik units-rest' \
  'scripts/test-irwiderest.pas test-irwiderest units-anchor'; do
  read -r source executable units <<<"$item"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" \
    "-o$executable" "$ROOT/$source" \
    >"$TMP/$executable.build.log" 2>&1 || {
      cat "$TMP/$executable.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$executable"
done
timeout 20s "$TMP/bin/test-irwiderest" "$TMP/anchor" \
  >"$TMP/anchor.log" 2>"$TMP/anchor.err"
timeout 20s "$TMP/bin/test-elfd12restpotik" "$TMP/frames" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
grep -Fq 'Д6-ОСТАЧА-ПОТІК-СВІДКИ-ГОТОВО позитивів=14 негативів=20' \
  "$TMP/fixtures.log"
test "$(wc -l < "$TMP/frames/cases.tsv")" -eq 14
ELF="$TMP/повторна-остача.elf"
MODE=--зібрати-D6-остача-потік
timeout 30s "$TMP/bin/sensd12restpotikelf" "$MODE" \
  "$TMP/anchor/04.sens" "$ELF" \
  >"$TMP/compilation.log" 2>"$TMP/compilation.err"
test ! -s "$TMP/compilation.err"
grep -Fq 'machine=CDQ_IDIV_ECX stdin=2xT5M-D12' "$TMP/compilation.log"
test -x "$ELF"
readelf -h "$ELF" >"$TMP/header.log"
grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/header.log"
python3 - "$ELF" <<'PY'
from pathlib import Path
import sys
data=Path(sys.argv[1]).read_bytes()
assert data[:4]==b'\x7fELF'
assert data[16:18]==b'\x03\x00'
assert data.count(b'\x44\x89\xc0\x99\x90\x90\x44\x89\xc9\x85\xc9\x0f\x8e')==1, "machine 32-byte replacement not unique"
assert b'\x85\xc0\x0f\x88' in data, "A<0 branch absent"
assert b'\xf7\xf9\x90\x89\xd0' in data, "idiv ecx/mov eax,edx absent"
assert b'\x48\x83\xf8\x06\x0f\x85' in data, "stdin six-byte frame gate absent"
print('Д6-ПОТІК-МАШИНА-ГОТОВО CDQ_IDIV_ECX=yes bounded=one-frame exact=6')
PY
dd if="$ELF" of="$TMP/code.bin" bs=1 skip=120 count=415 status=none
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code.bin" >"$TMP/disassembly.log"
grep -Eiq 'idiv[[:space:]]+ecx' "$TMP/disassembly.log"
grep -Eiq 'jle[[:space:]]' "$TMP/disassembly.log"
grep -Eiq 'js[[:space:]]' "$TMP/disassembly.log"
HASH="$(sha256sum "$ELF" | cut -d' ' -f1)"
PASS=0
while IFS=$'\t' read -r label a b; do
  test -n "$label"
  for round in 1 2; do
    timeout 5s "$ELF" <"$TMP/frames/$label.frame" \
      >"$TMP/$label.$round.sens" 2>"$TMP/$label.$round.err"
    test ! -s "$TMP/$label.$round.err"
    cmp "$TMP/frames/$label.expected.sens" "$TMP/$label.$round.sens"
    test "$(wc -c < "$TMP/$label.$round.sens")" -eq 3
    test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
  done
  cmp "$TMP/$label.1.sens" "$TMP/$label.2.sens"
  if [[ -n "$ORACLE" ]]; then
    printf '(остача %s %s)\n' "$a" "$b" >"$TMP/$label.lisp"
    timeout 60s "$ORACLE" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$((a%b))" >"$TMP/$label.expected.oracle"
    cmp "$TMP/$label.expected.oracle" "$TMP/$label.oracle"
  fi
  PASS=$((PASS+1))
done <"$TMP/frames/cases.tsv"
test "$PASS" -eq 14
NEG=0
for label in zero-divisor both-zero negative-left negative-right \
  both-negative min-left min-right negative-minus-one \
  empty short1 short5 extra newline invalid243 badfirst badsecond \
  badthird badlast projection d1; do
  code=0
  timeout 5s "$ELF" <"$TMP/frames/$label.frame" \
    >"$TMP/rejected-$label.sens" 2>"$TMP/rejected-$label.err" || code=$?
  if [[ "$code" -ne 2 ]] || [[ -s "$TMP/rejected-$label.sens" ]] || \
      ! grep -Fq 'ВІДМОВА' "$TMP/rejected-$label.err"; then
    echo "Д6-ПОТІК НЕ ВІДХИЛИВ $label rc=$code" >&2; exit 1
  fi
  NEG=$((NEG+1))
done
test "$NEG" -eq 20
# Invalid physical full-expression anchor, zero divisor and bad projection.
for anchor in div-zero.sens bad-t5m.sens min-left.sens; do
  code=0
  timeout 20s "$TMP/bin/sensd12restpotikelf" "$MODE" \
    "$TMP/anchor/$anchor" "$TMP/reject-$anchor.elf" \
    >"$TMP/reject-$anchor.out" 2>"$TMP/reject-$anchor.err" || code=$?
  test "$code" -eq 2
  test ! -e "$TMP/reject-$anchor.elf"
  test ! -s "$TMP/reject-$anchor.out"
done
printf '(остача 7 3)\n' >"$TMP/projection.lisp"
code=0
timeout 20s "$TMP/bin/sensd12restpotikelf" "$MODE" \
  "$TMP/projection.lisp" "$TMP/no-lisp.elf" >/dev/null \
  2>"$TMP/projection.err" || code=$?
test "$code" -eq 2 && test ! -e "$TMP/no-lisp.elf"
code=0
timeout 20s "$TMP/bin/sensd12restpotikelf" "$MODE" \
  "$TMP/anchor/04.sens" "$ELF" >"$TMP/clobber.out" \
  2>"$TMP/clobber.err" || code=$?
test "$code" -eq 2 && test ! -s "$TMP/clobber.out"
test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
ln -s "$TMP/nonexistent.elf" "$TMP/dangling.elf"
code=0
timeout 20s "$TMP/bin/sensd12restpotikelf" "$MODE" \
  "$TMP/anchor/04.sens" "$TMP/dangling.elf" \
  >"$TMP/dangling.out" 2>"$TMP/dangling.err" || code=$?
test "$code" -eq 2 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/nonexistent.elf"
timeout 5s "$ELF" <"$TMP/frames/04.frame" \
  >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/frames/04.expected.sens"
echo "Д6-ОСТАЧА-ПОТІК-ГОТОВО host-profile=positive-D12 native=$PASS two-runs-each=так negatives=$NEG pinned-oracle=when-provided no-clobber=2 recovery=так energy=NOT-MEASURED"
