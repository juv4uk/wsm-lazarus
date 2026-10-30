#!/usr/bin/env bash
# G6.161: один ELF64 PIE і 25 реальних пар runtime D12 T5M.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for exe in fpc git timeout cmp grep readelf python3 mktemp sha256sum;do
  command -v "$exe" >/dev/null || { echo "Д5-ЧАСТКА: бракує $exe" >&2;exit 127; }
done
timeout 180s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
git -C external/sens show "$PIN:lib/domains/d5.lisp" |
  grep -Fq '(10111 (ук частка) (укр частка)'
ORACLE=$(printenv SENS_ORACLE_BIN || true)
REQUIRED=$(printenv REQUIRE_SENS_ORACLE || echo 0)
if [[ "$REQUIRED" == 1 && -z "$ORACLE" ]];then
  echo 'Д5-ЧАСТКА: pinned oracle обов’язковий' >&2;exit 127
fi
if [[ -n "$ORACLE" ]];then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP=$(mktemp -d)
finish(){
  local rc=$? f
  if ((rc!=0));then
    echo "Д5-ЧАСТКА-ПРОВАЛ: рядок=$1 код=$rc" >&2
    for f in "$TMP"/*.build.log "$TMP"/*.err "$TMP"/*.log;do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 18 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap 'finish "$LINENO"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical" "$TMP/invalid"
for spec in \
 'scripts/test-elfd12quotpotik.pas test-elfd12quotpotik' \
 'scripts/test-irwidequot.pas test-irwidequot' \
 'src/sensd12quotpotikelf.lpr sensd12quotpotikelf';do
  read -r src name <<<"$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$src" >"$TMP/$name.build.log" 2>&1 || {
      cat "$TMP/$name.build.log" >&2;exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 40s "$TMP/bin/test-elfd12quotpotik" "$TMP/physical" \
  >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Fq 'positive=25 numeric-reject=7 frame-reject=11' "$TMP/generator.log"
timeout 45s "$TMP/bin/test-irwidequot" "$TMP/invalid" \
  >"$TMP/old-generator.log" 2>"$TMP/old-generator.err"
grep -Fq 'cases=22 negatives=21' "$TMP/old-generator.log"
check_heap(){
  if grep -Fq 'unfreed memory blocks' "$1";then
    grep -Fq '0 unfreed memory blocks' "$1"
  fi
}
check_heap "$TMP/generator.err"
check_heap "$TMP/old-generator.err"
ELF="$TMP/частка-runtime.elf"
MODE=--зібрати-D5-частку-потік
timeout 50s "$TMP/bin/sensd12quotpotikelf" "$MODE" \
  "$TMP/physical/anchor.sens" "$ELF" \
  >"$TMP/compile.log" 2>"$TMP/compile.err"
test ! -s "$TMP/compile.err" && test -x "$ELF"
grep -Fq 'machine=CDQ_IDIV_R9D stdin=2xT5M-D12 stdout=T5M-D12' \
  "$TMP/compile.log"
timeout 40s "$TMP/bin/sensd12quotpotikelf" "$MODE" \
  "$TMP/physical/anchor.sens" "$TMP/repeat.elf" >/dev/null \
  2>"$TMP/recompile.err"
test ! -s "$TMP/recompile.err"
cmp "$ELF" "$TMP/repeat.elf"
sha=$(sha256sum "$ELF" | cut -d' ' -f1)
readelf -h "$ELF" >"$TMP/elf-header.log"
grep -Eq 'Type:[[:space:]]+DYN' "$TMP/elf-header.log"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf-header.log"
! readelf -l "$ELF" | grep -Eq 'INTERP|DYNAMIC'
python3 - "$ELF" <<'PY'
from pathlib import Path
import sys,struct
b=Path(sys.argv[1]).read_bytes()
assert b[:4]==b'\x7fELF' and len(b)>120
assert struct.unpack_from('<Q',b,96)[0]==len(b)
assert struct.unpack_from('<Q',b,104)[0]==len(b)
needle=bytes.fromhex('44 89 c0 99 45 85 c9 0f 84')
assert b.count(needle)==1
start=b.index(needle)
assert b[start+13:start+16]==bytes.fromhex('41 f7 f9')
assert b[start+16:start+20]==bytes.fromhex('85 d2 0f 85')
assert b.count(bytes.fromhex('41 f7 f9'))==1
assert any(i+5+struct.unpack_from('<i',b,i+1)[0]==start
           for i in range(120,start-5) if b[i]==0xe9)
print('Д5-ЧАСТКА-МАШИНА-ПІДТВЕРДЖЕНО CDQ=1 IDIV=1 guarded=так')
PY
PASS=0;ORACLE_PASS=0
while IFS=$'\t' read -r name a b expected;do
  test -n "$name"
  for attempt in 1 2;do
    timeout 7s "$ELF" <"$TMP/physical/$name.frame" \
      >"$TMP/$name-$attempt.actual.sens" \
      2>"$TMP/$name-$attempt.machine.err"
    test ! -s "$TMP/$name-$attempt.machine.err"
    cmp "$TMP/physical/$name.expected.sens" "$TMP/$name-$attempt.actual.sens"
    test "$(wc -c <"$TMP/$name-$attempt.actual.sens")" -eq 3
    test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$sha"
  done
  cmp "$TMP/$name-1.actual.sens" "$TMP/$name-2.actual.sens"
  if [[ -n "$ORACLE" ]];then
    timeout 60s "$ORACLE" "$TMP/physical/$name.sens" \
      >"$TMP/$name.oracle.log" 2>"$TMP/$name.oracle.err"
    test ! -s "$TMP/$name.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$name.oracle.want"
    cmp "$TMP/$name.oracle.want" "$TMP/$name.oracle.log"
    ORACLE_PASS=$((ORACLE_PASS+1))
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 25
if [[ -n "$ORACLE" ]];then test "$ORACLE_PASS" -eq 25;fi
NEG=0
reject_frame(){
  local source="$1" rc=0
  timeout 7s "$ELF" <"$source" >"$TMP/negative.out" \
    2>"$TMP/negative.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/negative.out"
  grep -Fq 'ВІДМОВА' "$TMP/negative.err"
  NEG=$((NEG+1))
}
while IFS=$'\t' read -r name a b;do
  test -n "$name"
  reject_frame "$TMP/physical/$name.frame"
done <"$TMP/physical/numeric-reject.tsv"
for name in empty short1 short5 extra newline invalid243 badfirst \
            badsecond badlast projection d1;do
  reject_frame "$TMP/physical/$name.frame"
done
test "$NEG" -eq 18
ANCHOR_NEG=0
reject_anchor(){
  local source="$1" dest="$TMP/reject-$ANCHOR_NEG.elf" rc=0
  timeout 30s "$TMP/bin/sensd12quotpotikelf" "$MODE" \
    "$source" "$dest" >"$TMP/anchor-reject.out" \
    2>"$TMP/anchor-reject.err" || rc=$?
  test "$rc" -eq 2
  test ! -s "$TMP/anchor-reject.out"
  test ! -e "$dest" && test ! -L "$dest"
  grep -Fq 'Д5-ЧАСТКА-ПОТІК-ВІДМОВА:' "$TMP/anchor-reject.err"
  ANCHOR_NEG=$((ANCHOR_NEG+1))
}
for name in wrong-d5 wrong-d6 wrong-width missing extra \
            dotted two-roots zero unequal bad-t5m empty;do
  reject_anchor "$TMP/invalid/$name.sens"
done
reject_anchor "$TMP/invalid/fake.lisp"
test "$ANCHOR_NEG" -eq 12
cp "$ELF" "$TMP/occupied.elf"
rc=0
timeout 20s "$TMP/bin/sensd12quotpotikelf" "$MODE" \
  "$TMP/physical/anchor.sens" "$TMP/occupied.elf" \
  >"$TMP/clobber.out" 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/clobber.out"
cmp "$ELF" "$TMP/occupied.elf"
ln -s "$TMP/absent.elf" "$TMP/dangling.elf"
rc=0
timeout 20s "$TMP/bin/sensd12quotpotikelf" "$MODE" \
  "$TMP/physical/anchor.sens" "$TMP/dangling.elf" \
  >"$TMP/symlink.out" 2>"$TMP/symlink.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/absent.elf"
timeout 30s "$TMP/bin/sensd12quotpotikelf" "$MODE" \
  "$TMP/physical/anchor.sens" "$TMP/recovered.elf" >/dev/null
timeout 7s "$TMP/recovered.elf" <"$TMP/physical/25.frame" \
  >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/physical/25.expected.sens"
echo "Д5-ЧАСТКА-ПОТІК-ГАРАЗД machine=$PASS pinned-oracle=$ORACLE_PASS signed=так numeric-reject=7 frame-reject=11 anchor-reject=$ANCHOR_NEG byte-exact=так повтори=так no-clobber=2 energy=NOT-MEASURED"
