#!/usr/bin/env bash
# G6.156 — два фізичні D24-тіла → один справжній x86-64 ELF.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for c in git fpc timeout cmp readelf stat mktemp grep python3; do
  command -v "$c" >/dev/null || { echo "ПАРА-AOT-БЛОК: немає $c" >&2;exit 127; }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 180s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
ORACLE="${SENS_ORACLE_BIN:-}"
[[ -n "$ORACLE" && -x "$ORACLE" ]] || {
  echo 'ПАРА-AOT-БЛОК: немає незалежного pinned SENS REPL' >&2;exit 127;
}
TMP=$(mktemp -d)
trap 'rc=$?;echo "ПАРА-AOT-ЗБІЙ rc=$rc line=$LINENO cmd=$BASH_COMMAND" >&2' ERR
trap 'rc=$?;if ((rc!=0)); then for f in "$TMP"/*.err "$TMP"/*.log;do
 [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 20 "$f" >&2; }
 done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/u" "$TMP/b" "$TMP/cases"
for entry in 'src/sensbodyfileelf.lpr:sensbodyfileelf' \
             'scripts/test-pair-body-stdout.pas:test-pair-body-stdout' \
             'src/senschyslo.lpr:senschyslo';do
  IFS=: read -r src name <<<"$entry"
  if ! timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
      "-Fu$ROOT/src" "-FU$TMP/u" "-FE$TMP/b" "-o$name" \
      "$ROOT/$src" >"$TMP/$name.build.log" 2>&1;then
    cat "$TMP/$name.build.log" >&2;exit 1
  fi
  test -x "$TMP/b/$name"
done
HEAPTRC="log=$TMP/fixture.heap" timeout 90s \
  "$TMP/b/test-pair-body-stdout" "$ROOT" "$TMP/cases" \
  >"$TMP/manifest" 2>"$TMP/fixture.err"
test "$(wc -l <"$TMP/manifest")" -eq 7
grep -Fq 'PAIR-BODY-FIXTURES-OK cases=7' "$TMP/fixture.err"
grep -Fq '0 unfreed memory blocks' "$TMP/fixture.heap"
machine=0; independent=0; recursive=0
while IFS=$'\t' read -r tag input wanted op;do
  casebase="$TMP/cases/$tag"
  elf="$TMP/$tag.elf"
  HEAPTRC="log=$TMP/$tag.heap" timeout 40s "$TMP/b/sensbodyfileelf" \
    --пара-D24-stdout "$casebase.a.sens" "$casebase.an.sens" \
    "$casebase.b.sens" "$casebase.bn.sens" "$casebase.p.sens" \
    "$casebase.input.sens" "$elf" \
    >"$TMP/$tag.compile.out" 2>"$TMP/$tag.compile.err"
  grep -Fq 'functions=2 args=1 result=D24_T5M_STDOUT' "$TMP/$tag.compile.out"
  grep -Fq '0 unfreed memory blocks' "$TMP/$tag.heap"
  test ! -s "$TMP/$tag.compile.err"
  test "$(stat -c '%a' "$elf")" = 700
  timeout 8s readelf -h "$elf" >"$TMP/$tag.header"
  grep -Eq 'Class:[[:space:]]+ELF64' "$TMP/$tag.header"
  grep -Eq 'Type:[[:space:]]+EXEC' "$TMP/$tag.header"
  if readelf -l "$elf" | grep -Eq 'INTERP|DYNAMIC';then
    echo 'ПАРА-AOT-БЛОК: динамічний ELF' >&2;exit 1
  fi
  printf '%s\n' "$wanted" >"$TMP/$tag.expected.lisp"
  timeout 15s "$TMP/b/senschyslo" --з-укр D24 \
    "$TMP/$tag.expected.lisp" "$TMP/$tag.expected.sens"
  timeout 8s "$elf" >"$TMP/$tag.out.sens" 2>"$TMP/$tag.exec.err"
  test ! -s "$TMP/$tag.exec.err"
  test "$(wc -c <"$TMP/$tag.out.sens")" -eq 5
  cmp "$TMP/$tag.expected.sens" "$TMP/$tag.out.sens"
  if [[ "$op" == 'додати' ]];then
    printf '(додати %s 300)\n' "$input" >"$TMP/$tag.oracle.lisp"
    timeout 90s "$ORACLE" "$TMP/$tag.oracle.lisp" \
      >"$TMP/$tag.oracle.out" 2>"$TMP/$tag.oracle.err"
    test ! -s "$TMP/$tag.oracle.err"
    cmp "$TMP/$tag.expected.lisp" "$TMP/$tag.oracle.out"
    independent=$((independent+1))
  else
    recursive=$((recursive+1))
  fi
  machine=$((machine+1))
done <"$TMP/manifest"
test "$machine" -eq 7 && test "$independent" -eq 3 && test "$recursive" -eq 4

# Зворотна сумісність з уже існуючим вузьким exit(low8) ABI.
base="$TMP/cases/plus342"
timeout 35s "$TMP/b/sensbodyfileelf" --пара-D24 \
  "$base.a.sens" "$base.an.sens" "$base.b.sens" "$base.bn.sens" \
  "$base.p.sens" "$base.input.sens" "$TMP/low8.elf" \
  >"$TMP/low8.compile.out" 2>"$TMP/low8.compile.err"
grep -Fq 'functions=2 args=1 result=EXIT_LOW8' "$TMP/low8.compile.out"
rc=0
timeout 8s "$TMP/low8.elf" >"$TMP/low8.stdout" 2>"$TMP/low8.err" || rc=$?
test "$rc" -eq 86 && test ! -s "$TMP/low8.stdout" && test ! -s "$TMP/low8.err"

# Межа signed D24. Машинний результат 8388607+300 мусить відмовити.
rc=0
timeout 30s "$TMP/b/sensbodyfileelf" --пара-D24-stdout \
  "$base.a.sens" "$base.an.sens" "$base.b.sens" "$base.bn.sens" \
  "$base.p.sens" "$TMP/cases/overflow.sens" "$TMP/overflow.elf" \
  >"$TMP/overflow.compile.out" 2>"$TMP/overflow.compile.err"
timeout 8s "$TMP/overflow.elf" >"$TMP/overflow.stdout" \
  2>"$TMP/overflow.exec.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/overflow.stdout"
test ! -s "$TMP/overflow.exec.err"

negative=0
reject(){
  local label="$1";shift
  local dest="$TMP/rejected-$label.elf" rc=0
  timeout 25s "$TMP/b/sensbodyfileelf" "$@" "$dest" \
    >"$TMP/rejected-$label.out" 2>"$TMP/rejected-$label.err" || rc=$?
  test "$rc" -eq 2 && test ! -e "$dest"
  test ! -s "$TMP/rejected-$label.out"
  grep -Fq 'ТІЛО-SENS-AOT-ВІДМОВА' "$TMP/rejected-$label.err"
  negative=$((negative+1))
}
reject corrupt --пара-D24-stdout "$base.a.sens" "$base.an.sens" \
  "$TMP/cases/corrupt.sens" "$base.bn.sens" "$base.p.sens" "$base.input.sens"
reject bad-width --пара-D24-stdout "$base.a.sens" "$base.an.sens" \
  "$base.b.sens" "$base.bn.sens" "$base.p.sens" "$TMP/cases/wrong-width.sens"
reject same-function --пара-D24-stdout "$base.a.sens" "$base.an.sens" \
  "$base.b.sens" "$base.an.sens" "$base.p.sens" "$base.input.sens"
reject shadow --пара-D24-stdout "$base.a.sens" "$base.an.sens" \
  "$base.b.sens" "$base.bn.sens" "$base.an.sens" "$base.input.sens"
reject bad-body --пара-D24-stdout "$TMP/cases/bad-body.sens" "$base.an.sens" \
  "$base.b.sens" "$base.bn.sens" "$base.p.sens" "$base.input.sens"
cp "$base.a.sens" "$TMP/bad-projection.lisp"
reject projection --пара-D24-stdout "$TMP/bad-projection.lisp" "$base.an.sens" \
  "$base.b.sens" "$base.bn.sens" "$base.p.sens" "$base.input.sens"
reject missing --пара-D24-stdout "$base.a.sens" "$base.an.sens" \
  "$TMP/absent.sens" "$base.bn.sens" "$base.p.sens" "$base.input.sens"
reject arity --пара-D24-stdout "$base.a.sens" "$base.an.sens" \
  "$base.b.sens" "$base.bn.sens" "$base.p.sens"
test "$negative" -eq 8

# Жодних перезаписів чи підміни symlink — існуючий PublishNewELF64.
cp "$TMP/plus342.elf" "$TMP/occupied.elf"
rc=0
timeout 25s "$TMP/b/sensbodyfileelf" --пара-D24-stdout \
  "$base.a.sens" "$base.an.sens" "$base.b.sens" "$base.bn.sens" \
  "$base.p.sens" "$base.input.sens" "$TMP/occupied.elf" \
  >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/plus342.elf"
ln -s "$TMP/nonexistent.elf" "$TMP/dangling.elf"
rc=0
timeout 25s "$TMP/b/sensbodyfileelf" --пара-D24-stdout \
  "$base.a.sens" "$base.an.sens" "$base.b.sens" "$base.bn.sens" \
  "$base.p.sens" "$base.input.sens" "$TMP/dangling.elf" \
  >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/nonexistent.elf" && test ! -s "$TMP/dangling.out"
echo "PAIR-BODY-AOT-OK native=7 oracle=3 recursive-direct=4 full-D24=5-bytes overflow=exit2 low8=86 negative=8 no-clobber=2 energy=NOT-MEASURED"
