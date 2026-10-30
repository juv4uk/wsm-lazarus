#!/usr/bin/env bash
# G6.154 — машинний доказ повних 24 бітів у канонічному T5M stdout.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for c in fpc git timeout cmp readelf objdump awk grep stat mktemp;do
  command -v "$c" >/dev/null || { echo "ТІЛО-T5M-БЛОК: немає $c" >&2;exit 127; }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
timeout 150s bash scripts/check-pin.sh
timeout 150s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
ORACLE=${SENS_ORACLE_BIN:-}
[[ -x "$ORACLE" ]] || { echo "ТІЛО-T5M-БЛОК: потрібен pinned SENS CLI" >&2;exit 127; }
TMP=$(mktemp -d)
trap 'rc=$?;echo "ТІЛО-T5M-ПРОВАЛ rc=$rc line=$LINENO cmd=$BASH_COMMAND" >&2' ERR
trap 'rc=$?;if ((rc!=0));then for f in "$TMP"/*.err "$TMP"/*.log;do
 [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 17 "$f" >&2; }
 done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/u" "$TMP/b" "$TMP/cases"
for job in \
  'src/sensbodyfileelf.lpr:sensbodyfileelf' \
  'scripts/test-bodyfile-compiler.pas:test-bodyfile-compiler' \
  'src/senschyslo.lpr:senschyslo';do
  IFS=: read -r src name <<< "$job"
  if ! timeout 160s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/u" -FE"$TMP/b" "-o$name" \
    "$ROOT/$src" >"$TMP/$name.build.log" 2>&1;then
    cat "$TMP/$name.build.log" >&2;exit 1
  fi
  test -x "$TMP/b/$name"
done
HEAPTRC="log=$TMP/generator.heap" timeout 90s \
 "$TMP/b/test-bodyfile-compiler" "$ROOT" "$TMP/cases" \
 >"$TMP/manifest" 2>"$TMP/generator.err"
test "$(wc -l <"$TMP/manifest")" = 9
grep -Fq 'BODY-FILE-FIXTURES-OK cases=9 negatives=5' "$TMP/generator.err"
grep -Fq '0 unfreed memory blocks' "$TMP/generator.heap"
passed=0; oracle=0; recursion=0
while IFS=$'\t' read -r tag mode a b wanted op;do
  base="$TMP/cases/$tag"; elf="$TMP/$tag.elf"
  args=()
  case "$mode" in
    1) args=(--один-D24-stdout "$base.body.sens" "$base.p1.sens" "$base.a1.sens");;
    A|S) args=(--два-D24-stdout "$base.body.sens" "$base.p1.sens" \
             "$base.p2.sens" "$base.a1.sens" "$base.a2.sens");;
    R) args=(--два-D24-самовиклик-stdout "$base.body.sens" "$base.p1.sens" \
             "$base.p2.sens" "$base.self.sens" "$base.a1.sens" "$base.a2.sens");;
    *) echo "невідомий тест $mode" >&2;exit 1;;
  esac
  HEAPTRC="log=$TMP/$tag.heap" timeout 35s "$TMP/b/sensbodyfileelf" \
    "${args[@]}" "$elf" >"$TMP/$tag.compile.out" 2>"$TMP/$tag.compile.err"
  test ! -s "$TMP/$tag.compile.err"
  grep -Fq 'result=D24_T5M_STDOUT' "$TMP/$tag.compile.out"
  grep -Fq '0 unfreed memory blocks' "$TMP/$tag.heap"
  test "$(stat -c '%a' "$elf")" = 700
  readelf -h "$elf" >"$TMP/$tag.header"
  grep -Eq 'Type:[[:space:]]+EXEC' "$TMP/$tag.header"
  if readelf -l "$elf" | grep -Eq 'INTERP|DYNAMIC';then
    echo "неприпустимий dynamic ELF" >&2;exit 1
  fi
  printf '%s\n' "$wanted" >"$TMP/$tag.expected.lisp"
  timeout 20s "$TMP/b/senschyslo" --з-укр D24 \
    "$TMP/$tag.expected.lisp" "$TMP/$tag.expected.sens"
  timeout 10s "$elf" >"$TMP/$tag.actual.sens" 2>"$TMP/$tag.exec.err"
  test ! -s "$TMP/$tag.exec.err"
  test "$(wc -c <"$TMP/$tag.actual.sens")" = 5
  cmp "$TMP/$tag.expected.sens" "$TMP/$tag.actual.sens"
  timeout 10s "$TMP/b/senschyslo" --в-укр D24 "$TMP/$tag.actual.sens" \
    >"$TMP/$tag.decimal"
  printf '%s\n' "$wanted" >"$TMP/$tag.wanted"
  cmp "$TMP/$tag.wanted" "$TMP/$tag.decimal"
  if [[ "$mode" = R ]];then recursion=$((recursion+1));fi
  if [[ "$op" != "-" ]];then
    printf '(%s %s %s)\n' "$op" "$a" "$b" >"$TMP/$tag.oracle.lisp"
    timeout 90s "$ORACLE" "$TMP/$tag.oracle.lisp" \
      >"$TMP/$tag.oracle.out" 2>"$TMP/$tag.oracle.err"
    test ! -s "$TMP/$tag.oracle.err"
    cmp "$TMP/$tag.oracle.out" "$TMP/$tag.wanted"
    oracle=$((oracle+1))
  fi
  passed=$((passed+1))
done <"$TMP/manifest"
test "$passed" = 9 && test "$oracle" = 4 && test "$recursion" = 3

# 24-bit overflow: value +8388607+1 does not fit signed D24.
# Кодогенерація допустима, але native machine MUST fail closed.
printf '8388607\n' >"$TMP/limit.lisp"
printf '1\n' >"$TMP/one.lisp"
timeout 20s "$TMP/b/senschyslo" --з-укр D24 "$TMP/limit.lisp" "$TMP/limit.sens"
timeout 20s "$TMP/b/senschyslo" --з-укр D24 "$TMP/one.lisp" "$TMP/one.sens"
base="$TMP/cases/add7"
HEAPTRC="log=$TMP/overflow.heap" timeout 30s "$TMP/b/sensbodyfileelf" \
  --два-D24-stdout "$base.body.sens" "$base.p1.sens" "$base.p2.sens" \
  "$TMP/limit.sens" "$TMP/one.sens" "$TMP/overflow.elf" \
  >"$TMP/overflow.compiler.out" 2>"$TMP/overflow.compiler.err"
rc=0
timeout 10s "$TMP/overflow.elf" >"$TMP/overflow.stdout" \
  2>"$TMP/overflow.stderr" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/overflow.stdout" && test ! -s "$TMP/overflow.stderr"
grep -Fq '0 unfreed memory blocks' "$TMP/overflow.heap"

negative=0
reject(){
  local tag="$1"; shift
  local dest="$TMP/$tag.elf" rc=0
  HEAPTRC="log=$TMP/$tag.heap" timeout 35s "$TMP/b/sensbodyfileelf" \
    "$@" "$dest" >"$TMP/$tag.out" 2>"$TMP/$tag.err" || rc=$?
  test "$rc" -eq 2 && test ! -e "$dest" && test ! -L "$dest"
  test ! -s "$TMP/$tag.out"
  grep -Fq 'AOT-' "$TMP/$tag.err"
  negative=$((negative+1))
}
reject bad-name --два-D24-stdout "$base.body.sens" \
 "$TMP/cases/bad-name.sens" "$base.p2.sens" "$base.a1.sens" "$base.a2.sens"
reject bad-width --два-D24-stdout "$base.body.sens" \
 "$base.p1.sens" "$base.p2.sens" "$TMP/cases/bad-width.sens" "$base.a2.sens"
reject bad-body --два-D24-stdout "$TMP/cases/bad-body.sens" \
 "$base.p1.sens" "$base.p2.sens" "$base.a1.sens" "$base.a2.sens"
reject bad-corrupt --два-D24-stdout "$TMP/cases/bad-corrupt.sens" \
 "$base.p1.sens" "$base.p2.sens" "$base.a1.sens" "$base.a2.sens"
reject wrong-domain --два-D24-stdout "$base.body.sens" \
 "$base.p1.sens" "$base.p2.sens" "$base.a1.sens" "$TMP/cases/bad-width.sens"
reject no-projection --два-D24-stdout "$base.body.lisp" \
 "$base.p1.sens" "$base.p2.sens" "$base.a1.sens" "$base.a2.sens"
reject bad-arity --два-D24-stdout "$base.body.sens" \
 "$base.p1.sens" "$base.p2.sens" "$base.a1.sens"
test "$negative" -eq 7
# Повний no-clobber включно з dangling symlink.
cp "$TMP/add7.elf" "$TMP/occupied.elf"
rc=0
timeout 25s "$TMP/b/sensbodyfileelf" --два-D24-stdout \
 "$base.body.sens" "$base.p1.sens" "$base.p2.sens" "$base.a1.sens" "$base.a2.sens" \
 "$TMP/occupied.elf" >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/add7.elf" "$TMP/occupied.elf"
ln -s "$TMP/missing.elf" "$TMP/dangling.elf"
rc=0
timeout 25s "$TMP/b/sensbodyfileelf" --два-D24-stdout \
 "$base.body.sens" "$base.p1.sens" "$base.p2.sens" "$base.a1.sens" "$base.a2.sens" \
 "$TMP/dangling.elf" >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test ! -e "$TMP/missing.elf" && test -L "$TMP/dangling.elf"
test ! -s "$TMP/dangling.out"

echo "BODY-D24-T5M-OK physical=9 machine=9 oracle=4 recursive-direct=3 overflow=exit2 negative=7 no-clobber=2 bytes=5 full-domain=D24 energy=NOT-MEASURED"
