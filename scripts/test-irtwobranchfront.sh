#!/usr/bin/env bash
# G6.110 — той самий фізичний .sens → один CLI → один із трьох
# раніше перевірених exact-domain машинних профілів.
# 48 справжніх ELF64 і 48 незалежних pinned SENS oracle.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
trap 'rc=$?; echo "СПІЛЬНИЙ-ДВОГІЛКОВИЙ-ЗБІЙ status=$rc line=$LINENO" >&2' ERR
trap 'rm -rf "$TMP"' EXIT
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]]
for tool in fpc git timeout python3 grep cmp readelf objdump dd mktemp; do
  command -v "$tool" >/dev/null || exit 127
done
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show HEAD:lib/domains/d3.lisp |
 grep -F '(101 (ук тотожне?) (укр тотожне?)' >/dev/null
for word in '11010 (ук менше?)' '11011 (ук більше?)'             '01010 (ук додати)' '01011 (ук відняти)'; do
 git -C external/sens show HEAD:lib/domains/d5.lisp | grep -F "$word" >/dev/null
done
ORACLE=$(printenv SENS_ORACLE_BIN || true)
if [[ $(printenv REQUIRE_SENS_ORACLE || echo 0) == 1 ]]; then test -n "$ORACLE"; fi
if [[ -n "$ORACLE" ]]; then
 test -x "$ORACLE"
 test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/eq" "$TMP/less" "$TMP/greater"
FPC_BIN=$(printenv FPC || echo fpc)
for entry in  'src/senstwobranchfrontelf.lpr senstwobranchfrontelf'  'src/senstwobrancheqelf.lpr senstwobrancheqelf'  'src/senstwobranchlesself.lpr senstwobranchlesself'  'src/senstwobranchgreaterelf.lpr senstwobranchgreaterelf'  'scripts/test-irtwobrancheq.pas test-irtwobrancheq'  'scripts/test-irtwobranchless.pas test-irtwobranchless'  'scripts/test-irtwobranchgreater.pas test-irtwobranchgreater'; do
 read -r path exe <<<"$entry"
 if ! timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe"    "$ROOT/$path" >"$TMP/$exe.build.out" 2>"$TMP/$exe.build.err"; then
   cat "$TMP/$exe.build.out" "$TMP/$exe.build.err" >&2
   exit 1
 fi
 test -x "$TMP/bin/$exe"
done
for kind in eq less greater; do
 timeout 30s "$TMP/bin/test-irtwobranch$kind" "$TMP/$kind"    >"$TMP/$kind.tsv" 2>"$TMP/$kind.fixture.err"
 test "$(wc -l < "$TMP/$kind.tsv")" -eq 16
 test "$(find "$TMP/$kind" -name '*-program.sens' | wc -l)" -eq 16
 test "$(find "$TMP/$kind" -name 'bad-*.sens' | wc -l)" -eq 20
done

# Diagnostic-only HeapTrc; жодних проігнорованих витоків.
heap_ok() {
 local path=$1
 if grep -Fq 'unfreed memory blocks' "$path"; then
   grep -Eq '^0 unfreed memory blocks[[:space:]]*:[[:space:]]*0' "$path"
 elif grep -Fq 'Heap dump by heaptrc' "$path"; then
   echo "Неповний звіт heaptrc: $path" >&2; return 1
 fi
}
oracle_d1() {
 python3 - "$1" "$2" <<'PY'
from pathlib import Path
import sys
raw=Path(sys.argv[1]).read_text(encoding="utf-8").strip()
if raw.startswith("sens[укр]> "):
    raw=raw[len("sens[укр]> "):].strip()
valid={"0":"0","1":"1","НІ":"0","ТАК":"1","(н і)":"0","(т а к)":"1"}
assert raw in valid, f"Невідома pinned D1 проєкція: {raw!r}"
assert valid[raw]==sys.argv[2], f"pinned SENS oracle != expected {raw!r}"
PY
}
CLI="$TMP/bin/senstwobranchfrontelf"
MODE=--скомпілювати-дві-гілки
PASS=0;PINNED=0;NEG=0;T=0;F=0
for kind in eq less greater; do
 case "$kind" in
   eq) old=senstwobrancheqelf; oldmode=--скомпілювати-дві-гілки-тотожне; insn=sete ;;
   less) old=senstwobranchlesself; oldmode=--скомпілювати-дві-гілки-менше; insn=setl ;;
   greater) old=senstwobranchgreaterelf; oldmode=--скомпілювати-дві-гілки; insn=setg ;;
 esac
 while IFS=$'\t' read -r label a b c d expected; do
   source="$TMP/$kind/$label-program.sens"
   expected_file="$TMP/$kind/$label-expected.sens"
   target="$TMP/$kind-$label.elf"
   timeout 20s "$CLI" "$MODE" "$source" "$target"       >"$TMP/front.out" 2>"$TMP/front.err"
   heap_ok "$TMP/front.err"
   grep -Fq 'ДВОГІЛКОВИЙ-СПІЛЬНИЙ-ELF-ГОТОВО:' "$TMP/front.out"
   test -x "$target"
   readelf -h "$target" >"$TMP/$kind-$label.header"
   grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$kind-$label.header"
   grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$kind-$label.header"
   dd if="$target" of="$TMP/$kind-$label.code" bs=1 skip=120 count=37 status=none
   objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$kind-$label.code"      >"$TMP/$kind-$label.dis"
   grep -Eiq 'add[[:space:]]+eax,' "$TMP/$kind-$label.dis"
   grep -Eiq 'sub[[:space:]]+eax,' "$TMP/$kind-$label.dis"
   grep -Eiq 'cmp[[:space:]]+eax,ecx' "$TMP/$kind-$label.dis"
   grep -Eiq "$insn[[:space:]]+al" "$TMP/$kind-$label.dis"
   grep -Eiq 'movzx[[:space:]]+eax,al' "$TMP/$kind-$label.dis"
   timeout 5s "$target" >"$TMP/$kind-$label.out.sens"       2>"$TMP/$kind-$label.machine.err"
   test ! -s "$TMP/$kind-$label.machine.err"
   cmp "$expected_file" "$TMP/$kind-$label.out.sens"
   # EXACT image equality: без власного emitter і нової SENS семантики.
   timeout 20s "$TMP/bin/$old" "$oldmode" "$source"      "$TMP/$kind-$label.old.elf" >"$TMP/old.out" 2>"$TMP/old.err"
   heap_ok "$TMP/old.err"
   cmp "$target" "$TMP/$kind-$label.old.elf"
   timeout 20s "$CLI" "$MODE" "$source" "$TMP/$kind-$label.again.elf"      >"$TMP/again.out" 2>"$TMP/again.err"
   cmp "$target" "$TMP/$kind-$label.again.elf"
   if [[ -n "$ORACLE" ]]; then
     timeout 60s "$ORACLE" "$source" >"$TMP/oracle.out" 2>"$TMP/oracle.err"
     test ! -s "$TMP/oracle.err"
     oracle_d1 "$TMP/oracle.out" "$expected"
     PINNED=$((PINNED+1))
   fi
   if [[ $expected == 1 ]]; then T=$((T+1)); else F=$((F+1)); fi
   PASS=$((PASS+1))
 done <"$TMP/$kind.tsv"
done
test "$PASS" -eq 48 && test "$T" -gt 0 && test "$F" -gt 0
if [[ -n "$ORACLE" ]]; then test "$PINNED" -eq 48; fi
reject() {
 local label=$1;shift
 local dest="$TMP/declined-$label.elf" rc=0
 timeout 20s "$CLI" "$@" "$dest"      >"$TMP/reject.out" 2>"$TMP/reject.err" || rc=$?
 test "$rc" -eq 2 && test ! -e "$dest" && test ! -L "$dest"
 test ! -s "$TMP/reject.out"
 grep -Fq 'ДВОГІЛКОВИЙ-СПІЛЬНИЙ-ELF-ВІДМОВА:' "$TMP/reject.err"
 heap_ok "$TMP/reject.err"
 NEG=$((NEG+1))
}
for kind in eq less greater; do
 for file in "$TMP/$kind"/bad-*.sens; do
   # Чужий корінь є *коректним* окремим pinned профілем, не негатив.
   [[ ${file##*/} == bad-root.sens ]] && continue
   reject "$kind-${file##*/}" "$MODE" "$file"
 done
done
test "$NEG" -eq 57
reject projection "$MODE" "$TMP/eq/fake.lisp"
reject missing "$MODE" "$TMP/eq/nonexistent.sens"
reject mode --неіснуючий "$TMP/eq/01-program.sens"
test "$NEG" -eq 60

cp "$TMP/eq-01.elf" "$TMP/occupied.elf"
rc=0
timeout 20s "$CLI" "$MODE" "$TMP/less/02-program.sens" "$TMP/occupied.elf"  >"$TMP/clobber.out" 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/clobber.out"
cmp "$TMP/eq-01.elf" "$TMP/occupied.elf"
ln -s "$TMP/no-target.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$CLI" "$MODE" "$TMP/greater/01-program.sens" "$TMP/dangling.elf"  >"$TMP/symlink.out" 2>"$TMP/symlink.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf" && test ! -e "$TMP/no-target.elf"
test ! -s "$TMP/symlink.out"
timeout 20s "$CLI" "$MODE" "$TMP/eq/05-program.sens" "$TMP/recovered.elf"  >"$TMP/recovery.out" 2>"$TMP/recovery.err"
test -x "$TMP/recovered.elf"
timeout 5s "$TMP/recovered.elf" >"$TMP/recovered.sens"
cmp "$TMP/eq/05-expected.sens" "$TMP/recovered.sens"
echo "СПІЛЬНИЙ-ДВОГІЛКОВИЙ-ГАРАЗД фізичних=$PASS pinned-oracle=$PINNED позитивних=$T негативних=$F відмов=$NEG ELF=48 binary-identical=48 SETE_SETL_SETG=так D1=T5M energy=NOT_MEASURED"
