#!/usr/bin/env bash
# G6.112 — complete canonical D5:01011(D12,D12) → native ELF SUB.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'D5-SUB-БЛОК: потрібен Linux x86-64' >&2;exit 127;}
for x in git fpc timeout readelf objdump cmp mktemp grep; do
  command -v "$x" >/dev/null || { echo "D5-SUB-БЛОК: немає $x" >&2;exit 127;}
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
grep -Fq '(01011 (ук відняти) (укр відняти)' external/sens/lib/domains/d5.lisp
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  for f in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 40 "$f" >&2;}
  done
fi;rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
for row in 'scripts/test-irwidesub.pas:test-irwidesub' \
           'src/senswidesubelf.lpr:senswidesubelf'; do
  IFS=: read -r src exe <<<"$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$src" >"$TMP/$exe.build.log" 2>&1 || {
      cat "$TMP/$exe.build.log" >&2;exit 1; }
done
HEAPTRC="log=$TMP/fixture.heap" timeout 30s \
  "$TMP/bin/test-irwidesub" "$TMP/physical" >"$TMP/fixtures.log" 2>"$TMP/fixtures.err" || {
    cat "$TMP/fixtures.err" "$TMP/fixtures.log" >&2;exit 1; }
grep -Fq 'D5-WIDE-SUB-OK positives=12 negatives=16' "$TMP/fixtures.log"
test -s "$TMP/fixture.heap"
grep -Fq '0 unfreed memory blocks' "$TMP/fixture.heap"
MODE=--скомпілювати-віднімання-Д5
pass=0;d24=0;oracle=0
while IFS=$'\t' read -r label left right wanted width; do
  test -n "$label"
  result="$TMP/$label.elf"
  HEAPTRC="log=$TMP/$label.heap" timeout 20s \
    "$TMP/bin/senswidesubelf" "$MODE" "$TMP/physical/$label.sens" "$result" \
    >"$TMP/$label.status.log" 2>"$TMP/$label.err"
  test -x "$result"
  test -s "$TMP/$label.heap"
  grep -Fq '0 unfreed memory blocks' "$TMP/$label.heap"
  test ! -s "$TMP/$label.err"
  grep -Fq 'machine=SUB stdout=T5M' "$TMP/$label.status.log"
  cmp "$result" "$TMP/physical/$label.reference.elf"
  readelf -h "$result" >"$TMP/$label.header.log"
  grep -Eq 'Type:.*DYN' "$TMP/$label.header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header.log"
  tail -c +121 "$result" >"$TMP/machine"
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine" >"$TMP/$label.asm.log"
  grep -Eq 'sub[[:space:]]+eax,0x[0-9a-f]+' "$TMP/$label.asm.log"
  timeout 5s "$result" >"$TMP/$label.actual.sens"
  cmp "$TMP/$label.actual.sens" "$TMP/physical/$label.expected.sens"
  if [[ "$width" = 24 ]]; then
    test "$(wc -c <"$TMP/$label.actual.sens")" -eq 5
    d24=$((d24+1))
  else test "$(wc -c <"$TMP/$label.actual.sens")" -eq 3;fi
  if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
    test -x "$SENS_ORACLE_BIN"
    test "$(git -C sens-oracle rev-parse HEAD)" = 2c498b35af53c085450eac6f51b87facf7f9aa47
    printf '(відняти %s %s)\n' "$left" "$right" >"$TMP/$label.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$wanted" >"$TMP/$label.wanted"
    cmp "$TMP/$label.oracle.out" "$TMP/$label.wanted"
    oracle=$((oracle+1))
  fi
  pass=$((pass+1))
done <"$TMP/physical/cases.tsv"
test "$pass" -eq 12
test "$d24" -eq 4
reject() {
  local label="$1";shift
  local target="$TMP/rejected-$label.elf" code=0
  timeout 20s "$TMP/bin/senswidesubelf" "$@" "$target" \
    >"$TMP/negative.out" 2>"$TMP/negative.err" || code=$?
  test "$code" -eq 2
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/negative.out"
  grep -Fq 'Д5-ВІДНІМАННЯ-ELF-ВІДМОВА:' "$TMP/negative.err"
}
cp "$TMP/physical/01.sens" "$TMP/fake.lisp"
printf '\377' >"$TMP/corrupt.sens"
: >"$TMP/empty.sens"
reject text "$MODE" "$TMP/fake.lisp"
reject corrupt "$MODE" "$TMP/corrupt.sens"
reject empty "$MODE" "$TMP/empty.sens"
reject missing "$MODE" "$TMP/absent.sens"
reject invalid-mode --вигадано "$TMP/physical/01.sens"
cp "$TMP/01.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/senswidesubelf" "$MODE" \
 "$TMP/physical/02.sens" "$TMP/occupied.elf" >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/01.elf"
ln -s "$TMP/unwritten.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswidesubelf" "$MODE" \
 "$TMP/physical/03.sens" "$TMP/dangling.elf" >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" && test ! -e "$TMP/unwritten.elf"
timeout 20s "$TMP/bin/senswidesubelf" "$MODE" \
 "$TMP/physical/03.sens" "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/physical/03.expected.sens"
echo "D5-WIDE-SUB-ГАРАЗД physical=$pass D24=$d24 negatives=16 oracle=$oracle energy=NOT-MEASURED"
