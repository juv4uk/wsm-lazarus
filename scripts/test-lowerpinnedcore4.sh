#!/usr/bin/env bash
# G6.130: машинна компіляція НЕ переписаного pinned Core4 тіла.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TEMP=$(mktemp -d)
trap 'rc=$?; echo "PINNED-CORE4-НАТИВ-ЗБІЙ status=$rc line=$LINENO" >&2' ERR
trap 'rm -rf "$TEMP"' EXIT
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]]
for tool in fpc git timeout readelf objdump cmp grep python3 mktemp; do
 command -v "$tool" >/dev/null || exit 127
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
mkdir -p "$TEMP/bin" "$TEMP/units" "$TEMP/cases"
FPC_BIN=${FPC:-fpc}
for entry in 'src/senscore4natyv.lpr senscore4natyv' \
             'scripts/test-lowerpinnedcore4.pas test-lowerpinnedcore4'; do
 read -r path exe <<<"$entry"
 if ! timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
   -Fu"$ROOT/src" -FU"$TEMP/units" -FE"$TEMP/bin" "-o$exe" \
   "$ROOT/$path" >"$TEMP/$exe.build.out" 2>"$TEMP/$exe.build.err"; then
    cat "$TEMP/$exe.build.out" "$TEMP/$exe.build.err" >&2;exit 1
 fi
 test -x "$TEMP/bin/$exe"
done
timeout 120s "$TEMP/bin/test-lowerpinnedcore4" "$TEMP/cases" \
 >"$TEMP/cases.tsv" 2>"$TEMP/fixtures.err"
test "$(wc -l < "$TEMP/cases.tsv")" -eq 12
test "$(find "$TEMP/cases" -name '*-arg.sens' | wc -l)" -eq 12
test "$(find "$TEMP/cases" -name '*-call.sens' | wc -l)" -eq 12

BIN="$TEMP/bin/senscore4natyv"
MODE=--скомпілювати-core4-тіло
PASS=0;ORACLE=0
while IFS=$'\t' read -r label number expected; do
 source="$TEMP/cases/$label-arg.sens"
 target="$TEMP/$label.elf"
 timeout 20s "$BIN" "$MODE" "$source" "$target" \
   >"$TEMP/$label.compiler.out" 2>"$TEMP/$label.compiler.err"
 grep -Fq 'CORE4-ТІЛО-ELF-ГОТОВО:' "$TEMP/$label.compiler.out"
 test -x "$target"
 readelf -h "$target" >"$TEMP/$label.header"
 grep -Eq 'Type:.*EXEC' "$TEMP/$label.header"
 grep -Fq 'Advanced Micro Devices X86-64' "$TEMP/$label.header"
 objdump -d -M intel "$target" >"$TEMP/$label.asm"
 grep -Eiq 'call[[:space:]]' "$TEMP/$label.asm"
 grep -Eiq 'ret' "$TEMP/$label.asm"
 grep -Eiq 'mov[[:space:]]+eax,edi' "$TEMP/$label.asm"
 set +e; timeout 10s "$target" >"$TEMP/$label.actual.stdout" \
   2>"$TEMP/$label.actual.stderr"; rc=$?; set -e
 test "$rc" -eq "$expected"
 test ! -s "$TEMP/$label.actual.stdout"
 test ! -s "$TEMP/$label.actual.stderr"
 timeout 20s "$BIN" "$MODE" "$source" "$TEMP/$label.again.elf" \
   >"$TEMP/$label.again.out" 2>"$TEMP/$label.again.err"
 cmp "$target" "$TEMP/$label.again.elf"
 if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
   timeout 40s "$SENS_ORACLE_BIN" "$TEMP/cases/$label-call.sens" \
     >"$TEMP/$label.oracle.out" 2>"$TEMP/$label.oracle.err"
   test ! -s "$TEMP/$label.oracle.err"
   python3 - "$TEMP/$label.oracle.out" "$number" <<'PY'
from pathlib import Path
import sys
t=Path(sys.argv[1]).read_text(encoding="utf-8").strip()
if t.startswith("sens[укр]> "): t=t[len("sens[укр]> "):].strip()
assert t==sys.argv[2],f"pinned SENS result {t!r} != {sys.argv[2]}"
PY
   ORACLE=$((ORACLE+1))
 fi
 PASS=$((PASS+1))
done <"$TEMP/cases.tsv"
test "$PASS" -eq 12
if [[ ${REQUIRE_SENS_ORACLE:-0} == 1 ]];then
 test -n "${SENS_ORACLE_BIN:-}" && test "$ORACLE" -eq 12
fi

reject() {
 local label=$1; shift
 local dest="$TEMP/reject-$label.elf" rc=0
 timeout 20s "$BIN" "$@" "$dest" \
   >"$TEMP/rej.out" 2>"$TEMP/rej.err" || rc=$?
 test "$rc" -eq 2
 test ! -e "$dest" && test ! -L "$dest"
 test ! -s "$TEMP/rej.out"
 grep -Fq 'CORE4-ТІЛО-ELF-ВІДМОВА:' "$TEMP/rej.err"
}
for typ in empty padding corrupt d12 d25 d1 two; do
 reject "$typ" "$MODE" "$TEMP/cases/bad-$typ.sens"
done
reject projection "$MODE" "$TEMP/cases/fake.lisp"
reject absent "$MODE" "$TEMP/cases/absent.sens"
reject wrongmode --неіснуючий "$TEMP/cases/01-arg.sens"
cp "$TEMP/01.elf" "$TEMP/occupied.elf"
rc=0
timeout 20s "$BIN" "$MODE" "$TEMP/cases/02-arg.sens" "$TEMP/occupied.elf" \
 >"$TEMP/clobber.out" 2>"$TEMP/clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TEMP/clobber.out"
cmp "$TEMP/01.elf" "$TEMP/occupied.elf"
ln -s "$TEMP/missing.elf" "$TEMP/dangling.elf"
rc=0
timeout 20s "$BIN" "$MODE" "$TEMP/cases/02-arg.sens" "$TEMP/dangling.elf" \
 >"$TEMP/symlink.out" 2>"$TEMP/symlink.err" || rc=$?
test "$rc" -eq 2 && test -L "$TEMP/dangling.elf"
test ! -e "$TEMP/missing.elf"
timeout 20s "$BIN" "$MODE" "$TEMP/cases/02-arg.sens" "$TEMP/recovery.elf" \
 >"$TEMP/recovery.out" 2>"$TEMP/recovery.err"
set +e; timeout 10s "$TEMP/recovery.elf" >/dev/null; rc=$?;set -e
test "$rc" -eq 1
echo "PINNED-CORE4-ТІЛО-ГАРАЗД library=core4.sens real-ELF=$PASS pinned-core4-runtime=$PASS pinned-sens-cli=$ORACLE відмов=10 ET_EXEC=так source-body=original D24=так energy=NOT_MEASURED"
