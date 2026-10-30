#!/usr/bin/env bash
# G6.141 — два оригінальні Core1 DEFINE з pinned .sens у єдиному
# x86-64 PIE; FPC, 16 stdout=T5M, 11+7 негативів, SENS REPL oracle.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ЯДРО1-ДВА-БЛОК: потрібен Linux x86-64' >&2; exit 127;}
for x in git fpc timeout cmp mktemp readelf objdump grep sha256sum; do
  command -v "$x" >/dev/null || {
    echo "ЯДРО1-ДВА-БЛОК: немає $x" >&2; exit 127;}
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test -s external/sens/lib/core1.sens
grep -Fq '(визначити ядро1-додати' external/sens/lib/core1.lisp
grep -Fq '(визначити ядро1-відняти' external/sens/lib/core1.lisp
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
    for f in "$TMP"/*.log "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 70 "$f" >&2; }
    done
  fi;rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
for target in 'scripts/test-lowercore1twocalls.pas:test-lowercore1twocalls' \
              'src/senscore1twocalls.lpr:senscore1twocalls'; do
  IFS=: read -r source exe <<<"$target"
  timeout 240s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$source" >"$TMP/$exe.build.log" 2>&1 || {
      cat "$TMP/$exe.build.log" >&2; exit 1;}
done
HEAPTRC="log=$TMP/fixture.heap" timeout 90s \
 "$TMP/bin/test-lowercore1twocalls" "$ROOT" "$TMP/physical" \
 >"$TMP/fixture.log" 2>"$TMP/fixture.err" || {
   cat "$TMP/fixture.err" "$TMP/fixture.log" >&2;exit 1;}
grep -Fq 'позитивів=16 відмов=11' "$TMP/fixture.log"
test -s "$TMP/fixture.heap"
grep -Fq '0 unfreed memory blocks' "$TMP/fixture.heap"
test ! -s "$TMP/fixture.err"
MODE=--скомпілювати-два-виклики-ядра1
pass=0;oracle=0
while IFS=$'\t' read -r tag a b c wanted; do
  [[ -n "$tag" ]] || continue
  image="$TMP/$tag.elf"
  HEAPTRC="log=$TMP/$tag.heap" timeout 30s \
    "$TMP/bin/senscore1twocalls" "$MODE" \
    "$TMP/physical/$tag.a.sens" \
    "$TMP/physical/$tag.b.sens" \
    "$TMP/physical/$tag.c.sens" "$image" \
    >"$TMP/$tag.log" 2>"$TMP/$tag.err"
  test -x "$image"
  cmp "$image" "$TMP/physical/$tag.reference.elf"
  test -s "$TMP/$tag.heap"
  grep -Fq '0 unfreed memory blocks' "$TMP/$tag.heap"
  test ! -s "$TMP/$tag.err"
  readelf -h "$image" >"$TMP/$tag.header"
  grep -Eq 'Type:.*DYN' "$TMP/$tag.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$tag.header"
  tail -c +121 "$image" >"$TMP/$tag.machine"
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$tag.machine" >"$TMP/$tag.asm"
  grep -Eq 'add[[:space:]]+eax,0x[0-9a-f]+' "$TMP/$tag.asm"
  grep -Eq 'sub[[:space:]]+eax,0x[0-9a-f]+' "$TMP/$tag.asm"
  HASH="$(sha256sum "$image" | cut -d' ' -f1)"
  for round in 1 2; do
    timeout 5s "$image" >"$TMP/$tag.$round.actual.sens" 2>"$TMP/$tag.$round.err"
    test ! -s "$TMP/$tag.$round.err"
    test "$(wc -c <"$TMP/$tag.$round.actual.sens")" -eq 3
    cmp "$TMP/$tag.$round.actual.sens" "$TMP/physical/$tag.expected.sens"
    test "$(sha256sum "$image" | cut -d' ' -f1)" = "$HASH"
  done
  if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
    test -x "$SENS_ORACLE_BIN"
    test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
    printf '(відняти (додати %s %s) %s)\n' "$a" "$b" "$c" \
      >"$TMP/$tag.oracle.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$tag.oracle.lisp" \
      >"$TMP/$tag.oracle.out" 2>"$TMP/$tag.oracle.err"
    test ! -s "$TMP/$tag.oracle.err"
    printf '%s\n' "$wanted" >"$TMP/$tag.wanted"
    cmp "$TMP/$tag.wanted" "$TMP/$tag.oracle.out"
    oracle=$((oracle+1))
  fi
  pass=$((pass+1))
done <"$TMP/physical/cases.tsv"
test "$pass" -eq 16
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then test "$oracle" -eq 16; fi
reject() {
  local label="$1";shift
  local output="$TMP/rejected-$label.elf" code=0
  timeout 30s "$TMP/bin/senscore1twocalls" "$@" "$output" \
    >"$TMP/reject.out" 2>"$TMP/reject.err" || code=$?
  test "$code" -eq 2
  test ! -e "$output" && test ! -L "$output"
  test ! -s "$TMP/reject.out"
  grep -Fq 'ВІДМОВА:' "$TMP/reject.err"
}
cp "$TMP/physical/01.a.sens" "$TMP/fake.lisp"
printf '\377' >"$TMP/invalid.sens"
: >"$TMP/empty.sens"
reject projection "$MODE" "$TMP/fake.lisp" "$TMP/physical/01.b.sens" "$TMP/physical/01.c.sens"
reject corrupt "$MODE" "$TMP/invalid.sens" "$TMP/physical/01.b.sens" "$TMP/physical/01.c.sens"
reject empty "$MODE" "$TMP/empty.sens" "$TMP/physical/01.b.sens" "$TMP/physical/01.c.sens"
reject missing "$MODE" "$TMP/none.sens" "$TMP/physical/01.b.sens" "$TMP/physical/01.c.sens"
reject bad-mode --хибний "$TMP/physical/01.a.sens" "$TMP/physical/01.b.sens" "$TMP/physical/01.c.sens"
cp "$TMP/01.elf" "$TMP/occupied.elf"
code=0
timeout 30s "$TMP/bin/senscore1twocalls" "$MODE" \
 "$TMP/physical/02.a.sens" "$TMP/physical/02.b.sens" \
 "$TMP/physical/02.c.sens" "$TMP/occupied.elf" \
 >"$TMP/clobber.out" 2>"$TMP/clobber.err" || code=$?
test "$code" -eq 2 && test ! -s "$TMP/clobber.out"
cmp "$TMP/occupied.elf" "$TMP/01.elf"
ln -s "$TMP/nowhere.elf" "$TMP/dangling.elf"
code=0
timeout 30s "$TMP/bin/senscore1twocalls" "$MODE" \
 "$TMP/physical/03.a.sens" "$TMP/physical/03.b.sens" \
 "$TMP/physical/03.c.sens" "$TMP/dangling.elf" \
 >"$TMP/dangling.out" 2>"$TMP/dangling.err" || code=$?
test "$code" -eq 2 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/nowhere.elf"
timeout 30s "$TMP/bin/senscore1twocalls" "$MODE" \
 "$TMP/physical/03.a.sens" "$TMP/physical/03.b.sens" \
 "$TMP/physical/03.c.sens" "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/physical/03.expected.sens"
timeout 30s bash scripts/check-no-lcl.sh
echo "ЯДРО1-ДВА-ELF-ГОТОВО physical=$pass negatives=18 oracle=$oracle energy=NOT-MEASURED"
