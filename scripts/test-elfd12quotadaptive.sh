#!/usr/bin/env bash
# G6.178 — нова реальна машинна D5 частка: D12 або D24 stdout.
# Позитивні pinned .sens + незалежний SENS REPL у PR oracle job.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for exe in fpc git timeout cmp grep readelf python3 mktemp sha256sum;do
  command -v "$exe" >/dev/null || { echo "АДАПТИВНА-ЧАСТКА-БЛОК: немає $exe" >&2;exit 127; }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 180s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(10111 (ук частка) (укр частка)' external/sens/lib/domains/d5.lisp
grep -Fq '(01010 (ук додати) (укр додати)' external/sens/lib/domains/d5.lisp
ORACLE=$(printenv SENS_ORACLE_BIN || true)
REQUIRED=$(printenv REQUIRE_SENS_ORACLE || echo 0)
if [[ "$REQUIRED" == 1 && -z "$ORACLE" ]];then
  echo 'АДАПТИВНА-ЧАСТКА-БЛОК: незалежний pinned SENS oracle відсутній' >&2;exit 127;
fi
if [[ -n "$ORACLE" ]];then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP=$(mktemp -d)
finish(){
  local rc=$? f
  if ((rc!=0));then
    echo "АДАПТИВНА-ЧАСТКА-ПРОВАЛ: код=$rc" >&2
    for f in "$TMP"/*.build.log "$TMP"/*.err "$TMP"/*.log;do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 28 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical" "$TMP/invalid"
for spec in \
 'scripts/test-elfd12quotpotik.pas test-elfd12quotpotik' \
 'scripts/test-irwidequot.pas test-irwidequot' \
 'src/sensd12quotadaptive.lpr sensd12quotadaptive' \
 'src/senschyslo.lpr senschyslo';do
  read -r src name <<<"$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$src" >"$TMP/$name.build.log" 2>&1 || {
      cat "$TMP/$name.build.log" >&2;exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 30s "$TMP/bin/test-elfd12quotpotik" "$TMP/physical" \
  >"$TMP/generator.log" 2>"$TMP/generator.err"
grep -Fq 'positive=25 numeric-reject=7 frame-reject=11' "$TMP/generator.log"
timeout 30s "$TMP/bin/test-irwidequot" "$TMP/invalid" \
  >"$TMP/old-generator.log" 2>"$TMP/old-generator.err"
grep -Fq 'cases=22 negatives=21' "$TMP/old-generator.log"
check_heap(){
  if grep -Fq 'unfreed memory blocks' "$1";then
    grep -Fq '0 unfreed memory blocks' "$1"
  fi
}
check_heap "$TMP/generator.err"
check_heap "$TMP/old-generator.err"

MODE=--зібрати-адаптивну-D5-частку
ELF="$TMP/адаптивна-частка.elf"
timeout 70s "$TMP/bin/sensd12quotadaptive" "$MODE" \
  "$TMP/physical/anchor.sens" "$ELF" \
  >"$TMP/compile.log" 2>"$TMP/compile.err"
test ! -s "$TMP/compile.err" && test -x "$ELF"
grep -Fq 'machine=CDQ_IDIV_R9D stdin=2xT5M-D12 stdout=T5M-D12-or-D24' \
  "$TMP/compile.log"
timeout 60s "$TMP/bin/sensd12quotadaptive" "$MODE" \
  "$TMP/physical/07.sens" "$TMP/rebuilt.elf" \
  >"$TMP/rebuilt.log" 2>"$TMP/rebuilt.err"
test ! -s "$TMP/rebuilt.err"
cmp "$ELF" "$TMP/rebuilt.elf"
sha=$(sha256sum "$ELF" | cut -d' ' -f1)
readelf -h "$ELF" >"$TMP/header.log"
readelf -l "$ELF" >"$TMP/segments.log"
grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header.log"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
python3 - "$ELF" <<'PY'
from pathlib import Path
import struct,sys
b=Path(sys.argv[1]).read_bytes()
assert b[:4]==b'\x7fELF' and len(b)<8192
assert struct.unpack_from('<Q',b,96)[0]==len(b)
assert struct.unpack_from('<Q',b,104)[0]==len(b)
needle=bytes.fromhex('44 89 c0 99 45 85 c9 0f 84')
assert b.count(needle)==1, 'немає IDIV code island'
start=b.index(needle)
assert b[start+13:start+16]==bytes.fromhex('41 f7 f9')
assert b[start+16:start+20]==bytes.fromhex('85 d2 0f 85')
assert b.count(bytes.fromhex('41 f7 f9'))==1
assert bytes.fromhex('81 e3 ff ff ff 00') in b, 'немає D24 mask'
assert bytes.fromhex('48 83 f8 05 0f 85') in b, 'немає write(5) guard'
print('АДАПТИВНА-ЧАСТКА-МАШИНА-ПІДТВЕРДЖЕНО IDIV=1 D24=так')
PY
PASS=0;WIDE=0;ORACLE_PASS=0
while IFS=$'\t' read -r name a b expected;do
  test -n "$name"
  for attempt in 1 2;do
    timeout 7s "$ELF" <"$TMP/physical/$name.frame" \
      >"$TMP/$name-$attempt.actual.sens" \
      2>"$TMP/$name-$attempt.err"
    test ! -s "$TMP/$name-$attempt.err"
    cmp "$TMP/physical/$name.expected.sens" "$TMP/$name-$attempt.actual.sens"
    test "$(wc -c <"$TMP/$name-$attempt.actual.sens")" -eq 3
  done
  if [[ -n "$ORACLE" ]];then
    timeout 60s "$ORACLE" "$TMP/physical/$name.sens" \
      >"$TMP/$name.oracle.out" 2>"$TMP/$name.oracle.err"
    test ! -s "$TMP/$name.oracle.err"
    printf '%s\n' "$expected" >"$TMP/$name.oracle.want"
    cmp "$TMP/$name.oracle.want" "$TMP/$name.oracle.out"
    ORACLE_PASS=$((ORACLE_PASS+1))
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 25

# У signed D12 лише -2048/-1 може дати цілу частку >2047.
# Саме фізичний D24 numeric encoder породжує expected, не host ASCII.
printf '2048\n' >"$TMP/2048.ukr"
timeout 15s "$TMP/bin/senschyslo" --з-укр D24 \
  "$TMP/2048.ukr" "$TMP/promotion.expected.sens" \
  >"$TMP/encode.log" 2>"$TMP/encode.err"
test ! -s "$TMP/encode.err"
test "$(wc -c <"$TMP/promotion.expected.sens")" -eq 5
for attempt in 1 2;do
  timeout 7s "$ELF" <"$TMP/physical/promotion.frame" \
    >"$TMP/promotion-$attempt.actual.sens" \
    2>"$TMP/promotion-$attempt.err"
  test ! -s "$TMP/promotion-$attempt.err"
  cmp "$TMP/promotion.expected.sens" "$TMP/promotion-$attempt.actual.sens"
  test "$(wc -c <"$TMP/promotion-$attempt.actual.sens")" -eq 5
done
WIDE=1
if [[ -n "$ORACLE" ]];then
  timeout 60s "$ORACLE" "$TMP/physical/promotion.sens" \
    >"$TMP/promotion.oracle.out" 2>"$TMP/promotion.oracle.err"
  test ! -s "$TMP/promotion.oracle.err"
  cmp "$TMP/2048.ukr" "$TMP/promotion.oracle.out"
  ORACLE_PASS=$((ORACLE_PASS+1))
fi
if [[ -n "$ORACLE" ]];then test "$ORACLE_PASS" -eq 26;fi

NEG=0
reject_frame(){
  local source="$1" rc=0
  timeout 7s "$ELF" <"$source" >"$TMP/negative.out" \
    2>"$TMP/negative.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/negative.out"
  grep -Fq 'ВІДМОВА' "$TMP/negative.err"
  NEG=$((NEG+1))
}
while IFS=$'\t' read -r name a b;do
  [[ "$name" == promotion ]] && continue
  reject_frame "$TMP/physical/$name.frame"
done <"$TMP/physical/numeric-reject.tsv"
for name in empty short1 short5 extra newline invalid243 badfirst \
            badsecond badlast projection d1;do
  reject_frame "$TMP/physical/$name.frame"
done
test "$NEG" -eq 17
ANCHOR_NEG=0
reject_anchor(){
  local source="$1" dest="$TMP/reject-$ANCHOR_NEG.elf" rc=0
  timeout 45s "$TMP/bin/sensd12quotadaptive" "$MODE" \
    "$source" "$dest" >"$TMP/anchor-reject.out" \
    2>"$TMP/anchor-reject.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/anchor-reject.out"
  test ! -e "$dest" && test ! -L "$dest"
  grep -Fq 'Д5-ЧАСТКА-АДАПТИВНА-ВІДМОВА:' "$TMP/anchor-reject.err"
  ANCHOR_NEG=$((ANCHOR_NEG+1))
}
for name in wrong-d5 wrong-d6 wrong-width missing extra \
            dotted two-roots zero unequal bad-t5m empty;do
  reject_anchor "$TMP/invalid/$name.sens"
done
reject_anchor "$TMP/invalid/fake.lisp"
test "$ANCHOR_NEG" -eq 12
cp "$ELF" "$TMP/existing.elf"
rc=0
timeout 30s "$TMP/bin/sensd12quotadaptive" "$MODE" \
  "$TMP/physical/anchor.sens" "$TMP/existing.elf" \
  >"$TMP/clobber.out" 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/clobber.out"
cmp "$ELF" "$TMP/existing.elf"
ln -s "$TMP/absent.elf" "$TMP/dangling.elf"
rc=0
timeout 30s "$TMP/bin/sensd12quotadaptive" "$MODE" \
  "$TMP/physical/anchor.sens" "$TMP/dangling.elf" \
  >"$TMP/symlink.out" 2>"$TMP/symlink.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/absent.elf"
timeout 30s "$TMP/bin/sensd12quotadaptive" "$MODE" \
  "$TMP/physical/anchor.sens" "$TMP/recovered.elf" >/dev/null
timeout 7s "$TMP/recovered.elf" <"$TMP/physical/promotion.frame" \
  >"$TMP/recovered.sens"
cmp "$TMP/recovered.sens" "$TMP/promotion.expected.sens"
test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$sha"
echo "Д5-ЧАСТКА-АДАПТИВНА-ГАРАЗД d12=$PASS d24=$WIDE signed=так machine=IDIV oracle=$ORACLE_PASS negatives=$NEG anchors=$ANCHOR_NEG no-clobber=2 energy=NOT-MEASURED"
