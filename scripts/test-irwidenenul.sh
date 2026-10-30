#!/usr/bin/env bash
# G6.171 — physical D4 хибне?(D5 нуль? D12) -> native SETNE -> D1.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
finish() {
  local rc=$?
  if (( rc != 0 )); then
    echo "НЕНУЛЬ-ПРОВАЛ код=$rc" >&2
    for f in "$TMP"/*.err "$TMP"/*.build; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 35 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
trap 'echo "НЕНУЛЬ-ДІАГНОСТИКА: рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
for t in git fpc timeout mktemp cmp grep readelf objdump tail awk; do
  command -v "$t" >/dev/null || { echo "НЕНУЛЬ: немає $t" >&2;exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 180s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show HEAD:lib/domains/d4.lisp |
  grep -Fq '(0100 (ук хибне?)'
git -C external/sens show HEAD:lib/domains/d5.lisp |
  grep -Fq '(01000 (ук нуль?)'

MODE="${SENS_VERIFY_MODE:-full}"
ORACLE="${SENS_ORACLE_BIN:-}"
case "$MODE" in
  full)
    [[ -n "$ORACLE" && -x "$ORACLE" ]] || {
      echo "НЕНУЛЬ-БЛОК: full потребує pinned SENS CLI" >&2; exit 127;
    }
    test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
    ;;
  native-only)
    [[ -z "$ORACLE" ]] || {
      echo "НЕНУЛЬ-БЛОК: не приховувати наданий SENS oracle" >&2; exit 64;
    }
    ;;
  *) echo "НЕНУЛЬ-БЛОК: невідомий режим $MODE" >&2;exit 64 ;;
esac

mkdir -p "$TMP/bin" "$TMP/units" "$TMP/cases"
for item in 'scripts/test-irwidenenul.pas:test-irwidenenul' \
            'src/sensnenulelf.lpr:sensnenulelf'; do
  IFS=: read -r source target <<< "$item"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$target" \
    "$ROOT/$source" >"$TMP/$target.build" 2>&1 || {
      cat "$TMP/$target.build" >&2;exit 1;
    }
  test -x "$TMP/bin/$target"
done
HEAPTRC="log=$TMP/generator.heap" timeout 45s \
  "$TMP/bin/test-irwidenenul" "$TMP/cases" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fq 'positive=12 negatives=12' "$TMP/generator.out"
test ! -s "$TMP/generator.err"
test -s "$TMP/generator.heap"
grep -Fq '0 unfreed memory blocks' "$TMP/generator.heap"

PASS=0;ORACLE_COUNT=0
while IFS=$'\t' read -r label value wanted; do
  test -n "$label"
  target="$TMP/$label.elf"
  HEAPTRC="log=$TMP/$label.heap" timeout 30s "$TMP/bin/sensnenulelf" \
    --скомпілювати-ненуль "$TMP/cases/$label.sens" "$target" \
    >"$TMP/$label.compile.out" 2>"$TMP/$label.compile.err"
  test -x "$target"
  test ! -s "$TMP/$label.compile.err"
  test -s "$TMP/$label.heap"
  grep -Fq '0 unfreed memory blocks' "$TMP/$label.heap"
  readelf -h "$target" | grep -Eq 'Type:[[:space:]]+DYN'
  if readelf -l "$target" | grep -Eq 'INTERP|DYNAMIC'; then
    echo "НЕНУЛЬ: ELF містить interpreter/loader" >&2;exit 1
  fi
  tail -c +121 "$target" >"$TMP/$label.machine"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$label.machine" >"$TMP/$label.dis"
  grep -Eiq 'test[[:space:]]+eax,eax' "$TMP/$label.dis"
  grep -Eiq 'setne[[:space:]]+al' "$TMP/$label.dis"
  timeout 6s "$target" >"$TMP/$label.actual.sens" 2>"$TMP/$label.run.err"
  test ! -s "$TMP/$label.run.err"
  cmp "$TMP/cases/$label.expected.sens" "$TMP/$label.actual.sens"
  if [[ "$MODE" == full ]]; then
    printf '(хибне? (нуль? %s))\n' "$value" >"$TMP/$label.lisp"
    timeout 60s "$ORACLE" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$wanted" >"$TMP/$label.oracle.expected"
    cmp "$TMP/$label.oracle.out" "$TMP/$label.oracle.expected"
    ORACLE_COUNT=$((ORACLE_COUNT+1))
  fi
  HEAPTRC="log=$TMP/$label.again.heap" timeout 30s "$TMP/bin/sensnenulelf" \
    --скомпілювати-ненуль "$TMP/cases/$label.sens" "$TMP/$label.again.elf" \
    >"/dev/null"
  cmp "$target" "$TMP/$label.again.elf"
  PASS=$((PASS+1))
done <"$TMP/cases/cases.tsv"
test "$PASS" -eq 12
if [[ "$MODE" == full ]]; then
  test "$ORACLE_COUNT" -eq 12
else
  test "$ORACLE_COUNT" -eq 0
fi

NEG=0
reject() {
  local tag="$1";shift
  local target="$TMP/reject-$tag.elf" rc=0
  HEAPTRC="log=$TMP/$tag.reject.heap" timeout 20s "$TMP/bin/sensnenulelf" \
    --скомпілювати-ненуль "$@" "$target" \
    >"$TMP/$tag.out" 2>"$TMP/$tag.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$target" && test ! -L "$target" && test ! -s "$TMP/$tag.out"
  grep -Fq 'ВІДМОВА:' "$TMP/$tag.err"
  NEG=$((NEG+1))
}
for tag in bad-d4 bad-d5 bad-d24 bad-d1 bad-d7 bad-arity \
           bad-missing bad-nested bad-two-roots bad-d6 bad-corrupt bad-empty; do
  reject "$tag" "$TMP/cases/$tag.sens"
done
cp "$TMP/cases/01.sens" "$TMP/fake.lisp"
reject projection "$TMP/fake.lisp"
reject missing "$TMP/absent.sens"
test "$NEG" -eq 14

cp "$TMP/02.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/sensnenulelf" --скомпілювати-ненуль \
  "$TMP/cases/01.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/02.elf"
ln -s "$TMP/absent.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/sensnenulelf" --скомпілювати-ненуль \
  "$TMP/cases/03.sens" "$TMP/dangling.elf" \
  >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" && test ! -e "$TMP/absent.elf"

if [[ "$MODE" == full ]]; then
  echo "НЕНУЛЬ-ПОВНИЙ-PASS native=$PASS oracle=$ORACLE_COUNT negatives=$NEG no-clobber=2 energy=NOT-MEASURED"
else
  echo "НЕНУЛЬ-МАШИННИЙ-PASS native=$PASS oracle=NOT-CHECKED negatives=$NEG no-clobber=2 energy=NOT-MEASURED"
fi
