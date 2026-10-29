#!/usr/bin/env bash
# G6.120: канонічні D5 форми -> verified WideIR -> ALU32 -> справжній ELF64.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'Д5-РЕЄСТРИ-БЛОК: потрібен Linux x86-64' >&2; exit 127; }
for bin in fpc git timeout readelf objdump cmp mktemp grep as objcopy; do
  command -v "$bin" >/dev/null || { echo "Немає $bin" >&2; exit 127; }
done
timeout 150s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
grep -Fq '(01010 (ук додати) (укр додати)' external/sens/lib/domains/d5.lisp
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  for log in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$log" ]] || { echo "--- $log" >&2; tail -n 45 "$log" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data"
for spec in 'scripts/test-elfd12add.pas:test-elfd12add' \
            'scripts/test-irwidespilladd.pas:test-irwidespilladd' \
            'src/senswidespilladdelf.lpr:senswidespilladdelf'; do
  IFS=: read -r src name <<<"$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
     -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
     "$ROOT/$src" >"$TMP/$name.build.log" 2>&1 || {
    cat "$TMP/$name.build.log" >&2; exit 1; }
done
HEAPTRC="log=$TMP/fixtures.heap" timeout 15s \
 "$TMP/bin/test-elfd12add" "$TMP/data" >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
HEAPTRC="log=$TMP/ir.heap" timeout 30s \
 "$TMP/bin/test-irwidespilladd" "$TMP/data" >"$TMP/ir.log" 2>"$TMP/ir.err" || {
   cat "$TMP/ir.err" "$TMP/ir.log" >&2; exit 1; }
grep -Fq 'D5-SPILL-OK physical=9 tail-identical=9 negative=15 gnu-prefix=9' "$TMP/ir.log"
for h in "$TMP/fixtures.heap" "$TMP/ir.heap"; do
  test -s "$h";grep -Fq '0 unfreed memory blocks' "$h"
done
MODE=--скомпілювати-додавання-Д5-SPILL
for i in 01 02 03 04 05 06 07 08 09; do
  target="$TMP/$i.elf"
  HEAPTRC="log=$TMP/$i.heap" timeout 20s \
    "$TMP/bin/senswidespilladdelf" "$MODE" "$TMP/data/$i.sens" "$target" \
    >"$TMP/$i.out" 2>"$TMP/$i.err"
  test -x "$target"
  test -s "$TMP/$i.heap"
  grep -Fq '0 unfreed memory blocks' "$TMP/$i.heap"
  test ! -s "$TMP/$i.err"
  cmp "$target" "$TMP/data/$i.reference.elf"
  ! cmp -s "$target" "$TMP/data/$i.prior.elf"
  timeout 20s as --64 -o "$TMP/$i.prefix.o" "$TMP/data/$i.prefix.s"
  timeout 20s objcopy -O binary -j .text "$TMP/$i.prefix.o" "$TMP/$i.gnu.prefix.bin"
  cmp "$TMP/$i.gnu.prefix.bin" "$TMP/data/$i.prefix.bin"
  test "$(wc -c <"$TMP/$i.gnu.prefix.bin")" -eq 154
  readelf -h "$target" >"$TMP/$i.header.log"
  grep -Eq 'Type:.*DYN' "$TMP/$i.header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$i.header.log"
  readelf -l "$target" >"$TMP/$i.segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/$i.segments.log"
  tail -c +121 "$target" >"$TMP/machine"
  objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine" >"$TMP/$i.asm.log"
  grep -Eq 'movabs[[:space:]]+r8,' "$TMP/$i.asm.log"
  grep -Eq 'movabs[[:space:]]+r9,' "$TMP/$i.asm.log"
  grep -Eq 'movabs[[:space:]]+r15,' "$TMP/$i.asm.log"
  grep -Eq 'mov[[:space:]]+QWORD PTR \\[rsp\\],rax' "$TMP/$i.asm.log"
  grep -Eq 'mov[[:space:]]+rax,QWORD PTR \\[rsp\\]' "$TMP/$i.asm.log"
  grep -Eq 'add[[:space:]]+r8,rax' "$TMP/$i.asm.log"
  grep -Eq 'mov[[:space:]]+rax,r8' "$TMP/$i.asm.log"
  timeout 5s "$target" >"$TMP/$i.actual.sens"
  cmp "$TMP/$i.actual.sens" "$TMP/data/$i-expected.sens"
done

reject() {
  local label="$1";shift
  local target="$TMP/failed-$label.elf" rc=0
  timeout 20s "$TMP/bin/senswidespilladdelf" "$@" "$target" \
    >"$TMP/negative.out" 2>"$TMP/negative.err" || rc=$?
  test "$rc" -eq 2
  test ! -e "$target" && test ! -L "$target"
  test ! -s "$TMP/negative.out"
  grep -Fq 'Д5-SPILL-ДОДАВАННЯ-ELF-ВІДМОВА:' "$TMP/negative.err"
}
cp "$TMP/data/01.sens" "$TMP/fake.lisp"
printf '\377' >"$TMP/corrupt.sens"
: >"$TMP/empty.sens"
reject text "$MODE" "$TMP/fake.lisp"
reject corrupt "$MODE" "$TMP/corrupt.sens"
reject empty "$MODE" "$TMP/empty.sens"
reject missing "$MODE" "$TMP/no-file.sens"
reject mode --вигаданий "$TMP/data/01.sens"
cp "$TMP/01.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/senswidespilladdelf" "$MODE" \
  "$TMP/data/02.sens" "$TMP/occupied.elf" >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/01.elf"
ln -s "$TMP/nowhere.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/senswidespilladdelf" "$MODE" \
  "$TMP/data/03.sens" "$TMP/dangling.elf" >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" && test ! -e "$TMP/nowhere.elf"
timeout 20s "$TMP/bin/senswidespilladdelf" "$MODE" "$TMP/data/03.sens" \
  "$TMP/recovered.elf" >/dev/null
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/data/03-expected.sens"
echo 'Д5-SPILL-ELF-ГАРАЗД фізичних=9 машинних=9 негативів=15 публікація=атомарна енергія=НЕ-ВИМІРЯНО'
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
  oracle=0
  for row in '01:0:0:0' '02:31:42:73' '03:-12:7:-5' \
             '04:-1024:-1024:-2048' '05:-2048:2047:-1' \
             '06:1023:1:1024' '07:2047:-2048:-1' \
             '08:2046:1:2047' '09:-2047:-1:-2048'; do
    IFS=: read -r label a b wanted <<<"$row"
    printf '(додати %s %s)\n' "$a" "$b" >"$TMP/$label.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle.out" 2>"$TMP/$label.oracle.err"
    test ! -s "$TMP/$label.oracle.err"
    printf '%s\n' "$wanted" >"$TMP/$label.oracle.expected"
    cmp "$TMP/$label.oracle.out" "$TMP/$label.oracle.expected"
    oracle=$((oracle+1))
  done
  test "$oracle" -eq 9
  echo "Д5-РЕЄСТРИ-НЕЗАЛЕЖНИЙ-REPL-ГАРАЗД oracle=$oracle"
fi
