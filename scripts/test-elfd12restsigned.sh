#!/usr/bin/env bash
# G6.184: 14 existing + 6 signed Д6 остача, same compiled x86-64 ELF.
# Numeric host expectations are fixtures ONLY; pinned SENS REPL is oracle.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for tool in fpc git timeout readelf python3 cmp sha256sum mktemp grep;do
  command -v "$tool" >/dev/null || { echo "Д6-ЗНАК-БЛОК: немає $tool" >&2;exit 127; }
done
timeout 180s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
grep -Fq '(010100 (ук остача) (укр остача)' external/sens/lib/domains/d6.lisp
ORACLE=$(printenv SENS_ORACLE_BIN || true)
REQUIRE=$(printenv REQUIRE_SENS_ORACLE || echo 0)
if [[ "$REQUIRE" == 1 && -z "$ORACLE" ]];then
  echo 'Д6-ЗНАК-БЛОК: pinned SENS oracle обов’язковий' >&2;exit 127
fi
if [[ -n "$ORACLE" ]];then
  test -x "$ORACLE"
  test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
fi
TMP=$(mktemp -d)
cleanup(){
  local rc=$? file
  if ((rc!=0));then
    echo "Д6-ЗНАК-ПРОВАЛ rc=$rc" >&2
    for file in "$TMP"/*.log "$TMP"/*.err;do
      [[ ! -s "$file" ]] || { echo "--- $file" >&2;tail -n 40 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/anchors" "$TMP/frames"
for spec in \
 'scripts/test-elfd12restpotik.pas test-elfd12restpotik' \
 'scripts/test-irwiderest.pas test-irwiderest' \
 'src/sensd12restsigned.lpr sensd12restsigned' \
 'src/senschyslo.lpr senschyslo';do
  read -r src name <<<"$spec"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$src" >"$TMP/$name.log" 2>&1 || {
      cat "$TMP/$name.log" >&2;exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 35s "$TMP/bin/test-elfd12restpotik" "$TMP/frames" >"$TMP/fixtures.log"
timeout 35s "$TMP/bin/test-irwiderest" "$TMP/anchors" >"$TMP/anchors.log"
test "$(wc -l <"$TMP/frames/cases.tsv")" -eq 14
MODE=--зібрати-D6-остачу-зі-знаком
ELF="$TMP/остача.elf"
timeout 50s "$TMP/bin/sensd12restsigned" "$MODE" \
  "$TMP/anchors/04.sens" "$ELF" >"$TMP/compile.log" 2>"$TMP/compile.err"
test -x "$ELF" && test ! -s "$TMP/compile.err"
grep -Fq 'machine=CDQ_IDIV_R9D stdin=2xT5M-D12 stdout=T5M-D12' "$TMP/compile.log"
timeout 50s "$TMP/bin/sensd12restsigned" "$MODE" \
  "$TMP/anchors/04.sens" "$TMP/repeat.elf" >"$TMP/repeat.log"
cmp "$ELF" "$TMP/repeat.elf"
readelf -h "$ELF" >"$TMP/header.log"
readelf -l "$ELF" >"$TMP/segments.log"
grep -Eq 'Type:[[:space:]]+DYN' "$TMP/header.log"
! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
python3 - "$ELF" <<'PY'
import struct,sys
from pathlib import Path
b=Path(sys.argv[1]).read_bytes()
assert b[:4]==b'\x7fELF' and 120<len(b)<8192
assert struct.unpack_from('<Q',b,96)[0]==len(b)
assert struct.unpack_from('<Q',b,104)[0]==len(b)
needle=bytes.fromhex('41 f7 f9 e9')
assert b.count(needle)==1, 'бракує єдиного IDIV та JMP до корекції'
assert b.count(bytes.fromhex('41 f7 f9'))==1
assert b.count(bytes.fromhex('44 89 c0 99 45 85 c9 0f 84'))==1
assert bytes.fromhex('85 d2 0f 84') in b, 'немає JE zero-rem guard'
assert bytes.fromhex('89 d1 44 31 c9 0f 89') in b, 'немає XOR-перевірки знаків'
assert bytes.fromhex('44 01 ca') in b, 'немає поправки знаку дільника'
assert b'\x48\x83\xf8\x05\x0f\x85' in b, 'втрачено перевірений T5M D24 writer'
print('Д6-ЗНАК-МАШИНА-ГОТОВО IDIV=1 floor-modulo=так reject-zero=так EOF=так')
PY
HASH=$(sha256sum "$ELF" | cut -d' ' -f1)
PASS=0
SIGNED=0
ORACLE_PASS=0
verify(){
  local name="$1" a="$2" b="$3" answer="$4" expected="$5" attempt
  for attempt in 1 2;do
    timeout 7s "$ELF" <"$TMP/frames/$name.frame" \
      >"$TMP/$name-$attempt.actual.sens" 2>"$TMP/$name-$attempt.err"
    test ! -s "$TMP/$name-$attempt.err"
    cmp "$expected" "$TMP/$name-$attempt.actual.sens"
    test "$(wc -c <"$TMP/$name-$attempt.actual.sens")" -eq 3
    test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
  done
  if [[ -n "$ORACLE" ]];then
    printf '(остача %s %s)\n' "$a" "$b" >"$TMP/$name.lisp"
    timeout 60s "$ORACLE" "$TMP/$name.lisp" \
      >"$TMP/$name.oracle.out" 2>"$TMP/$name.oracle.err"
    test ! -s "$TMP/$name.oracle.err"
    printf '%s\n' "$answer" >"$TMP/$name.oracle.want"
    cmp "$TMP/$name.oracle.want" "$TMP/$name.oracle.out"
    ORACLE_PASS=$((ORACLE_PASS+1))
  fi
  PASS=$((PASS+1))
}
while IFS=$'\t' read -r label a b;do
  test -n "$label"
  verify "$label" "$a" "$b" "$((a%b))" "$TMP/frames/$label.expected.sens"
done <"$TMP/frames/cases.tsv"
test "$PASS" -eq 14
# All 6 formerly rejected, exact signed T5M frames from original G6.120.
# Закон pinned Core4: a-b*floor(a/b); знак ненульової остачі — знак дільника.
# Expected numeric projection passes the existing D12 numeric-plane CLI.
while IFS=: read -r name a b expected;do
  printf '%s\n' "$expected" >"$TMP/$name.expected.lisp"
  timeout 25s "$TMP/bin/senschyslo" --з-укр D12 \
    "$TMP/$name.expected.lisp" "$TMP/$name.expected.sens" \
    >"$TMP/$name.encode.log" 2>"$TMP/$name.encode.err"
  test ! -s "$TMP/$name.encode.err"
  verify "$name" "$a" "$b" "$expected" "$TMP/$name.expected.sens"
  SIGNED=$((SIGNED+1))
done <<'CASES'
negative-left:-1:3:2
negative-right:7:-3:-2
both-negative:-7:-3:-1
min-left:-2048:3:1
min-right:7:-2048:-2041
negative-minus-one:2047:-1:0
CASES
test "$PASS" -eq 20 && test "$SIGNED" -eq 6
if [[ -n "$ORACLE" ]];then test "$ORACLE_PASS" -eq 20;fi

NEG=0
reject(){
  local name="$1" rc=0
  timeout 7s "$ELF" <"$TMP/frames/$name.frame" \
    >"$TMP/reject.actual.sens" 2>"$TMP/reject.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/reject.actual.sens"
  grep -Fq 'ВІДМОВА' "$TMP/reject.err"
  NEG=$((NEG+1))
}
for name in zero-divisor both-zero empty short1 short5 extra newline \
            invalid243 badfirst badsecond badthird badlast projection d1;do
  reject "$name"
done
test "$NEG" -eq 14
ANCHOR_NEG=0
for name in div-zero.sens bad-t5m.sens min-left.sens;do
  rc=0
  timeout 30s "$TMP/bin/sensd12restsigned" "$MODE" \
    "$TMP/anchors/$name" "$TMP/invalid-$ANCHOR_NEG.elf" \
    >"$TMP/invalid.out" 2>"$TMP/invalid.err" || rc=$?
  test "$rc" -eq 2 && test ! -s "$TMP/invalid.out"
  test ! -e "$TMP/invalid-$ANCHOR_NEG.elf"
  ANCHOR_NEG=$((ANCHOR_NEG+1))
done
printf '(остача 7 3)\n' >"$TMP/fake.lisp"
rc=0
timeout 30s "$TMP/bin/sensd12restsigned" "$MODE" \
  "$TMP/fake.lisp" "$TMP/invalid-$ANCHOR_NEG.elf" \
  >"$TMP/invalid.out" 2>"$TMP/invalid.err" || rc=$?
test "$rc" -eq 2 && test ! -e "$TMP/invalid-$ANCHOR_NEG.elf"
ANCHOR_NEG=$((ANCHOR_NEG+1))
test "$ANCHOR_NEG" -eq 4
cp "$ELF" "$TMP/occupied.elf"
rc=0
timeout 30s "$TMP/bin/sensd12restsigned" "$MODE" \
  "$TMP/anchors/04.sens" "$TMP/occupied.elf" \
  >"$TMP/clobber.out" 2>"$TMP/clobber.err" || rc=$?
test "$rc" -eq 2 && test ! -s "$TMP/clobber.out"
cmp "$ELF" "$TMP/occupied.elf"
ln -s "$TMP/absent.elf" "$TMP/dangling.elf"
rc=0
timeout 30s "$TMP/bin/sensd12restsigned" "$MODE" \
  "$TMP/anchors/04.sens" "$TMP/dangling.elf" \
  >"$TMP/symlink.out" 2>"$TMP/symlink.err" || rc=$?
test "$rc" -eq 2 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/absent.elf"
timeout 30s "$TMP/bin/sensd12restsigned" "$MODE" \
  "$TMP/anchors/04.sens" "$TMP/recovery.elf" >/dev/null
timeout 7s "$TMP/recovery.elf" <"$TMP/frames/min-left.frame" \
  >"$TMP/recovery.sens"
cmp "$TMP/min-left.expected.sens" "$TMP/recovery.sens"
test "$(sha256sum "$ELF" | cut -d' ' -f1)" = "$HASH"
echo "Д6-ОСТАЧА-ЗНАК-ГАРАЗД d12=$PASS signed=$SIGNED negatives=$NEG anchors=$ANCHOR_NEG oracle=$ORACLE_PASS native=IDIV energy=NOT-MEASURED"
