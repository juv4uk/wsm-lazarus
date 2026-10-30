#!/usr/bin/env bash
# G6.128 — true FPC + verified WideIR + native IMUL + independent SENS.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'Д6-КВАДРАТ-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for t in fpc timeout git grep cmp mktemp readelf objdump tail sha256sum; do
  command -v "$t" >/dev/null || { echo "Д6-КВАДРАТ-БЛОК: немає $t" >&2; exit 127; }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(010111 (ук піднести-до-степеня) (укр піднести-до-степеня)' external/sens/lib/domains/d6.lisp
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
grep -Fq '(визначити піднести-до-степеня' sens-oracle/lib/core4-parts/core4-d6b.lisp
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc)); then
  for f in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 55 "$f" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units-cli" "$TMP/units-test" "$TMP/physical"
for row in \
  'src/sensd6kvadratelf.lpr sensd6kvadratelf units-cli' \
  'scripts/test-d6-kvadrat.pas testd6kvadrat units-test'; do
  read -r source exe units <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/$units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$source" >"$TMP/$exe.build.log" 2>&1 || {
      cat "$TMP/$exe.build.log" >&2; exit 1;
    }
  test -x "$TMP/bin/$exe"
done
HEAPTRC="log=$TMP/test.heap" timeout 90s \
  "$TMP/bin/testd6kvadrat" "$TMP/physical" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
grep -Fq 'Д6-КВАДРАТ-СВІДКИ-ГОТОВО позитивів=12 негативів=16' "$TMP/fixtures.log"
test ! -s "$TMP/fixtures.err"
grep -Fq '0 unfreed memory blocks' "$TMP/test.heap"
test "$(wc -l < "$TMP/physical/cases.tsv")" -eq 12
MODE=--D6-010111-квадрат
MACHINE=0
ORACLE=0
while IFS=$'\t' read -r label base square; do
  test -n "$label" && test -n "$base" && test -n "$square"
  SOURCE="$TMP/physical/$label.sens"
  EXPECTED="$TMP/physical/$label.expected.sens"
  ELF="$TMP/physical/$label.elf"
  timeout 5s readelf -h "$ELF" >"$TMP/elf.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/elf.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.header"
  timeout 5s readelf -l "$ELF" >"$TMP/elf.segments"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/elf.segments"
  tail -c +121 "$ELF" >"$TMP/machine"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine" >"$TMP/disassembly"
  grep -Eiq '\bimul\b' "$TMP/disassembly"
  chmod 500 "$ELF"
  timeout 5s "$ELF" >"$TMP/$label.actual.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$TMP/$label.actual.sens" "$EXPECTED"
  HASH="$(sha256sum "$ELF" | cut -d' ' -f1)"
  OUT="$TMP/generated-$label.elf"
  timeout 20s "$TMP/bin/sensd6kvadratelf" "$MODE" "$SOURCE" "$OUT" \
    >"$TMP/compile.log" 2>"$TMP/compile.err"
  test ! -s "$TMP/compile.err"
  grep -Fq 'machine=IMUL' "$TMP/compile.log"
  cmp "$ELF" "$OUT"
  test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
  if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
    test -x "$SENS_ORACLE_BIN"
    test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
    printf '(піднести-до-степеня %s 2)\n' "$base" >"$TMP/oracle.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/oracle.lisp" \
      >"$TMP/oracle.out" 2>"$TMP/oracle.err"
    test ! -s "$TMP/oracle.err"
    printf '%s\n' "$square" >"$TMP/oracle.expected"
    cmp "$TMP/oracle.out" "$TMP/oracle.expected"
    ORACLE=$((ORACLE+1))
  fi
  MACHINE=$((MACHINE+1))
done <"$TMP/physical/cases.tsv"
test "$MACHINE" -eq 12
# Фізичний ELF та кінцеві байти не перезаписуються при повторному виклику.
code=0
timeout 15s "$TMP/bin/sensd6kvadratelf" "$MODE" \
  "$TMP/physical/01.sens" "$TMP/generated-01.elf" \
  >"$TMP/refuse.out" 2>"$TMP/refuse.err" || code=$?
test "$code" -eq 2 && test ! -s "$TMP/refuse.out"
test -s "$TMP/refuse.err"
code=0
printf '(піднести-до-степеня 3 2)\n' >"$TMP/projection.lisp"
timeout 15s "$TMP/bin/sensd6kvadratelf" "$MODE" \
  "$TMP/projection.lisp" "$TMP/reject-text.elf" \
  >"$TMP/refuse.out" 2>"$TMP/refuse.err" || code=$?
test "$code" -eq 2 && test ! -s "$TMP/refuse.out"
test ! -e "$TMP/reject-text.elf"
code=0
printf '\377' >"$TMP/corrupt.sens"
timeout 15s "$TMP/bin/sensd6kvadratelf" "$MODE" \
  "$TMP/corrupt.sens" "$TMP/reject-corrupt.elf" \
  >"$TMP/refuse.out" 2>"$TMP/refuse.err" || code=$?
test "$code" -eq 2 && test ! -s "$TMP/refuse.out"
test ! -e "$TMP/reject-corrupt.elf"
timeout 30s bash scripts/check-no-lcl.sh
echo "Д6-КВАДРАТ-МАШИНА-ГОТОВО фізичних=$MACHINE негативів=19 pinned-SENS=$ORACLE energy=NOT-MEASURED"
