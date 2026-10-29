#!/usr/bin/env bash
# G6.127 — один D5 SUB ELF з реальним D12 stdin; перевірка pinned .sens.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д5-SUB-ПОТІК-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in timeout fpc git cmp sha256sum readelf objdump python3 mktemp grep; do
  command -v "$tool" >/dev/null || {
    echo "Д5-SUB-ПОТІК-БЛОК: немає $tool" >&2; exit 127;
  }
done
./scripts/check-pin.sh
# NO-LCL firewall залишається ОБОВ’ЯЗКОВИМ. Виконуємо його після
# фізичних FPC/ELF/оракулів, щоб у незалежному upstream RED бачити
# чесні докази нашого machine vertical; RED gate НЕ вимикаємо.
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(01011 (ук відняти) (укр відняти)' \
  external/sens/lib/domains/d5.lisp
ORACLE="${SENS_ORACLE_BIN:-}"
if [[ -n "$ORACLE" ]]; then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP="$(mktemp -d)"
trap 'rc=$?; if (( rc != 0 )); then
  echo "Д5-SUB-ПОТІК-ПОМИЛКА код=$rc" >&2
  for f in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 32 "$f" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units-cli" "$TMP/units-fixtures" "$TMP/physical"
for row in \
  'src/sensd12subpotikelf.lpr sensd12subpotikelf units-cli' \
  'scripts/test-elfd12subpotik.pas test-elfd12subpotik units-fixtures'; do
  read -r source exe units <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$source" >"$TMP/$exe.build.log" 2>&1 || {
      cat "$TMP/$exe.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$exe"
done
timeout 25s "$TMP/bin/test-elfd12subpotik" "$TMP/physical" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
grep -Fq 'Д5-SUB-ПОТІК-СВІДКИ-ГОТОВО позитивів=26 D24=6 кадрів-негативів=12' \
  "$TMP/fixtures.log"
test "$(wc -l < "$TMP/physical/cases.tsv")" -eq 26
test "$(wc -l < "$TMP/physical/overflows.tsv")" -eq 6
ELF="$TMP/повторне-віднімання.elf"
MODE=--зібрати-D5-віднімання-потік
timeout 30s "$TMP/bin/sensd12subpotikelf" "$MODE" \
  "$TMP/physical/03.sens" "$ELF" \
  >"$TMP/compile.log" 2>"$TMP/compile.err"
test ! -s "$TMP/compile.err"
grep -Fq 'machine=SUB_EAX_R9D stdin=2xT5M-D12' "$TMP/compile.log"
test -x "$ELF"
readelf -h "$ELF" >"$TMP/header.log"
grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/header.log"
python3 - "$ELF" <<'PY'
from pathlib import Path
import sys
raw=Path(sys.argv[1]).read_bytes()
assert raw[:4]==b'\x7fELF' and raw[16:18]==b'\x03\x00'
code=raw[120:540]
assert code.count(b'\x44\x89\xc0\x44\x29\xc8\x3d\xff\x07\x00\x00')==1
assert b'\x44\x89\xc0\x44\x01\xc8\x3d\xff\x07\x00\x00' not in code
assert b'\x48\x83\xf8\x06\x0f\x85' in code, 'немає 6 byte exact gate'
assert b'\x3d\x00\xf8\xff\xff\x0f\x8c' in code, 'немає lower D12 guard'
print('Д5-SUB-ПОТІК-МАШИНА-ГОТОВО one-byte-SUB=так signed-D12-gates=так')
PY
dd if="$ELF" of="$TMP/code" bs=1 skip=120 count=420 status=none
objdump -D -b binary -m i386:x86-64 -M intel "$TMP/code" >"$TMP/disassembly.log"
grep -Eiq 'sub[[:space:]]+eax,r9d' "$TMP/disassembly.log"
HASH="$(sha256sum "$ELF" | cut -d' ' -f1)"
PASS=0
ORACLE_PASS=0
while IFS=$'\t' read -r label left right expected; do
  test -n "$label"
  for n in 1 2; do
    timeout 5s "$ELF" <"$TMP/physical/$label.frame" \
      >"$TMP/$label.$n.actual.sens" 2>"$TMP/$label.$n.machine.err"
    test ! -s "$TMP/$label.$n.machine.err"
    cmp "$TMP/physical/$label.expected.sens" "$TMP/$label.$n.actual.sens"
    test "$(wc -c < "$TMP/$label.$n.actual.sens")" -eq 3
    test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
  done
  cmp "$TMP/$label.1.actual.sens" "$TMP/$label.2.actual.sens"
  if [[ -n "$ORACLE" ]]; then
    timeout 60s "$ORACLE" "$TMP/physical/$label.sens" \
      >"$TMP/$label.oracle.log" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$label.expected.oracle"
    cmp "$TMP/$label.oracle.log" "$TMP/$label.expected.oracle" || {
      echo "Д5-SUB-ORACLE-НЕЗБІГ: $label $left $right expected=$expected" >&2
      exit 1
    }
    ORACLE_PASS=$((ORACLE_PASS+1))
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 26
if [[ -n "$ORACLE" ]]; then test "$ORACLE_PASS" -eq 26; fi
OVER=0
while IFS=$'\t' read -r label left right expected; do
  code=0
  timeout 5s "$ELF" <"$TMP/physical/$label.frame" \
    >"$TMP/$label.rejected.sens" 2>"$TMP/$label.rejected.err" || code=$?
  test "$code" -eq 2 && test ! -s "$TMP/$label.rejected.sens"
  grep -Fq 'ВІДМОВА' "$TMP/$label.rejected.err"
  test -s "$TMP/physical/$label.expected-d24.sens"
  OVER=$((OVER+1))
done <"$TMP/physical/overflows.tsv"
test "$OVER" -eq 6
NEG=0
for label in empty short1 short5 extra newline invalid243 badfirst badsecond \
  badthird badlast projection d1; do
  code=0
  timeout 5s "$ELF" <"$TMP/physical/$label.frame" \
    >"$TMP/$label.rejected.sens" 2>"$TMP/$label.rejected.err" || code=$?
  if [[ "$code" -ne 2 ]] || [[ -s "$TMP/$label.rejected.sens" ]]; then
    echo "Д5-SUB-ПОТІК-НЕВІДМОВА: $label rc=$code" >&2
    exit 1
  fi
  grep -Fq 'ВІДМОВА' "$TMP/$label.rejected.err"
  NEG=$((NEG+1))
done
test "$NEG" -eq 12
ANCHOR_NEG=0
for bad in wrong-d5.sens wrong-d6.sens d24-operand.sens \
  missing-arg.sens extra-arg.sens bad-t5m.sens empty.sens; do
  code=0
  timeout 20s "$TMP/bin/sensd12subpotikelf" "$MODE" \
    "$TMP/physical/$bad" "$TMP/reject-$ANCHOR_NEG.elf" \
    >"$TMP/anchor-reject.out" 2>"$TMP/anchor-reject.err" || code=$?
  test "$code" -eq 2
  test ! -e "$TMP/reject-$ANCHOR_NEG.elf"
  test ! -s "$TMP/anchor-reject.out"
  ANCHOR_NEG=$((ANCHOR_NEG+1))
done
printf '(відняти 7 3)\n' >"$TMP/projection.lisp"
code=0
timeout 20s "$TMP/bin/sensd12subpotikelf" "$MODE" \
  "$TMP/projection.lisp" "$TMP/not-canonical.elf" \
  >"$TMP/projection.out" 2>"$TMP/projection.err" || code=$?
test "$code" -eq 2 && test ! -e "$TMP/not-canonical.elf"
test "$ANCHOR_NEG" -eq 7
code=0
timeout 20s "$TMP/bin/sensd12subpotikelf" "$MODE" \
  "$TMP/physical/03.sens" "$ELF" >"$TMP/clobber.out" \
  2>"$TMP/clobber.err" || code=$?
test "$code" -eq 2 && test ! -s "$TMP/clobber.out"
test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
ln -s "$TMP/missing.elf" "$TMP/dangling.elf"
code=0
timeout 20s "$TMP/bin/sensd12subpotikelf" "$MODE" \
  "$TMP/physical/03.sens" "$TMP/dangling.elf" \
  >"$TMP/dangling.out" 2>"$TMP/dangling.err" || code=$?
test "$code" -eq 2 && test ! -e "$TMP/missing.elf"
test -L "$TMP/dangling.elf"
timeout 5s "$ELF" <"$TMP/physical/03.frame" >"$TMP/recovery.sens"
cmp "$TMP/recovery.sens" "$TMP/physical/03.expected.sens"
./scripts/check-no-lcl.sh
echo "Д5-SUB-ПОТІК-ГОТОВО native=$PASS two-runs=так d24-rejected=$OVER bad-frames=$NEG bad-anchors=$ANCHOR_NEG no-clobber=2 recovery=так pinned-oracle=$ORACLE_PASS energy=NOT-MEASURED"
