#!/usr/bin/env bash
# G6.135 / G6.141 — два pinned Core1 D4 DEFINE/LAMBDA з двома exact D7 параметрами
# -> одна AOT спеціалізація D5:01010/01011 та 24 ELF64 PIE із T5M stdout.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ЯДРО1-АOT-БЛОК: потрібен Linux x86-64' >&2;exit 127;}
for t in git fpc timeout cmp mktemp readelf objdump grep sha256sum; do
  command -v "$t" >/dev/null || { echo "ЯДРО1-АOT-БЛОК: немає $t" >&2;exit 127;}
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
    [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 55 "$f" >&2;}
  done
fi;rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/u" "$TMP/physical"
for spec in 'scripts/test-lowerpinnedcore1add.pas:test-lowerpinnedcore1add' \
            'src/senscore1addelf.lpr:senscore1addelf'; do
  IFS=: read -r source output <<<"$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/u" -FE"$TMP/bin" "-o$output" \
    "$ROOT/$source" >"$TMP/$output.build.log" 2>&1 || {
      cat "$TMP/$output.build.log" >&2;exit 1;
    }
  test -x "$TMP/bin/$output"
done
HEAPTRC="log=$TMP/fixture.heap" timeout 90s \
 "$TMP/bin/test-lowerpinnedcore1add" "$ROOT" "$TMP/physical" \
 >"$TMP/fixture.log" 2>"$TMP/fixture.err" || {
   cat "$TMP/fixture.err" "$TMP/fixture.log" >&2;exit 1;
 }
grep -Fq 'positive=24 negative=16 D24=8' "$TMP/fixture.log"
test -s "$TMP/fixture.heap"
grep -Fq '0 unfreed memory blocks' "$TMP/fixture.heap"
test ! -s "$TMP/fixture.err"

MODE=--скомпілювати-ядро1-додавання
MODE_SUB=--скомпілювати-ядро1-віднімання
pass=0;promote=0;oracle=0
while IFS=$'\t' read -r label operation left right wanted width; do
  test -n "$label"
  case "$operation" in
    01010) mode="$MODE";ukr=додати ;;
    01011) mode="$MODE_SUB";ukr=відняти ;;
    *) echo "НЕВІДОМА точна pinned D5 голова тесту" >&2; exit 2 ;;
  esac
  compiled="$TMP/$label.elf"
  HEAPTRC="log=$TMP/$label.heap" timeout 30s \
    "$TMP/bin/senscore1addelf" "$mode" \
    "$TMP/physical/$label.left.sens" "$TMP/physical/$label.right.sens" \
    "$compiled" >"$TMP/$label.compile.log" 2>"$TMP/$label.err"
  test -s "$TMP/$label.heap"
  grep -Fq '0 unfreed memory blocks' "$TMP/$label.heap"
  test ! -s "$TMP/$label.err"
  test -x "$compiled"
  cmp "$compiled" "$TMP/physical/$label.native.elf"
  timeout 5s readelf -h "$compiled" >"$TMP/$label.header.log"
  grep -Eq 'Type:.*DYN' "$TMP/$label.header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header.log"
  tail -c +121 "$compiled" >"$TMP/machine"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine" >"$TMP/$label.asm.log"
  if [[ "$operation" = '01011' ]]; then
    grep -Eq 'sub[[:space:]]+eax,0x[0-9a-f]+' "$TMP/$label.asm.log"
  elif [[ "$width" = 24 ]]; then
    grep -Eq 'add[[:space:]]+eax,0x[0-9a-f]+' "$TMP/$label.asm.log"
  else
    grep -Eq 'add[[:space:]]+eax,ecx' "$TMP/$label.asm.log"
  fi
  hash_before="$(sha256sum "$compiled" | cut -d' ' -f1)"
  for repeat in 1 2; do
    timeout 5s "$compiled" >"$TMP/$label.$repeat.sens" \
      2>"$TMP/$label.$repeat.exec.err"
    test ! -s "$TMP/$label.$repeat.exec.err"
    cmp "$TMP/$label.$repeat.sens" "$TMP/physical/$label.expected.sens"
    test "$(sha256sum "$compiled" | cut -d' ' -f1)" = "$hash_before"
  done
  if [[ "$width" = 24 ]];then
    test "$(wc -c < "$TMP/$label.1.sens")" -eq 5
    promote=$((promote+1))
  else
    test "$width" = 12
    test "$(wc -c < "$TMP/$label.1.sens")" -eq 3
  fi
  if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
    test -x "$SENS_ORACLE_BIN"
    test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
    printf '(%s %s %s)\n' "$ukr" "$left" "$right" \
       >"$TMP/$label.oracle.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.oracle.lisp" \
       >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$wanted" >"$TMP/$label.wanted"
    cmp "$TMP/$label.wanted" "$TMP/$label.oracle.out"
    oracle=$((oracle+1))
  fi
  pass=$((pass+1))
done <"$TMP/physical/cases.tsv"
test "$pass" = 24 && test "$promote" = 8
if [[ -n "${SENS_ORACLE_BIN:-}" ]];then test "$oracle" -eq 24;fi

reject() {
  local tag="$1";shift
  local output="$TMP/rejected-$tag.elf" code=0
  timeout 30s "$TMP/bin/senscore1addelf" "$@" "$output" \
    >"$TMP/rejected.out" 2>"$TMP/rejected.err" || code=$?
  test "$code" -eq 2
  test ! -e "$output" && test ! -L "$output"
  test ! -s "$TMP/rejected.out"
  grep -Fq 'ВІДМОВА:' "$TMP/rejected.err"
}
cp "$TMP/physical/01.left.sens" "$TMP/fake.lisp"
printf '\377' >"$TMP/corrupt.sens"
: >"$TMP/empty.sens"
reject projection "$MODE" "$TMP/fake.lisp" "$TMP/physical/01.right.sens"
reject corrupt "$MODE" "$TMP/corrupt.sens" "$TMP/physical/01.right.sens"
reject empty "$MODE" "$TMP/empty.sens" "$TMP/physical/01.right.sens"
reject missing "$MODE" "$TMP/absent.sens" "$TMP/physical/01.right.sens"
reject mode --хибно "$TMP/physical/01.left.sens" "$TMP/physical/01.right.sens"
reject sub-corrupt "$MODE_SUB" "$TMP/corrupt.sens" "$TMP/physical/01.right.sens"
cp "$TMP/01.elf" "$TMP/occupied.elf"
code=0
timeout 30s "$TMP/bin/senscore1addelf" "$MODE" \
  "$TMP/physical/02.left.sens" "$TMP/physical/02.right.sens" \
  "$TMP/occupied.elf" >"$TMP/clobber.out" 2>"$TMP/clobber.err" || code=$?
test "$code" -eq 2 && test ! -s "$TMP/clobber.out"
cmp "$TMP/occupied.elf" "$TMP/01.elf"
ln -s "$TMP/missing-target.elf" "$TMP/dangling.elf"
code=0
timeout 30s "$TMP/bin/senscore1addelf" "$MODE" \
  "$TMP/physical/03.left.sens" "$TMP/physical/03.right.sens" \
  "$TMP/dangling.elf" >"$TMP/dangling.out" 2>"$TMP/dangling.err" || code=$?
test "$code" -eq 2 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/missing-target.elf"
timeout 5s "$TMP/01.elf" >"$TMP/recovery.sens"
cmp "$TMP/recovery.sens" "$TMP/physical/01.expected.sens"
timeout 30s bash scripts/check-no-lcl.sh
echo "ЯДРО1-AOT-ГОТОВО native=$pass D24=$promote negatives=16+8 oracle=$oracle energy=NOT-MEASURED"
