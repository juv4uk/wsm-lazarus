#!/usr/bin/env bash
# G6.135 — checked FPC + executable x86-64 nested D3 inlining, pinned SENS.
set -euo pipefail
export LC_ALL=C.UTF-8 LANG=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'G6_135_BLOCK: Linux x86_64 required' >&2;exit 127;
}
for tool in fpc git timeout cmp readelf objdump mktemp grep stat head; do
  command -v "$tool" >/dev/null || {
    echo "G6_135_BLOCK: missing $tool" >&2; exit 127;
  }
done
test "$(git -C external/sens rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 120s bash scripts/check-pin.sh
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE"
test "$(git -C sens-oracle rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  for f in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 90 "$f" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/phys" "$TMP/compiled"
for entry in 'scripts/test-irnestedinline.pas:test-irnestedinline' \
             'src/sensd3inlineelf.lpr:sensd3inlineelf'; do
  IFS=: read -r source binary <<< "$entry"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/build-$binary.log" 2>&1 || {
      cat "$TMP/build-$binary.log" >&2;exit 1;
    }
done
HEAPTRC="log=$TMP/heap.log" timeout 60s \
  "$TMP/bin/test-irnestedinline" "$TMP/phys" \
  >"$TMP/generator.log" 2>"$TMP/generator.err" || {
    cat "$TMP/generator.log" "$TMP/generator.err" >&2;exit 1;
  }
grep -Fq 'G6_135_OK PHYSICAL=16 OPTIMIZED=16 NEGATIVE=15' "$TMP/generator.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
N=0
for source in "$TMP"/phys/d3-????.sens; do
  stem="${source%.sens}"
  bits="${stem##*/d3-}"
  [[ "$bits" =~ ^[01]{4}$ ]]
  original="$stem.baseline.elf"
  optimized="$stem.inline.elf"
  expected="$stem.expected.sens"
  cli="$TMP/compiled/d3-$bits.elf"
  test -s "$source" && test -s "$original" && test -s "$optimized" && test -s "$expected"
  timeout 12s "$TMP/bin/sensd3inlineelf" --породити-вбудовану-рівність \
    "$source" "$cli" >"$TMP/cli.log" 2>"$TMP/cli.err"
  test ! -s "$TMP/cli.err"
  grep -Fq 'INLINE=3' "$TMP/cli.log"
  test -x "$cli"
  test "$(stat -c '%a' "$cli")" = 700
  cmp "$cli" "$optimized"
  test "$(stat -c '%s' "$cli")" -eq "$(stat -c '%s' "$original")"
  timeout 5s readelf -h "$cli" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  timeout 5s readelf -l "$cli" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$cli" >"$TMP/code.bin"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/code.bin" >"$TMP/asm.log"
  ! grep -Eq '[[:space:]](call|ret)[[:space:]]' "$TMP/asm.log"
  test "$(grep -c 'sete[[:space:]]' "$TMP/asm.log")" -eq 3
  chmod 700 "$original" "$optimized"
  timeout 5s "$original" >"$TMP/baseline.sens" 2>"$TMP/native.err"
  test ! -s "$TMP/native.err"
  timeout 5s "$cli" >"$TMP/optimized.sens" 2>"$TMP/native.err"
  test ! -s "$TMP/native.err"
  cmp "$TMP/optimized.sens" "$TMP/baseline.sens"
  cmp "$TMP/optimized.sens" "$expected"
  timeout 60s "$ORACLE" "$source" >"$TMP/oracle.txt" \
    2>"$TMP/oracle.err"
  test ! -s "$TMP/oracle.err"
  left=0;right=0
  [[ "${bits:0:1}" == "${bits:1:1}" ]] && left=1
  [[ "${bits:2:1}" == "${bits:3:1}" ]] && right=1
  if ((left == right));then printf '1\n' >"$TMP/oracle-expected.txt"
  else printf '0\n' >"$TMP/oracle-expected.txt";fi
  cmp "$TMP/oracle.txt" "$TMP/oracle-expected.txt"
  N=$((N+1))
done
test "$N" -eq 16
# Existing output and dangling symlink cannot be overwritten.
reject() {
  local code="$1";shift
  local got=0
  timeout 10s "$TMP/bin/sensd3inlineelf" "$@" >"$TMP/reject.log" \
    2>"$TMP/reject.err" || got=$?
  test "$got" -eq "$code"
  grep -Fq 'ВІДМОВА' "$TMP/reject.err"
  test ! -s "$TMP/reject.log"
}
source="$TMP/phys/d3-0000.sens"
reject 2 --породити-вбудовану-рівність "$source" "$TMP/compiled/d3-0000.elf"
printf 'захищено' >"$TMP/compiled/zakhyshcheno.elf"
reject 2 --породити-вбудовану-рівність "$source" "$TMP/compiled/zakhyshcheno.elf"
test "$(cat "$TMP/compiled/zakhyshcheno.elf")" = 'захищено'
ln -s "$TMP/nonexistent" "$TMP/compiled/posylannia.elf"
reject 2 --породити-вбудовану-рівність "$source" "$TMP/compiled/posylannia.elf"
test -L "$TMP/compiled/posylannia.elf"
reject 2 --породити-вбудовану-рівність "$TMP/no-file.sens" "$TMP/compiled/nonexistent.elf"
test ! -e "$TMP/compiled/nonexistent.elf"
: >"$TMP/empty.sens"
reject 2 --породити-вбудовану-рівність "$TMP/empty.sens" "$TMP/compiled/empty.elf"
test ! -e "$TMP/compiled/empty.elf"
printf '\363' >"$TMP/malformed.sens"
reject 2 --породити-вбудовану-рівність "$TMP/malformed.sens" "$TMP/compiled/malformed.elf"
test ! -e "$TMP/compiled/malformed.elf"
reject 2 --породити-вбудовану-рівність "$source" "$TMP/nonexistent-dir/target.elf"
test ! -e "$TMP/nonexistent-dir/target.elf"
printf '(тотожне? так так)\n' >"$TMP/projection.lisp"
reject 2 --породити-вбудовану-рівність "$TMP/projection.lisp" "$TMP/compiled/projection.elf"
test ! -e "$TMP/compiled/projection.elf"
reject 2 --породити-вбудовану-рівність "$source" "$TMP/compiled/wrong-extension.txt"
test ! -e "$TMP/compiled/wrong-extension.txt"
reject 2 --wrong-flag "$source" "$TMP/compiled/flag.elf"
test ! -e "$TMP/compiled/flag.elf"
test "$(find "$TMP/compiled" -maxdepth 1 -type f -name 'sen??????' | wc -l)" -eq 0
echo 'G6_135_EXECUTABLE_OK CANONICAL=16 ORIGINAL_ELF=16 INLINE_ELF=16 PINNED_SENS=16 FPC_NEGATIVE=15 CLI_NEGATIVE=10 CALL_REMOVED_PER_RUN=3 RET_REMOVED_PER_RUN=3 ELF_BYTES_UNCHANGED=YES HEAP=ZERO ENERGY=NOT_MEASURED'
