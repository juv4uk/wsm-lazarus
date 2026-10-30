#!/usr/bin/env bash
# G6.74 — compile pinned ExactIR → real ELF64 → byte-exact T5M → SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { echo "Д7-IR-БЛОК: Linux x86-64 обов’язковий" >&2; exit 127; }
for exe in fpc timeout readelf objdump cmp mktemp git; do command -v "$exe" >/dev/null || exit 127; done
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" && test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN" || { echo "Д7-IR-БЛОК: немає незалежного pinned SENS" >&2; exit 127; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/fixtures"
for spec in "scripts/test-ird7eq.pas:test-ird7eq" "src/sensird7eqelf.lpr:sensird7eqelf"; do
  IFS=: read -r src target <<< "$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$target" "$ROOT/$src" > "$TMP/$target.log" 2>&1 || { cat "$TMP/$target.log" >&2; exit 1; }
  test -x "$TMP/bin/$target"
done
timeout 120s "$TMP/bin/test-ird7eq" "$ROOT/external/sens" "$TMP/fixtures" >"$TMP/test.log" 2>"$TMP/error.log" || { cat "$TMP/test.log" "$TMP/error.log" >&2; exit 1; }
grep -Fq 'IRD7EQ-OK positives=7 negatives=12 verified-IR=1 byte-identical=1' "$TMP/test.log"
COUNT=0; ORACLE_COUNT=0
for label in син-однакові син-різні старший-однакові старший-різні нулі-однакові нулі-різні син-відновлено; do
  source="$TMP/fixtures/$label.sens"
  elf="$TMP/$label.elf"
  timeout 90s "$TMP/bin/sensird7eqelf" "$ROOT/external/sens" "$source" "$elf" > "$TMP/compile.log" 2>"$TMP/compile.error"
  test ! -s "$TMP/compile.error" && test -x "$elf"
  cmp "$elf" "$TMP/fixtures/$label.elf"
  readelf -h "$elf" > "$TMP/elf.header"
  readelf -l "$elf" > "$TMP/elf.program"
  grep -Fq 'ELF64' "$TMP/elf.header"
  grep -Eq 'Type:.*DYN' "$TMP/elf.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.header"
  grep -Fq LOAD "$TMP/elf.program"
  tail -c +121 "$elf" > "$TMP/machine"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/machine" > "$TMP/disasm"
  test "$(grep -c 'xor.*cl' "$TMP/disasm")" -eq 7
  grep -Fq sete "$TMP/disasm"
  timeout 5s "$elf" > "$TMP/actual.sens"
  cmp "$TMP/actual.sens" "$TMP/fixtures/$label.expected.sens"
  test "$(wc -c < "$TMP/actual.sens")" -eq 1
  COUNT=$((COUNT+1))
  if [[ "$label" != син-відновлено ]]; then
    timeout 90s "$ORACLE" "$source" > "$TMP/actual.txt" 2> "$TMP/oracle.err"
    test ! -s "$TMP/oracle.err"
    cmp "$TMP/actual.txt" "$TMP/fixtures/$label.expected.txt"
    ORACLE_COUNT=$((ORACLE_COUNT+1))
  fi
done
BAD="$TMP/помилковий.sens"
printf '\363' > "$BAD"
reject() {
  local output="$TMP/відхилений.elf" rc=0
  rm -f "$output"
  timeout 45s "$TMP/bin/sensird7eqelf" "$@" "$output" > "$TMP/reject.out" 2> "$TMP/reject.err" || rc=$?
  if [[ "$rc" -ne 2 || -e "$output" || -s "$TMP/reject.out" || ! -s "$TMP/reject.err" ]]; then
    echo "Д7-IR-ПРОВАЛ: помилковий вхід не відхилено атомарно rc=$rc" >&2; cat "$TMP/reject.err" >&2; exit 1
  fi
}
reject "$ROOT/external/sens" "$BAD"
: > "$TMP/порожній.sens"
reject "$ROOT/external/sens" "$TMP/порожній.sens"
cp "$TMP/fixtures/син-однакові.sens" "$TMP/не-двійковий.lisp"
reject "$ROOT/external/sens" "$TMP/не-двійковий.lisp"
reject "$TMP/немає-authority" "$TMP/fixtures/син-однакові.sens"
cp "$TMP/син-однакові.elf" "$TMP/залишити.elf"
rc=0
timeout 45s "$TMP/bin/sensird7eqelf" "$ROOT/external/sens" "$TMP/fixtures/син-однакові.sens" "$TMP/залишити.elf" > "$TMP/reject.out" 2> "$TMP/reject.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/reject.out" && test -s "$TMP/reject.err"
cmp "$TMP/залишити.elf" "$TMP/син-однакові.elf"
test "$COUNT" -eq 7 && test "$ORACLE_COUNT" -eq 6
echo 'Д7-IR-МАШИНА-ГАРАЗД ELF64=7 byte-identical=7 XOR=7/ELF pinned-SENS=6 негативи=17'
