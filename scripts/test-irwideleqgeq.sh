#!/usr/bin/env bash
# G6.156 — спільний WideIR → signed CMP/SETLE/SETGE → ELF64 → D1 T5M.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
finish() {
  local rc=$?
  if ((rc!=0)); then
    echo "D6-МЕЖІ-ПРОВАЛ код=$rc" >&2
    for f in "$TMP"/*.err "$TMP"/*.build; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 35 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
for t in git fpc timeout mktemp cmp grep readelf objdump tail awk;do
  command -v "$t" >/dev/null || { echo "немає $t" >&2;exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || exit 127
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 180s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
for key in '110100 (ук не-більше?)' '110110 (ук не-менше?)';do
  git -C external/sens show HEAD:lib/domains/d6.lisp | grep -Fq "$key"
done
ORACLE="${SENS_ORACLE_BIN:-}"
[[ -n "$ORACLE" && -x "$ORACLE" ]] || {
  echo "D6-МЕЖІ-БЛОК: потрібен незалежний pinned SENS REPL" >&2; exit 127;
}
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/cases"
for item in 'scripts/test-irwideleqgeq.pas:test-irwideleqgeq' \
            'src/senswidefrontelf.lpr:senswidefrontelf';do
  IFS=: read -r source target <<< "$item"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$target" \
    "$ROOT/$source" >"$TMP/$target.build" 2>&1 || {
      cat "$TMP/$target.build" >&2;exit 1;
    }
  test -x "$TMP/bin/$target"
done
HEAPTRC="log=$TMP/generator.heap" timeout 45s "$TMP/bin/test-irwideleqgeq" "$TMP/cases" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fq 'positive=16 negatives=9' "$TMP/generator.out"
test ! -s "$TMP/generator.err"
test -s "$TMP/generator.heap"
grep -Fq "0 unfreed memory blocks" "$TMP/generator.heap"
PASS=0;ORACLE_COUNT=0
while IFS=$'\t' read -r label head left right expected;do
  test -n "$label"
  case "$head" in
    110100) instruction=setle;ukr="не-більше?" ;;
    110110) instruction=setge;ukr="не-менше?" ;;
    *) echo "неочікувана D6 голова $head" >&2;exit 1 ;;
  esac
  target="$TMP/$label.elf"
  HEAPTRC="log=$TMP/$label.heap" timeout 30s "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму \
    "$TMP/cases/$label.sens" "$target" \
    >"$TMP/$label.compile.out" 2>"$TMP/$label.compile.err"
  test -x "$target"
  test ! -s "$TMP/$label.compile.err"
  test -s "$TMP/$label.heap"
  grep -Fq "0 unfreed memory blocks" "$TMP/$label.heap"
  readelf -h "$target" | grep -Eq 'Type:[[:space:]]+DYN'
  if readelf -l "$target" | grep -Eq 'INTERP|DYNAMIC';then
    echo 'ELF залежить від loader' >&2;exit 1
  fi
  tail -c +121 "$target" >"$TMP/$label.machine"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/$label.machine" >"$TMP/$label.dis"
  grep -Eiq "$instruction[[:space:]]+al" "$TMP/$label.dis"
  grep -Eiq 'cmp[[:space:]]+eax,' "$TMP/$label.dis"
  timeout 6s "$target" >"$TMP/$label.actual.sens" 2>"$TMP/$label.run.err"
  test ! -s "$TMP/$label.run.err"
  cmp "$TMP/cases/$label.expected.sens" "$TMP/$label.actual.sens"
  printf '(%s %s %s)\n' "$ukr" "$left" "$right" >"$TMP/$label.lisp"
  timeout 60s "$ORACLE" "$TMP/$label.lisp" \
    >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
  test ! -s "$TMP/$label.oracle.err"
  printf '%s\n' "$expected" >"$TMP/$label.oracle.expected"
  cmp "$TMP/$label.oracle.out" "$TMP/$label.oracle.expected"
  HEAPTRC="log=$TMP/$label.repeat.heap" timeout 30s "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму \
    "$TMP/cases/$label.sens" "$TMP/$label.repeat.elf" >"/dev/null"
  cmp "$target" "$TMP/$label.repeat.elf"
  ORACLE_COUNT=$((ORACLE_COUNT+1))
  PASS=$((PASS+1))
done <"$TMP/cases/cases.tsv"
test "$PASS" -eq 16 && test "$ORACLE_COUNT" -eq 16
NEG=0
reject() {
  local tag="$1";shift
  local target="$TMP/reject-$tag.elf" rc=0
  HEAPTRC="log=$TMP/$tag.reject.heap" timeout 20s "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму \
    "$@" "$target" >"$TMP/$tag.out" 2>"$TMP/$tag.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$target" && test ! -L "$target" && test ! -s "$TMP/$tag.out"
  grep -Fq 'ВІДМОВА:' "$TMP/$tag.err"
  NEG=$((NEG+1))
}
for tag in bad-head bad-arity bad-d24 bad-d1 bad-d7 bad-two-roots \
           bad-nested bad-corrupt bad-empty;do
  reject "$tag" "$TMP/cases/$tag.sens"
done
cp "$TMP/cases/01.sens" "$TMP/fake.lisp"
reject projection "$TMP/fake.lisp"
reject absent "$TMP/missing.sens"
test "$NEG" -eq 11
cp "$TMP/01.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму \
  "$TMP/cases/02.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/01.elf"
ln -s "$TMP/absent.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswidefrontelf" --скомпілювати-фізичну-форму \
  "$TMP/cases/03.sens" "$TMP/dangling.elf" \
  >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" && test ! -e "$TMP/absent.elf"
echo "D6-МЕЖІ-ГОТОВО signed=16 native=16 pinned-oracle=16 negatives=$NEG no-clobber=2 energy=NOT-MEASURED"
