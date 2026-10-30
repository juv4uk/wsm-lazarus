#!/usr/bin/env bash
# G6.148 — фізичний файл тіла, а не host-генерація готового fib.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for t in git fpc timeout cmp mktemp readelf objdump grep awk stat tail;do
  command -v "$t" >/dev/null || { echo "ТІЛО-AOT-БЛОК: немає $t" >&2;exit 127; }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 180s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
ORACLE=${SENS_ORACLE_BIN:-}
[[ -n "$ORACLE" && -x "$ORACLE" ]] || {
  echo 'ТІЛО-AOT-БЛОК: немає незалежного pinned SENS oracle' >&2;exit 127;
}
TMP=$(mktemp -d)
trap 'rc=$?;echo "ТІЛО-AOT-ПРОВАЛ rc=$rc line=$LINENO command=$BASH_COMMAND" >&2' ERR
trap 'rc=$?;if ((rc!=0));then
  for f in "$TMP"/*.err "$TMP"/*.log;do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 24 "$f" >&2; }
  done
fi;rm -rf "$TMP"' EXIT
mkdir -p "$TMP/b" "$TMP/u" "$TMP/cases"
for job in 'src/sensbodyfileelf.lpr:sensbodyfileelf' \
           'scripts/test-bodyfile-compiler.pas:test-bodyfile-compiler';do
  IFS=: read -r path name <<< "$job"
  if ! timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
      -Fu"$ROOT/src" -FU"$TMP/u" -FE"$TMP/b" "-o$name" \
      "$ROOT/$path" >"$TMP/$name.build.log" 2>&1;then
    cat "$TMP/$name.build.log" >&2;exit 1
  fi
  test -x "$TMP/b/$name"
done
HEAPTRC="log=$TMP/fixture.heap" timeout 90s \
  "$TMP/b/test-bodyfile-compiler" "$ROOT" "$TMP/cases" \
    >"$TMP/manifest.tsv" 2>"$TMP/fixture.err"
test "$(wc -l <"$TMP/manifest.tsv")" -eq 9
grep -Fq 'BODY-FILE-FIXTURES-OK cases=9 negatives=5' "$TMP/fixture.err"
test -s "$TMP/fixture.heap"
grep -Fq '0 unfreed memory blocks' "$TMP/fixture.heap"
tests=0; oracle=0; rec=0
while IFS=$'\t' read -r tag mode a b wanted op;do
  root="$TMP/cases/$tag"
  target="$TMP/$tag.elf"
  args=()
  case "$mode" in
    1) args=(--один-D24 "$root.body.sens" "$root.p1.sens" "$root.a1.sens");;
    A|S) args=(--два-D24 "$root.body.sens" "$root.p1.sens"
             "$root.p2.sens" "$root.a1.sens" "$root.a2.sens");;
    R) args=(--два-D24-самовиклик "$root.body.sens" "$root.p1.sens"
             "$root.p2.sens" "$root.self.sens" "$root.a1.sens" "$root.a2.sens");;
    *) echo "неочікуваний режим $mode" >&2;exit 1;;
  esac
  HEAPTRC="log=$TMP/$tag.heap" timeout 40s \
    "$TMP/b/sensbodyfileelf" "${args[@]}" "$target" \
    >"$TMP/$tag.compile.out" 2>"$TMP/$tag.compile.err"
  grep -Fq 'SENS-BODY-AOT-ELF64' "$TMP/$tag.compile.out"
  test -s "$TMP/$tag.heap"
  grep -Fq '0 unfreed memory blocks' "$TMP/$tag.heap"
  test ! -s "$TMP/$tag.compile.err"
  test -x "$target"
  test "$(stat -c '%a' "$target")" = 700
  timeout 5s readelf -h "$target" >"$TMP/$tag.header.log"
  grep -Eq 'Type:[[:space:]]+EXEC' "$TMP/$tag.header.log"
  if readelf -l "$target" | grep -Eq 'INTERP|DYNAMIC';then
    echo 'залежний від host runtime ELF' >&2;exit 1
  fi
  # Справжній код повертає тільки low8 через syscall exit, не друкує
  # SENS-свідок: це чесно ВУЗЬКИЙ ABI. Негативний код exit допустимий.
  rc=0
  timeout 8s "$target" >"$TMP/$tag.stdout" 2>"$TMP/$tag.exec.err" || rc=$?
  test ! -s "$TMP/$tag.stdout" && test ! -s "$TMP/$tag.exec.err"
  expected=$(((wanted%256+256)%256))
  if ((rc!=expected));then
    echo "помилка native ELF $tag expected=$expected actual=$rc" >&2;exit 1
  fi
  if [[ "$mode" = R ]];then
    # ET_EXEC тут не містить ELF section table; objdump -d без секцій
    # не показує інструкцій. Розбираємо рівно payload після 120-byte ELF.
    tail -c +121 "$target" >"$TMP/$tag.machine"
    timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
      "$TMP/$tag.machine" >"$TMP/$tag.dis"
    grep -Eq 'call[[:space:]]' "$TMP/$tag.dis"
    rec=$((rec+1))
  fi
  if [[ "$op" != - ]];then
    printf '(%s %s %s)\n' "$op" "$a" "$b" >"$TMP/$tag.oracle.lisp"
    timeout 60s "$ORACLE" "$TMP/$tag.oracle.lisp" \
      >"$TMP/$tag.oracle.out" 2>"$TMP/$tag.oracle.err"
    test ! -s "$TMP/$tag.oracle.err"
    printf '%s\n' "$wanted" >"$TMP/$tag.expected.decimal"
    cmp "$TMP/$tag.expected.decimal" "$TMP/$tag.oracle.out"
    oracle=$((oracle+1))
  fi
  tests=$((tests+1))
done <"$TMP/manifest.tsv"
test "$tests" -eq 9 && test "$oracle" -eq 4 && test "$rec" -eq 3

# Кожна відмова: exit 2, нуль stdout і жодного ELF, без випадкового
# aliasing exact D7/D24 або перезапису зайнятого inode.
neg=0
reject() {
  local name="$1";shift
  local output="$TMP/rejected-$name.elf" rc=0
  HEAPTRC="log=$TMP/rejected-$name.heap" timeout 30s \
    "$TMP/b/sensbodyfileelf" "$@" "$output" \
    >"$TMP/rejected-$name.out" 2>"$TMP/rejected-$name.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$output" && test ! -L "$output"
  test ! -s "$TMP/rejected-$name.out"
  grep -Fq 'AOT-' "$TMP/rejected-$name.err"
  neg=$((neg+1))
}
root="$TMP/cases/add7"
reject corrupt --два-D24 "$TMP/cases/bad-corrupt.sens" \
  "$root.p1.sens" "$root.p2.sens" "$root.a1.sens" "$root.a2.sens"
reject name-width --два-D24 "$root.body.sens" \
  "$TMP/cases/bad-name.sens" "$root.p2.sens" "$root.a1.sens" "$root.a2.sens"
reject numeric-width --два-D24 "$root.body.sens" \
  "$root.p1.sens" "$root.p2.sens" "$TMP/cases/bad-width.sens" "$root.a2.sens"
reject duplicate-keys --два-D24 "$root.body.sens" \
  "$root.p1.sens" "$root.p1.sens" "$root.a1.sens" "$root.a2.sens"
reject wrong-head --два-D24 "$TMP/cases/bad-body.sens" \
  "$root.p1.sens" "$root.p2.sens" "$root.a1.sens" "$root.a2.sens"
reject projection --два-D24 "$TMP/cases/add7.body.lisp" \
  "$root.p1.sens" "$root.p2.sens" "$root.a1.sens" "$root.a2.sens"
reject missing --два-D24 "$TMP/cases/unknown.sens" \
  "$root.p1.sens" "$root.p2.sens" "$root.a1.sens" "$root.a2.sens"
reject wrong-arity --один-D24 "$root.body.sens" "$root.p1.sens" "$root.a1.sens"
recurroot="$TMP/cases/rec5"
reject unknown-self --два-D24-самовиклик "$recurroot.body.sens" \
  "$recurroot.p1.sens" "$recurroot.p2.sens" \
  "$TMP/cases/bad-self.sens" "$recurroot.a1.sens" "$recurroot.a2.sens"
test "$neg" -eq 9

# Атомарний no-clobber: перевірити звичайний ELF і dangling symlink.
cp "$TMP/add7.elf" "$TMP/occupied.elf"
rc=0
timeout 30s "$TMP/b/sensbodyfileelf" --два-D24 "$root.body.sens" \
  "$root.p1.sens" "$root.p2.sens" "$root.a1.sens" "$root.a2.sens" \
  "$TMP/occupied.elf" >"$TMP/clobber.out" 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/clobber.out"
cmp "$TMP/occupied.elf" "$TMP/add7.elf"
ln -s "$TMP/no-inode.elf" "$TMP/dangling.elf"
rc=0
timeout 30s "$TMP/b/sensbodyfileelf" --два-D24 "$root.body.sens" \
  "$root.p1.sens" "$root.p2.sens" "$root.a1.sens" "$root.a2.sens" \
  "$TMP/dangling.elf" >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/dangling.out"
test -L "$TMP/dangling.elf" && test ! -e "$TMP/no-inode.elf"
echo "BODY-FILE-AOT-OK physical=9 native=9 independent-sens=4 recursive-direct=3 negative=9 no-clobber=2 host-ABI=exit-low8 energy=NOT-MEASURED"
